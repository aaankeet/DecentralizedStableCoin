// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {MockV3Aggregator} from "../Mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@oz/mocks/ERC20Mock.sol";
import {MockDSC} from "../Mocks/MockDebtDsc.sol";

error DSCEngine_InvalidTokenAddress();
error DSCEngine_InvalidAddress();
error DSCEngine_TokenNotAllowed();
error DSCEngine_AmountMustBeAboveZero();
error DSCEngine_TokenAndPriceFeedAddressMisMatch();
error DSCEngine_TransferFailed();
error DSCEngine_CriticalHealthFactor(uint256 healthFactor);
error DSCEngine_HealthFactorOk();
error DSCEngine_UserHealthFactorNotImproved();

contract DSCEngineTest is Test {
    DeployDsc deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;

    address public wEth;
    address public wBtc;

    address public ethPriceFeed;
    address public btcPriceFeed;

    address public ALICE = makeAddr("Alice");
    address public fakeToken = makeAddr("FakeToken");

    uint256 public ONE_ETH_PRICE = 2000;
    uint256 public ONE_BTC_PRICE = 1000;

    uint256 public DSC_AMOUNT_TO_MINT = 10000 ether; // equivalent to $10,000
    uint256 public DSC_AMOUNT_TO_BURN = 5000 ether; // equivalent to $5,000

    uint256 public APPROVAL_AMOUNT = 200 ether;
    uint256 public COLLATERAL_AMOUNT = 10 ether; // equivalent to $20,000 DSC

    event DscMinted(address user, uint256 amount);

    function setUp() public {
        deployer = new DeployDsc();
        (dsc, dscEngine, config) = deployer.run();
        (ethPriceFeed, btcPriceFeed, wEth, wBtc,) = config.activeNetworkConfig();

        ERC20Mock(wEth).mint(ALICE, APPROVAL_AMOUNT);
    }

    address[] public tokenAddresses = [wEth, wBtc];
    address[] public priceFeedAddresses = [ethPriceFeed, btcPriceFeed];

    modifier depositCollateral() {
        vm.startPrank(ALICE);
        ERC20Mock(wEth).approve(address(dscEngine), APPROVAL_AMOUNT);

        dscEngine.depositCollateral(wEth, COLLATERAL_AMOUNT);

        vm.stopPrank();
        _;
    }

    modifier dscApproval() {
        vm.startPrank(ALICE);
        dsc.approve(address(dscEngine), DSC_AMOUNT_TO_MINT);
        _;
    }

    /////////////////////////////////////////////////////
    ///              CONSTRUCTOR TESTS                ///
    /////////////////////////////////////////////////////

    function testRevertIfTokenAddressesAndPriceFeedAddressesMismatch() public {
        // Add fake Token to check for revert
        tokenAddresses.push(fakeToken);
        vm.expectRevert(DSCEngine_TokenAndPriceFeedAddressMisMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testRevertDscEngineAddressZero() public {
        vm.expectRevert(DSCEngine_InvalidAddress.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(0));
    }

    /////////////////////////////////////////////////////
    ///                 PRICE FEED TEST               ///
    /////////////////////////////////////////////////////

    function testGetValueInUSD() public {
        uint256 ethAmount = 15 ether;
        uint256 expectedValueInUSDFromEther = ethAmount * ONE_ETH_PRICE;

        uint256 valueInUsdFromEth = dscEngine.getValueInUSD(wEth, ethAmount);

        assertEq(valueInUsdFromEth, expectedValueInUSDFromEther);

        uint256 btcAmount = 15 ether;
        uint256 valueInUSDFromBTC = btcAmount * ONE_BTC_PRICE;

        uint256 valueInBtc = dscEngine.getValueInUSD(wBtc, 15 ether);
        assertEq(valueInUSDFromBTC, valueInBtc);
    }

    function testGetTokenAmountFromUSD() public {
        uint256 amountInUsd = 10 ether;
        uint256 expectedAmount = dscEngine.getTokenAmountFromUSD(wEth, amountInUsd);
        // $2000 / Eth
        assertEq(expectedAmount, amountInUsd / ONE_ETH_PRICE);
    }

    /////////////////////////////////////////////////////
    ///            DEPOSIT COLLATERAL TESTS           ///
    /////////////////////////////////////////////////////

    function testRevertDepositCollateralIfTokenNotAllowed() public {
        vm.expectRevert(DSCEngine_TokenNotAllowed.selector);
        dscEngine.depositCollateral(fakeToken, COLLATERAL_AMOUNT);
    }

    function testRevertDepositCollateralIfAmountIsZero() public {
        vm.expectRevert(DSCEngine_AmountMustBeAboveZero.selector);
        dscEngine.depositCollateral(wEth, 0);
    }

    function testDepositCollateral() public {
        vm.startPrank(ALICE);

        ERC20Mock(wEth).approve(address(dscEngine), APPROVAL_AMOUNT);

        dscEngine.depositCollateral(wEth, COLLATERAL_AMOUNT);

        uint256 aliceDepositedCollateral = dscEngine.getUserDepositedCollateral(ALICE, wEth);

        console.log(aliceDepositedCollateral);

        assertEq(aliceDepositedCollateral, COLLATERAL_AMOUNT);

        assertEq(ERC20Mock(wEth).balanceOf(address(dscEngine)), COLLATERAL_AMOUNT);
        assertEq(ERC20Mock(wEth).balanceOf(ALICE), APPROVAL_AMOUNT - COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testDepositCollaterlAndMintDSC() public {
        vm.startPrank(ALICE);

        ERC20Mock(wEth).approve(address(dscEngine), APPROVAL_AMOUNT);
        dscEngine.depositCollateralAndMintDsc(wEth, COLLATERAL_AMOUNT, DSC_AMOUNT_TO_MINT);

        assertEq(dscEngine.getUserDepositedCollateral(ALICE, wEth), COLLATERAL_AMOUNT);
        assertEq(dscEngine.getUserDscMinted(ALICE), DSC_AMOUNT_TO_MINT);

        vm.stopPrank();
    }

    /////////////////////////////////////////////////////
    ///                MINT & BURN TESTS              ///
    /////////////////////////////////////////////////////

    function testRevertIfHealthFactorGetsBroken() public depositCollateral {
        // Deposited 10 Eth
        // 1 Eth -> $2000
        // $2000 * 10 => $20,000
        // should not be able to mint DSC worth more than $10,000
        vm.prank(ALICE);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine_CriticalHealthFactor.selector, 0));
        dscEngine.mintDsc(10001 ether);
    }

    function testMintDsc() public depositCollateral {
        vm.prank(ALICE);

        vm.expectEmit(true, true, false, true, address(dscEngine));

        emit DscMinted(ALICE, DSC_AMOUNT_TO_MINT);

        dscEngine.mintDsc(DSC_AMOUNT_TO_MINT);

        assertEq(dscEngine.getUserDscMinted(ALICE), DSC_AMOUNT_TO_MINT); // 10000 ether
    }

    function testBurnDSC() public dscApproval {
        testDepositCollaterlAndMintDSC();

        vm.prank(ALICE);

        bool result = dscEngine.burnDsc(DSC_AMOUNT_TO_BURN); // 5000 ether

        uint256 amountAfterBurn = dscEngine.getUserDscMinted(ALICE);

        assertEq(amountAfterBurn, DSC_AMOUNT_TO_MINT - DSC_AMOUNT_TO_BURN);
        assertEq(result, true);
    }

    function testRedeemCollateralForDsc() public dscApproval {
        uint256 redeemAmount = 5 ether;

        testDepositCollaterlAndMintDSC();

        console.log("wEth Deposited By Alice: ", dscEngine.getUserDepositedCollateral(ALICE, wEth));
        console.log("Dsc Minted By Alice:", dscEngine.getUserDscMinted(ALICE));
        console.log("Alice Health Factor:", dscEngine.getHealthFactor(ALICE));

        vm.prank(ALICE);

        dscEngine.redeemCollateralForDsc(wEth, redeemAmount, 10000 ether);

        console.log("After Redeeming Collateral for DSC");

        console.log("wEth Deposited By Alice:", dscEngine.getUserDepositedCollateral(ALICE, wEth));
        console.log("Dsc Minted By Alice:", dscEngine.getUserDscMinted(ALICE));

        console.log("Alice Health Factor:", dscEngine.getHealthFactor(ALICE));

        assertEq(ERC20Mock(wEth).balanceOf(ALICE), (APPROVAL_AMOUNT - COLLATERAL_AMOUNT) + redeemAmount);
        assertEq(dscEngine.getUserDepositedCollateral(ALICE, wEth), redeemAmount);
        assertEq(dscEngine.getUserDscMinted(ALICE), 0);
    }

    function testGetUserCollateralValue() public depositCollateral {
        uint256 totalCollateralValue = dscEngine.getUserCollateralValue(ALICE);

        uint256 expectedTotalCollateralValue = COLLATERAL_AMOUNT * ONE_ETH_PRICE;
        assertEq(totalCollateralValue, expectedTotalCollateralValue);
    }

    ////////////////////////////////////////////////////////////////////
    ///                        LIQUIDATE TESTS                       ///
    ////////////////////////////////////////////////////////////////////

    function testRevertLiquidateIfHealthFactorIsOK() public {
        address liquidator = makeAddr("Liquidator");

        testDepositCollaterlAndMintDSC();

        vm.prank(liquidator);

        vm.expectRevert(DSCEngine_HealthFactorOk.selector);

        dscEngine.liquidate(ALICE, wEth, 5 ether);
    }

    address[] tokens;
    address[] priceFeeds;

    function test_Must_Improve_Health_Factor_On_Liquidation() public {
        MockDSC mdsc = new MockDSC(ethPriceFeed);

        tokens = [wEth];
        priceFeeds = [ethPriceFeed];

        address owner = msg.sender;

        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokens, priceFeeds, address(mdsc));
        mdsc.transferOwnership(address(mockDsce));

        // User Setup
        vm.startPrank(ALICE);
        ERC20Mock(wEth).approve(address(mockDsce), COLLATERAL_AMOUNT);
        mockDsce.depositCollateralAndMintDsc(wEth, COLLATERAL_AMOUNT, 100 ether);
        vm.stopPrank();

        // Arrange Liquidator
        uint256 collateraToCover = 1 ether; // 1 Ether = $2000
        address LIQUIDATOR = makeAddr("Liquidator");
        ERC20Mock(wEth).mint(LIQUIDATOR, collateraToCover);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wEth).approve(address(mockDsce), collateraToCover);
        uint256 debtToCover = 10 ether; // 10 DSC Tokens  = $10
        // Deposit 1 ether = $2000 and mint 100 Dsc = 100$
        mockDsce.depositCollateralAndMintDsc(wEth, collateraToCover, 100 ether);
        mdsc.approve(address(mockDsce), debtToCover);

        // Act
        int256 ethUsdNewPrice = 18e8; // 1 Eth = $18
        MockV3Aggregator(ethPriceFeed).updateAnswer(ethUsdNewPrice);

        vm.expectRevert(DSCEngine_UserHealthFactorNotImproved.selector);
        mockDsce.liquidate(ALICE, wEth, debtToCover);
        vm.stopPrank();
    }

    ////////////////////////////////////////
    ///         HEALTH FACTOR TEST       ///
    ////////////////////////////////////////

    function testHealthFactor() public {
        testDepositCollaterlAndMintDSC();

        uint256 expectedHealthFactor = 1;

        // we deposited $20,000 worth of eth
        // and minted $10,000 worth of DSC
        // with 50% liquidation threshold
        // So, we must always have $20,000 as collateral all the time
        // to maintain our position

        /**
         * Collatarerl Amount * Liquidation Threshold
         * 20,000 * 0.5 = 10,000 -> Liquidation threshold value
         * Liquidation Threshold value / Borrowed Amount
         * 10,000 / 10000 = 1;
         *
         * with a borrowed amount of $10,000 and a collateral of $20,000 at a 50% liquidation threshold,
         * the health factor is 1.
         * This means that the collateral is equal to the liquidation threshold,
         * indicating a precarious situation where any decrease in collateral value
         * would result in liquidation.
         */
        assertEq(dscEngine.getHealthFactor(ALICE), expectedHealthFactor);
    }
}
