// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

error DecentralizedStableCoin_AmountMustBeAboveZero();
error DecentralizedStableCoin_AmountExceedsBalance();
error DecentralizedStableCoin_InvalidAddress();

interface IDecentralizedStableCoin {
    function burn(uint256 amount) external;

    function mint(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
