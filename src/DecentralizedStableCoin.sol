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
import "./Interfaces/IDecentralizedStableCoin.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    constructor() ERC20("Pretty Stable Coin", "PSC") {}

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (amount == 0) revert DecentralizedStableCoin_AmountMustBeAboveZero();
        if (balance < amount) {
            revert DecentralizedStableCoin_AmountExceedsBalance();
        }
        super.burn(amount);
    }

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (to == address(0)) revert DecentralizedStableCoin_InvalidAddress();
        if (amount == 0) revert DecentralizedStableCoin_AmountMustBeAboveZero();

        _mint(to, amount);

        return true;
    }
}
