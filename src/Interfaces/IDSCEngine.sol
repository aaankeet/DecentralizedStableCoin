// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.19;

interface IDSCEngine {
    error DSCEngine_InvalidTokenAddress();
    error DSCEngine_InvalidAddress();
    error DSCEngine_TokenNotAllowed();
    error DSCEngine_AmountMustBeAboveZero();
    error DSCEngine_TokenAndPriceFeedAddressMisMatch();
    error DSCEngine_TransferFailed();
    error DSCEngine_CriticalHealthFactor(uint256 healthFactor);
    error DSCEngine_HealthFactorOk();
    error DSCEngine_UserHealthFactorNotImproved();

    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed amount);

    event CollateralRedeemed(address indexed from, address indexed to, address indexed tokenAddress, uint256 amount);

    event DscMinted(address user, uint256 amount);

    function depositCollateralAndMintDsc(address tokenAddress, uint256 collateralAmount, uint256 amountDscToMint)
        external;

    function depositCollateral(address tokenAddress, uint256 amount) external returns (bool);

    function redeemCollateral(address collateralTokenAddress, uint256 collateralAmount) external;

    function redeemCollateralForDsc(
        address collateralTokenAddress,
        uint256 collateralAmountToRedeem,
        uint256 dscAmountToBurn
    ) external;

    function liquidate(address user, address collateralTokenAddress, uint256 debtToCover) external returns (bool);

    function mintDsc(uint256 amountToMint) external returns (bool);

    function burnDsc(uint256 amount) external returns (bool);

    function getHealthFactor(address user) external view returns (uint256);

    function getUserCollateralValue(address user) external view returns (uint256);

    function getValueInUSD(address token, uint256 amount) external view returns (uint256);

    function getTokenAmountFromUSD(address token, uint256 usdAmountInWei) external view returns (uint256);
}
