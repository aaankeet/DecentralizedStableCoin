// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {DeployDsc} from "../script/DeployDsc.s.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

import {ERC20Mock} from "@oz/mocks/ERC20Mock.sol";

error DSCEngine_InvalidTokenAddress();
error DSCEngine_InvalidAddress();
error DSCEngine_TokenNotAllowed();
error DSCEngine_AmountMustBeAboveZero();
error DSCEngine_TokenAndPriceFeedAddressMisMatch();
error DSCEngine_TransferFailed();
error DSCEngine_CriticalHealthFactor(uint256 healthFactor);

contract DSCEngineTest is Test {
    DeployDsc deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;

    address public wEth;
    address public wBtc;

    address public ethPriceFeed;
    address public btcPriceFeed;

    uint256 public deployerKey;

    address public ALICE = makeAddr("Alice");
    address public fakeToken = makeAddr("FakeToken");

    uint256 public COLLATERAL_AMOUNT = 10 ether;

    function setUp() public {
        deployer = new DeployDsc();
        (dsc, dscEngine, config) = deployer.run();
        (ethPriceFeed, btcPriceFeed, wEth, wBtc, deployerKey) = config.activeNetworkConfig();

        ERC20Mock(wEth).mint(ALICE, COLLATERAL_AMOUNT);
    }

    ///////////////////////
    /// PRICE FEED TEST ///
    ///////////////////////

    function testPriceInUsd() public {
        uint256 ethAmount = 15 ether;
        uint256 expectedValue = ethAmount * 2000;

        uint256 valueInUsd = dscEngine.getValueInUSD(wEth, ethAmount);

        assertEq(valueInUsd, expectedValue);

        uint256 valueInUsd2 = dscEngine.getValueInUSD(wBtc, 15 ether);

        assertEq(valueInUsd2, 15 ether * 1000);
    }

    function testDepositCollateral() public {
        assertEq(ERC20Mock(wEth).balanceOf(ALICE), COLLATERAL_AMOUNT);

        vm.startPrank(ALICE);

        ERC20Mock(wEth).approve(address(dscEngine), COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine_TokenNotAllowed.selector);
        dscEngine.depositCollateral(fakeToken, COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine_AmountMustBeAboveZero.selector);
        dscEngine.depositCollateral(wEth, 0);

        dscEngine.depositCollateral(wEth, COLLATERAL_AMOUNT);

        assertEq(ERC20Mock(wEth).balanceOf(address(dscEngine)), COLLATERAL_AMOUNT);
        assertEq(ERC20Mock(wEth).balanceOf(ALICE), 0);
    }
}
