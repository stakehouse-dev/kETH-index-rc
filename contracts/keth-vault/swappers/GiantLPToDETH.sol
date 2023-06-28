// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Errors} from "../../Errors.sol";
import {IGiantSavETHVaultPool} from "../../interfaces/IGiantSavETHVaultPool.sol";
import {ICurveRETHPool} from "../reth/ICurveRETHPool.sol";
import {ISwapper} from "./ISwapper.sol";

contract GiantLPToDETH is ISwapper {
    using SafeERC20 for IERC20;

    address public dETH;
    address public giantLP;
    address public giantSavETHVaultPool;

    constructor(
        address _dETH,
        address _giantLP,
        address _giantSavETHVaultPool
    ) {
        dETH = _dETH;
        giantLP = _giantLP;
        giantSavETHVaultPool = _giantSavETHVaultPool;
    }

    receive() external payable {}

    /// @inheritdoc ISwapper
    function inputToken() external view override returns (address) {
        return giantLP;
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
        bytes memory extraData
    ) external payable override returns (uint256 amountOut) {
        if (input != giantLP || output != dETH) {
            revert Errors.InvalidAddress();
        }

        IERC20(input).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(input).safeApprove(address(giantSavETHVaultPool), amountIn);

        (
            address[] memory _savETHVaults,
            address[][] memory _lpTokens,
            uint256[][] memory _amounts
        ) = abi.decode(extraData, (address[], address[][], uint256[][]));

        IGiantSavETHVaultPool(giantSavETHVaultPool).withdrawDETH(
            _savETHVaults,
            _lpTokens,
            _amounts
        );
        amountOut = IERC20(dETH).balanceOf(address(this));

        if (minAmountOut > amountOut) {
            revert Errors.ExceedMinAmountOut();
        }

        // withdraw to user
        IERC20(output).safeTransfer(msg.sender, amountOut);
    }
}
