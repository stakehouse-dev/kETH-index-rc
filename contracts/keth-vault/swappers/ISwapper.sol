// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface ISwapper {
    /// @dev Return the input token address
    /// @return token The input token address
    function inputToken() external view returns (address);

    /// @dev Return the output token address
    /// @return token The output token address
    function outputToken() external view returns (address);

    /// @dev Swap exact amount of input token for output token
    /// @param input The input token address
    /// @param amountIn The amount of input token
    /// @param output The output token address
    /// @param minAmountOut The minimum amount of output token
    /// @param extraData Extra swap data
    /// @return amountOut The swap result
    function swap(
        address input,
        uint256 amountIn,
        address output,
        uint256 minAmountOut,
        bytes memory extraData
    ) external payable returns (uint256 amountOut);
}
