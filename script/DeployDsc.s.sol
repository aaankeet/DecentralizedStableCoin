// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import "../src/DSCEngine.sol";
import "../src/DecentralizedStableCoin.sol";

import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDsc is Script {
    address[] public tokenAddress;
    address[] public priceFeeds;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address wEthPriceFeed, address wBtcPriceFeed, address wEth, address wBtc, uint256 deployerKey) =
            config.activeNetworkConfig();

        tokenAddress = [wEth, wBtc];
        priceFeeds = [wEthPriceFeed, wBtcPriceFeed];

        vm.startBroadcast(deployerKey);

        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine(tokenAddress, priceFeeds, address(dsc));

        dsc.transferOwnership(address(dscEngine));

        vm.stopBroadcast();

        return (dsc, dscEngine, config);
    }
}
