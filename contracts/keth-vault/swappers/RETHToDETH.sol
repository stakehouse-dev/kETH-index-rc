// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../../Errors.sol";
import {DETHVault} from "../../deth-vault/DETHVault.sol";
import {ICurveRETHPool} from "../reth/ICurveRETHPool.sol";
import {ISwapper} from "./ISwapper.sol";

contract RETHToDETH is ISwapper {
    using SafeERC20 for IERC20;

    address public rETH;
    address public curveRETHPool;
    address public dETH;
    address public dETHVault;

    constructor(
        address _rETH,
        address _curveRETHPool,
        address _dETH,
        address _dETHVault
    ) {
        rETH = _rETH;
        curveRETHPool = _curveRETHPool;
        dETH = _dETH;
        dETHVault = _dETHVault;
    }

    receive() external payable {}

    /// @inheritdoc ISwapper
    function inputToken() external view override returns (address) {
        return rETH;
    }

    /// @inheritdoc ISwapper
    function outputToken() external view override returns (address) {
        return dETH;
    }

    /// @inheritdoc ISwapper
    function swap(
        address input,
        uint256 amountIn,
        address output,
        uint256 minAmountOut,
        bytes memory
    ) external payable override returns (uint256 amountOut) {
        if (input != rETH || output != dETH) {
            revert Errors.InvalidAddress();
        }

        IERC20(input).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 ethAmount = _sellRETHForETH(amountIn);
        amountOut = _sellETHforDETH(ethAmount);

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
     * @dev Sell ETH for dETH
     * @param _ethAmount The ETH amount for sell
     */
    function _sellETHforDETH(uint256 _ethAmount) internal returns (uint256) {
        DETHVault(dETHVault).swapETHToDETH{value: _ethAmount}(address(this));

        return _ethAmount;
    }
}
