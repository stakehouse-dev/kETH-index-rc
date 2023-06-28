// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../../Errors.sol";
import {ICurveRETHPool} from "../reth/ICurveRETHPool.sol";
import {ISwapper} from "./ISwapper.sol";

contract RETHToETH is ISwapper {
    using SafeERC20 for IERC20;

    address public constant ETH = address(0);
    address public rETH;
    address public curveRETHPool;

    constructor(address _rETH, address _curveRETHPool) {
        rETH = _rETH;
        curveRETHPool = _curveRETHPool;
    }

    receive() external payable {}

    /// @inheritdoc ISwapper
    function inputToken() external view override returns (address) {
        return rETH;
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
        if (input != rETH || output != ETH) {
            revert Errors.InvalidAddress();
        }

        IERC20(input).safeTransferFrom(msg.sender, address(this), amountIn);

        amountOut = _sellRETHForETH(amountIn);

        if (minAmountOut > amountOut) {
            revert Errors.ExceedMinAmountOut();
        }

        // withdraw ETH to user
        (bool sent, ) = payable(msg.sender).call{value: amountOut}("");
        if (!sent) {
            revert Errors.FailedToSendETH();
        }
    }

    /**
     * @dev Sell rETH for ETH
     * @param _rETHAmount The rETH amount for sell
     */
    function _sellRETHForETH(
        uint256 _rETHAmount
    ) internal returns (uint256 ethAmount) {
        // swap reth to eth
        IERC20(rETH).safeApprove(curveRETHPool, _rETHAmount);
        ethAmount = ICurveRETHPool(curveRETHPool).exchange(
            1,
            0,
            _rETHAmount,
            0,
            true
        ); // min receive = 0
    }
}
