// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../../Errors.sol";
import {IGiantSavETHVaultPool} from "../../interfaces/IGiantSavETHVaultPool.sol";
import {ICurveRETHPool} from "../reth/ICurveRETHPool.sol";
import {ISwapper} from "./ISwapper.sol";

contract RETHToGiantLP is ISwapper {
    using SafeERC20 for IERC20;

    address public rETH;
    address public curveRETHPool;
    address public giantLP;
    address public giantSavETHVaultPool;

    constructor(
        address _rETH,
        address _curveRETHPool,
        address _giantLP,
        address _giantSavETHVaultPool
    ) {
        rETH = _rETH;
        curveRETHPool = _curveRETHPool;
        giantLP = _giantLP;
        giantSavETHVaultPool = _giantSavETHVaultPool;
    }

    receive() external payable {}

    /// @inheritdoc ISwapper
    function inputToken() external view override returns (address) {
        return rETH;
    }

    /// @inheritdoc ISwapper
    function outputToken() external view override returns (address) {
        return giantLP;
    }

    /// @inheritdoc ISwapper
    function swap(
        address input,
        uint256 amountIn,
        address output,
        uint256 minAmountOut,
        bytes memory
    ) external payable override returns (uint256 amountOut) {
        if (input != rETH || output != giantLP) {
            revert Errors.InvalidAddress();
        }

        IERC20(input).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 ethAmount = _sellRETHForETH(amountIn);
        amountOut = _sellETHforGiantLP(ethAmount);

        if (minAmountOut > amountOut) {
            revert Errors.ExceedMinAmountOut();
        }

        // withdraw to user
        IERC20(output).safeTransfer(msg.sender, amountOut);
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

    /**
     * @dev Sell ETH for GiantLP
     * @param _ethAmount The ETH amount for sell
     */
    function _sellETHforGiantLP(uint256 _ethAmount) internal returns (uint256) {
        IGiantSavETHVaultPool(giantSavETHVaultPool).depositETH{value: _ethAmount}(
            _ethAmount
        );

        return _ethAmount;
    }
}
