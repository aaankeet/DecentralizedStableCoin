// This will holds all the invariants / properties that we are going to test

// What are out invariants?

// 1. the total supply of DSC should always be less than total collaretal amount
// 2. Getter view functions should never revert <- Evergreen Invriant

pragma solidity 0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

import {HelperConfig} from "../../script/HelperConfig.s.sol";

import {Handler} from "./Handler.t.sol";

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDsc deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig config;

    Handler handler;

    address public wEthPriceFeed;
    address public wBtcPriceFeed;

    address public wEth;
    address public wBtc;

    function setUp() external {
        deployer = new DeployDsc();
        (dsc, dscEngine, config) = deployer.run();

        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));

        (wEthPriceFeed, wBtcPriceFeed, wEth, wBtc,) = config.activeNetworkConfig();
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol;
        // compare it to all  the debt (dsc)

        uint256 totalWethDeposited = IERC20(wEth).balanceOf(address(dscEngine));
        uint256 totalBtcDeposited = IERC20(wBtc).balanceOf(address(dscEngine));

        uint256 totalEthValue = dscEngine.getValueInUSD(wEth, totalWethDeposited);
        uint256 totalBtcValue = dscEngine.getValueInUSD(wBtc, totalBtcDeposited);

        uint256 totalSupply = dsc.totalSupply();

        console.log("Total Supply:", totalSupply / 1e18);
        console.log("Total Eth Value:", totalEthValue / 1e18);
        console.log("Total Btc Value:", totalBtcValue / 1e18);
        console.log("Times Mint Called:", handler.timeMintCalled());

        assert(totalBtcValue + totalEthValue >= totalSupply);
    }
}
