// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

error DSCEngine_InvalidTokenAddress();
error DSCEngine_InvalidAddress();
error DSCEngine_TokenNotAllowed();
error DSCEngine_AmountMustBeAboveZero();
error DSCEngine_TokenAndPriceFeedAddressMisMatch();
error DSCEngine_TransferFailed();
error DSCEngine_CriticalHealthFactor(uint256 healthFactor);
error DSCEngine_HealthFactorOk();

interface IDSCEngine {
    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);

    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    event DscMinted(address user, uint256 amount);

    function depositCollateralAndMintDsc(address tokenAddress, uint256 collateralAmount, uint256 amountToMint)
        external
        returns (bool);

    function depositCollateral(address token, uint256 amount) external returns (bool);

    function redeemCollateral() external;

    function mintDsc(uint256 amountToMint) external returns (bool);

    function burnDsc(address from, uint256 amount) external returns (bool);

    function liquidate(address user) external;

    function getHealthFactor(address user) external view returns (uint256);

    function getUserCollateralValue(address user) external view returns (uint256);

    function getValueInUSD(address token, uint256 amount) external view returns (uint256);
}
