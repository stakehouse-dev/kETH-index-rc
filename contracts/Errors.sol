// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface Errors {
    error ZeroAddress();
    error InvalidIndex();
    error InvalidAddress();
    error InvalidAmount();
    error Unauthorized();
    error FailedToSendETH();
    error ExceedsDepositCeiling();
    error UnknownAsset();
    error CannotRemoveHoldingAsset();
    error TooSmall();
    error ComeBackLater();
    error ExceedMinAmountOut();
    error InvalidSwapper();
    error RemoveDefaultSwapperBefore();
    error NotSupportedSwapper();
    error AssetNotAllowedInNewStrategy();
    error InvalidTokenOut();
}
