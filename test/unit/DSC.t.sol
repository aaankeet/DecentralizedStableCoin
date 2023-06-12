// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

error DecentralizedStableCoin_AmountMustBeAboveZero();
error DecentralizedStableCoin_InvalidAddress();
error DecentralizedStableCoin_AmountExceedsBalance();

contract DSCTest is Test {
    DecentralizedStableCoin dsc;
    address public ALICE = makeAddr("Alice");
    uint256 public AMOUNT = 10 ether;

    function setUp() public {
        dsc = new DecentralizedStableCoin();
    }

    function testRevertMintIfAmountIsZero() public {
        vm.expectRevert(DecentralizedStableCoin_AmountMustBeAboveZero.selector);
        dsc.mint(ALICE, 0);
    }

    function testRevertMintIfAddressIfZero() public {
        vm.expectRevert(DecentralizedStableCoin_InvalidAddress.selector);
        dsc.mint(address(0), AMOUNT);
    }

    function testRevertBurnIfAmountIsZero() public {
        vm.expectRevert(DecentralizedStableCoin_AmountMustBeAboveZero.selector);
        dsc.burn(0);
    }

    function testRevertBalanceIsLessThanAmount() public {
        vm.expectRevert(DecentralizedStableCoin_AmountExceedsBalance.selector);
        dsc.burn(AMOUNT);
    }
}
