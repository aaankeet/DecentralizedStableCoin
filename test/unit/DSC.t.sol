// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

error DecentralizedStableCoin_AmountMustBeAboveZero();
error DecentralizedStableCoin_InvalidAddress();

contract DSCTest is Test {
    DecentralizedStableCoin dsc;
    address public ALICE = makeAddr("Alice");
    uint256 public AMOUNT = 10 ether;

    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    function testRevertIfAmountIsZero() public {
        vm.expectRevert(DecentralizedStableCoin_AmountMustBeAboveZero.selector);
        dsc.mint(ALICE, 0);
    }
}
