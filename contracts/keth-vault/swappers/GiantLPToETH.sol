// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../../Errors.sol";
import {IGiantSavETHVaultPool} from "../../interfaces/IGiantSavETHVaultPool.sol";
import {ICurveRETHPool} from "../reth/ICurveRETHPool.sol";
import {ISwapper} from "./ISwapper.sol";

contract GiantLPToETH is ISwapper {
    using SafeERC20 for IERC20;

    address public constant ETH = address(0);
    address public giantLP;
    address public giantSavETHVaultPool;

    constructor(address _giantLP, address _giantSavETHVaultPool) {
        giantLP = _giantLP;
        giantSavETHVaultPool = _giantSavETHVaultPool;
    }

    receive() external payable {}

    /// @inheritdoc ISwapper
    function inputToken() external view override returns (address) {
        return giantLP;
    }

    /// @inheritdoc ISwapper
    function outputToken() external pure override returns (address) {
        return ETH;
    }

    /// @inheritdoc ISwapper
    function swap(
        address input,
        uint256 amountIn,
        address output,
        uint256 minAmountOut,
        bytes memory
    ) external payable override returns (uint256 amountOut) {
        if (input != giantLP || output != ETH) {
            revert Errors.InvalidAddress();
        }

        IERC20(input).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(input).safeApprove(address(giantSavETHVaultPool), amountIn);
        IGiantSavETHVaultPool(giantSavETHVaultPool).withdrawETH(amountIn);
        amountOut = address(this).balance;

        if (minAmountOut > amountOut) {
            revert Errors.ExceedMinAmountOut();
        }

        // withdraw ETH to user
        (bool sent, ) = payable(msg.sender).call{value: amountOut}("");
        if (!sent) {
            revert Errors.FailedToSendETH();
        }
    }
}
