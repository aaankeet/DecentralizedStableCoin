// Handler will narrow down the way we call functions
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

import {ERC20Mock} from "@oz/mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;

    ERC20Mock wEth;
    ERC20Mock wBtc;

    uint256 public timeMintCalled;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralAddresses = dscEngine.getCollateralTokens();
        wEth = ERC20Mock(collateralAddresses[0]);
        wBtc = ERC20Mock(collateralAddresses[1]);
    }

    function depositCollateral(uint256 collateralSeed, uint256 collateralAmount) public returns (address, address) {
        collateralAmount = bound(collateralAmount, 1, type(uint128).max);

        //to avoid address(0)
        // if (sender == address(0)) {
        //     sender = makeAddr("Sender");
        // }

        ERC20Mock tokenAddress = getCollateralTokenSeed(collateralSeed);

        vm.startPrank(msg.sender);

        tokenAddress.mint(msg.sender, collateralAmount);
        tokenAddress.approve(address(dscEngine), collateralAmount);

        dscEngine.depositCollateral(address(tokenAddress), collateralAmount);
        vm.stopPrank();

        return (msg.sender, address(tokenAddress));
    }

    // function redeemCollateral( /*address sender*/ uint256 collateralSeed, uint256 collateralAmount) public {
    //     // (address sender2, address tokenAddress) = depositCollateral(sender, collateralSeed, collateralAmount);

    //     ERC20Mock tokenAddress = getCollateralTokenSeed(collateralSeed);

    //     uint256 maxCollateralToRedeem = dscEngine.getUserDepositedCollateral(msg.sender, address(tokenAddress));
    //     collateralAmount = bound(collateralAmount, 0, maxCollateralToRedeem);

    //     if (collateralAmount == 0) {
    //         return;
    //     }

    //     vm.startPrank(msg.sender);

    //     dscEngine.redeemCollateral(address(tokenAddress), collateralAmount);

    //     vm.stopPrank();
    // }

    function mintDsc(uint256 amountToMint) public {
        (uint256 totalDscMinted, uint256 totalCollateralValue) = dscEngine.getUseraAccountInfo(msg.sender);

        if (totalCollateralValue == 0) return;

        int256 mintableAmount = ((int256(totalCollateralValue) / 1e18) / 2) - int256(totalDscMinted);

        amountToMint = bound(amountToMint, 0, uint256(mintableAmount));

        timeMintCalled++;

        if (amountToMint > 0) {
            vm.startPrank(msg.sender);

            dscEngine.mintDsc(amountToMint);

            vm.stopPrank();
        } else {
            return;
        }
    }

    function getCollateralTokenSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return wEth;
        }
        return wBtc;
    }
}
