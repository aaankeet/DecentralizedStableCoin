// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title DSCEngine
 * @author (www.github.com/aaankeet)
 *
 * The system is deisgned to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exegenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

import {ReentrancyGuard} from "@oz/security/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";

import "./Interfaces/IDSCEngine.sol";
import "./Interfaces/IDecentralizedStableCoin.sol";

contract DSCEngine is IDSCEngine, ReentrancyGuard {
    ///////////////////////
    /// STATE VARIABLES ///
    ///////////////////////
    IDecentralizedStableCoin public dsc;

    mapping(address token => address priceFeeds) public tokenToPriceFeeds;

    mapping(address user => mapping(address token => uint256 amount)) private userCollateralDeposited;

    mapping(address user => uint256 amount) private userDscMinted;

    uint8 public constant MIN_HEALTH_FACTOR = 1;
    uint8 public constant LIQUIDATION_THRESHOLD = 50; // 200%
    uint8 public constant LIQUIDATION_PRECISION = 100;
    uint8 public constant LIQUIDATOR_BONUS = 10; //this means 10% bonus

    uint256 public constant FEED_PRECISION = 1e10;
    uint256 public constant PRECISION = 1e18;

    address[] private collateralTokens;

    //////////////////////////////////////////////////////////////////////////////////////////////////
    //////?????????????????????????????????????? (MODIFIERS) ?????????????????????????????????????////
    //////////////////////////////////////////////////////////////////////////////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert DSCEngine_AmountMustBeAboveZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (tokenToPriceFeeds[token] == address(0)) revert DSCEngine_TokenNotAllowed();
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_TokenAndPriceFeedAddressMisMatch();
        }

        if (dscAddress == address(0)) revert DSCEngine_InvalidAddress();

        for (uint256 i; i < tokenAddresses.length;) {
            tokenToPriceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            collateralTokens.push(tokenAddresses[i]);

            unchecked {
                ++i;
            }
        }
        dsc = IDecentralizedStableCoin(dscAddress);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////
    //////????????????????????????????????? (EXTERNAL FUNCTIONS) ??????????????????????????????????////                                                  ///
    ///////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @param tokenAddress: The ERC20 token address of the collateral you're depositing
     * @param collateralAmount: The amount of collateral you're depositing
     * @param amountDscToMint: The amount of DSC you want to mint
     * @notice This function will deposit your collateral and mint DSC in one transaction
     */

    function depositCollateralAndMintDsc(address tokenAddress, uint256 collateralAmount, uint256 amountDscToMint)
        external
        returns (bool success)
    {
        depositCollateral(tokenAddress, collateralAmount);
        mintDsc(amountDscToMint);

        return success;
    }

    function redeemCollateral(address collateralTokenAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, collateralTokenAddress, collateralAmount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param collateralTokenAddress - The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user - The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover - The amount of DSC you want to burn to cover the user's debt.
     * @notice - You can partially liquidate a user.
     * @notice - You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice - this function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice - A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */

    function liquidate(address user, address collateralTokenAddress, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        returns (bool success)
    {
        // Get User's HealthFactor
        uint256 userStartingHealthFactor = _healthFactor(user);

        // Revert if User's Health Factor is not Low Enough to Liquidate
        if (userStartingHealthFactor >= MIN_HEALTH_FACTOR) revert DSCEngine_HealthFactorOk();

        // We want to burn User's DSC "debt"
        // And take their collateral
        // Bad user: $140 ETH Collateral, $100 DSC Holdings
        // debtToCover = $100
        // $100 of DSC == ??? DSC

        // Get the Value of debt the Liquidator is Covering for in USD.
        uint256 amountOfDebtCovered = getTokenAmountFromUSD(collateralTokenAddress, debtToCover);

        // And give them a 10% bonus
        // So we are giving the liquidator $110 of wETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent.

        // 0.05 Eth * 0.1 = 0.005.Getting 0.055

        // Calculate the bonus for liquidator for liquidating a user (10% bonus).
        uint256 bonusCollateral = (amountOfDebtCovered * LIQUIDATION_PRECISION) / LIQUIDATOR_BONUS;

        // Calculate the total amount of collateral the liquidator will receive (debtToCover + Bonus).
        uint256 totalCollateralToRedeem = amountOfDebtCovered + bonusCollateral;

        // Internal Function to Redeem Collateral From Target
        _redeemCollateral(user, msg.sender, collateralTokenAddress, totalCollateralToRedeem);

        // Now Burn total Debt covered by the Liquidator
        _burnDsc(msg.sender, user, debtToCover);

        // Get Target's Health Factor (Must Be Improved Since Liquidator Covered their Debt).
        uint256 userEndingHealthFactor = _healthFactor(user);

        // Revert if User's Health Factor is Not Improved
        if (userEndingHealthFactor <= userStartingHealthFactor) revert DSCEngine_UserHealthFactorNotImproved();

        // Also Revert If Liquidator's Health Factor Drops In the Proccess
        _revertIfHealthFactorIsBroken(msg.sender);

        return success;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////
    ////!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! PUBLIC FUNCTIONS !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!////
    /////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice - anyone can deposit collateral to avoid being liquidated
     * @param tokenAddress- token Address to provide as collateral
     * @param collateralAmount - amount of tokens to provide as collateral
     */

    function depositCollateral(address tokenAddress, uint256 collateralAmount)
        public
        isAllowedToken(tokenAddress)
        moreThanZero(collateralAmount)
        nonReentrant
        returns (bool)
    {
        userCollateralDeposited[msg.sender][tokenAddress] += collateralAmount;
        (bool success) = IERC20(tokenAddress).transferFrom(msg.sender, address(this), collateralAmount);

        if (!success) revert DSCEngine_TransferFailed();

        emit CollateralDeposited(msg.sender, tokenAddress, collateralAmount);

        return success;
    }

    /**
     *
     * @param collateralTokenAddress - collateral token address to redeem
     * @param collateralAmountToRedeem  - collateral amount to redeem
     * @param amountToBurn - amount of dsc to burn
     */

    function redeemCollateralForDsc(
        address collateralTokenAddress,
        uint256 collateralAmountToRedeem,
        uint256 amountToBurn
    ) external {
        _burnDsc(msg.sender, msg.sender, amountToBurn);
        redeemCollateral(collateralTokenAddress, collateralAmountToRedeem);
        // redeem collateral already checks health factor
    }

    /**
     * @param amountToMint - amount of DSC to mint
     * @notice - user must have the collateral value above minimun threshold
     */
    function mintDsc(uint256 amountToMint) public moreThanZero(amountToMint) returns (bool) {
        userDscMinted[msg.sender] += amountToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = IDecentralizedStableCoin(dsc).mint(msg.sender, amountToMint);
        if (!minted) revert DSCEngine_TransferFailed();

        emit DscMinted(msg.sender, amountToMint);
        return minted;
    }

    /**
     * @notice - Anyone can burn their DSC
     * @param dscAmountToBurn - Amount of DSC to Burn
     */
    function burnDsc(uint256 dscAmountToBurn) public moreThanZero(dscAmountToBurn) returns (bool) {
        _burnDsc(msg.sender, msg.sender, dscAmountToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // this condition wont hit but still

        return true;
    }

    /**
     * @notice - Get total Value of Collateral provided by a user
     * @param user - address of user to query for.
     */

    function getUserCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i; i < collateralTokens.length;) {
            address token = collateralTokens[i];
            uint256 amount = userCollateralDeposited[user][token];
            totalCollateralValueInUsd += getValueInUSD(token, amount);

            unchecked {
                ++i;
            }
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice - get the usd value of amount in wei for a token
     * @param token - token address
     * @param usdAmountInWei - amount of token in wei to query for
     */

    function getTokenAmountFromUSD(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // price of ETH (token)
        // $/ETH Eth??
        // $2000 / Eth. $1000 = 0.5 eth
        AggregatorV3Interface priceFeed = AggregatorV3Interface(tokenToPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * FEED_PRECISION);
    }

    function getValueInUSD(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(tokenToPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * FEED_PRECISION) * amount) / PRECISION;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////
    ////************************************ DSCENGINE FUNCTIONS ********************************////
    /////////////////////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev - Low level internal function
     */

    function _burnDsc(address from, address target, uint256 amountToBurn) private {
        userDscMinted[target] -= amountToBurn;

        bool success = dsc.transferFrom(from, address(this), amountToBurn);
        if (!success) revert DSCEngine_TransferFailed();

        dsc.burn(amountToBurn);
    }

    function _redeemCollateral(address from, address to, address collateralTokenAddress, uint256 collateralAmount)
        private
    {
        userCollateralDeposited[from][collateralTokenAddress] -= collateralAmount;

        emit CollateralRedeemed(from, to, collateralTokenAddress, collateralAmount);

        bool success = IERC20(collateralTokenAddress).transfer(to, collateralAmount);

        if (!success) revert DSCEngine_TransferFailed();
    }

    function getAccountInfo(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = userDscMinted[user];
        totalCollateralValueInUsd = getUserCollateralValue(user);

        return (totalDscMinted, totalCollateralValueInUsd);
    }

    function _healthFactor(address user) private view returns (uint256 healthFactor) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = getAccountInfo(user);
        uint256 collateralRatio = ((totalCollateralValueInUsd / 1e18) * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // cannot be divide by 0

        if (totalDscMinted == 0) {
            return type(uint256).max;
        }

        return healthFactor = (collateralRatio * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 healthFactor = _healthFactor(user);

        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_CriticalHealthFactor(healthFactor);
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function getUserDepositedCollateral(address user, address collateralTokenAddress) external view returns (uint256) {
        return userCollateralDeposited[user][collateralTokenAddress];
    }

    function getUseraAccountInfo(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        (totalDscMinted, totalCollateralValueInUsd) = getAccountInfo(user);
    }

    function getUserDscMinted(address user) external view returns (uint256) {
        return userDscMinted[user];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
