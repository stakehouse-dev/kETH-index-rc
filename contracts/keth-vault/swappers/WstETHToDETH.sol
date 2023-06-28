// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../../Errors.sol";
import {DETHVault} from "../../deth-vault/DETHVault.sol";
import {IWstETH} from "../steth/IWstETH.sol";
import {ICurveStETHPool} from "../steth/ICurveStETHPool.sol";
import {ISwapper} from "./ISwapper.sol";

contract WstETHToDETH is ISwapper {
    using SafeERC20 for IERC20;

    address public wstETH;
    address public stETH;
    address public curveStETHPool;
    address public dETH;
    address public dETHVault;

    constructor(
        address _wstETH,
        address _stETH,
        address _curveStETHPool,
        address _dETH,
        address _dETHVault
    ) {
        wstETH = _wstETH;
        stETH = _stETH;
        curveStETHPool = _curveStETHPool;
        dETH = _dETH;
        dETHVault = _dETHVault;
    }

    receive() external payable {}

    /// @inheritdoc ISwapper
    function inputToken() external view override returns (address) {
        return wstETH;
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
        if (input != wstETH || output != dETH) {
            revert Errors.InvalidAddress();
        }

        IERC20(input).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 ethAmount = _sellWstETHForETH(amountIn);
        amountOut = _sellETHforDETH(ethAmount);

        if (minAmountOut > amountOut) {
            revert Errors.ExceedMinAmountOut();
        }

        // withdraw to user
        IERC20(output).safeTransfer(msg.sender, amountOut);
    }

    /**
     * @dev Sell wstETH for ETH
     * @param _wstETHAmount The wstETH amount for sell
     */
    function _sellWstETHForETH(
        uint256 _wstETHAmount
    ) internal returns (uint256 ethAmount) {
        // unwrap wsteth to steth
        uint256 stETHAmount = IWstETH(wstETH).unwrap(_wstETHAmount);

        // swap steth to eth
        IERC20(stETH).safeApprove(curveStETHPool, stETHAmount);
        ethAmount = ICurveStETHPool(curveStETHPool).exchange(
            1,
            0,
            stETHAmount,
            0
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
