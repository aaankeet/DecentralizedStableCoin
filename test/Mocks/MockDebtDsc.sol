// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

/**
 * @title DecentralizedStableCoin
 * @author Aaankeet
 * Collateral: Exogenous (ETH & BTC)
 * Minting Algorithmic
 * Relative Stability: Pegged to USD
 *
 * This is the contract meant to be governed by DSCEngine.
 * This contract is just ERC20 implementation of out stablecoin.
 */

import {ERC20Burnable, ERC20} from "@oz/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import "./MockV3Aggregator.sol";

error MockDSC_AmountMustBeAboveZero();
error MockDSC_AmountExceedsBalance();
error MockDSC_InvalidAddress();

contract MockDSC is ERC20Burnable, Ownable {
    address mockAggregator;

    constructor(address _mockAggregator) ERC20("Mock More Debt DSC", "MDSC") {
        mockAggregator = _mockAggregator;
    }

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (amount == 0) revert MockDSC_AmountMustBeAboveZero();
        if (balance < amount) {
            revert MockDSC_AmountExceedsBalance();
        }
        super.burn(amount);
    }

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (to == address(0)) revert MockDSC_InvalidAddress();
        if (amount == 0) revert MockDSC_AmountMustBeAboveZero();

        _mint(to, amount);

        return true;
    }
}
