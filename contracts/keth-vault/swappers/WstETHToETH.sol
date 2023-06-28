// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../../Errors.sol";
import {IWstETH} from "../steth/IWstETH.sol";
import {ICurveStETHPool} from "../steth/ICurveStETHPool.sol";
import {ISwapper} from "./ISwapper.sol";

contract WstETHToETH is ISwapper {
    using SafeERC20 for IERC20;

    address public constant ETH = address(0);
    address public wstETH;
    address public stETH;
    address public curveStETHPool;

    constructor(address _wstETH, address _stETH, address _curveStETHPool) {
        wstETH = _wstETH;
        stETH = _stETH;
        curveStETHPool = _curveStETHPool;
    }

    receive() external payable {}

    /// @inheritdoc ISwapper
    function inputToken() external view override returns (address) {
        return wstETH;
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
        if (input != wstETH || output != ETH) {
            revert Errors.InvalidAddress();
        }

        IERC20(input).safeTransferFrom(msg.sender, address(this), amountIn);

        amountOut = _sellWstETHForETH(amountIn);

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
}
