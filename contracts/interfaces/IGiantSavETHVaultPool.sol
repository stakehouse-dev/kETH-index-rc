// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IGiantSavETHVaultPool {
    function depositETH(uint256 _amount) external payable;

    function withdrawETH(uint256 _amount) external;

    function withdrawDETH(
        address[] calldata _savETHVaults,
        address[][] calldata _lpTokens,
        uint256[][] calldata _amounts
    ) external;
}
