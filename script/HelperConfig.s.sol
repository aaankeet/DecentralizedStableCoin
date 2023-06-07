// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/Mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@oz/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wEthPriceFeed;
        address wBtcPriceFeed;
        address wEth;
        address wBtc;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 18;
    int256 public constant WETH_USD_PRICE = 2000e8;
    int256 public constant WBTC_USD_PRICE = 1000e8;

    uint256 public DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wEthPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBtcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wEth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            wBtc: 0xABA31898c4472a09C8295807cd47A6a54071c9D5,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wEthPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();

        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS,WETH_USD_PRICE);

        ERC20Mock wETH = new ERC20Mock("WETH","WETH", msg.sender, 1000e8);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS,WBTC_USD_PRICE);

        ERC20Mock wBTC = new ERC20Mock("WBTC","WBTC", msg.sender, 1000e8);

        vm.stopBroadcast();

        return NetworkConfig({
            wEthPriceFeed: address(ethUsdPriceFeed),
            wBtcPriceFeed: address(btcUsdPriceFeed),
            wEth: address(wETH),
            wBtc: address(wBTC),
            deployerKey: DEFAULT_ANVIL_KEY
        });
    }
}
