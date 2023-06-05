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

    address[] private collateralTokens;

    uint256 private constant FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200%
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATOR_BONUS = 10; //this means 10% bonus
    uint8 private constant MIN_HEALTH_FACTOR = 1;

    ////////////////////////////////////////////////////////////////////////////////////////////////
    ////?????????????????????????????????????? (MODIFIERS) ?????????????????????????????????????////
    ////////////////////////////////////////////////////////////////////////////////////////////////

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

    /////////////////////////////////////////////////////////////////////////////////////////////////
    ////????????????????????????????????? (EXTERNAL FUNCTIONS) ??????????????????????????????????////                                                  ///
    /////////////////////////////////////////////////////////////////////////////////////////////////

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
        userCollateralDeposited[msg.sender][collateralTokenAddress] -= collateralAmount;

        emit CollateralRedeemed(msg.sender, collateralTokenAddress, collateralAmount);

        bool success = IERC20(collateralTokenAddress).transfer(msg.sender, collateralAmount);

        if (!success) revert DSCEngine_TransferFailed();

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////
    ////!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! PUBLIC FUNCTIONS !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!////
    /////////////////////////////////////////////////////////////////////////////////////////////////

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
        burnDsc(msg.sender, amountToBurn);
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

    function burnDsc(address from, uint256 dscAmountToBurn) public moreThanZero(dscAmountToBurn) returns (bool) {
        userDscMinted[msg.sender] -= dscAmountToBurn;

        bool success = dsc.transferFrom(msg.sender, address(this), dscAmountToBurn);
        if (!success) revert DSCEngine_TransferFailed();

        dsc.burn(dscAmountToBurn);

        _revertIfHealthFactorIsBroken(msg.sender);
        return success;
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

    function liquidate(address collateralTokenAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
    {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor >= MIN_HEALTH_FACTOR) revert DSCEngine_HealthFactorOk();
        // We want to burn their DSC "debt"
        // And take their collateral
        // Bad user: $140 ETH, $100 DSC
        // debtToCover = $100
        // $100 of DSC == ??? DSC

        uint256 amountOfDebtCovered = getTokenAmountFromUSD(collateralTokenAddress, debtToCover);
        // and give them a 10% bonus
        // so we are giving the liquidator $110 of wETH for 100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent

        // 0.05 Eth * 0.1 = 0.005.Getting 0.055
        uint256 bonusCollateral = (amountOfDebtCovered * LIQUIDATION_PRECISION) / LIQUIDATOR_BONUS;

        uint256 totalCollateralToRedeem = amountOfDebtCovered + bonusCollateral;
    }

    function getHealthFactor(address user) external view returns (uint256) {}

    function getUserCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i; i < collateralTokens.length;) {
            address token = collateralTokens[i];
            uint256 amount = userCollateralDeposited[user][token];
            totalCollateralValueInUsd += getValueInUSD(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getValueInUSD(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(tokenToPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * FEED_PRECISION) * amount) / PRECISION;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////
    ////************************************ DSCENGINE FUNCTIONS ********************************////
    /////////////////////////////////////////////////////////////////////////////////////////////////
    function getTokenAmountFromUSD(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // price of ETH (token)
        // $/ETH Eth??
        // $2000 / Eth. $1000 = 0.5 eth
        AggregatorV3Interface priceFeed = AggregatorV3Interface(tokenToPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * FEED_PRECISION);
    }

    function getAccountInfo(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 totalCollateralValueInUsd)
    {
        totalDscMinted = userDscMinted[user];
        totalCollateralValueInUsd = getUserCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = getAccountInfo(user);
        uint256 collateralRatio = (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralRatio * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 healthFactor = _healthFactor(user);

        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine_CriticalHealthFactor(healthFactor);
        }
    }
}
