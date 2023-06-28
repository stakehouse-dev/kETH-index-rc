// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface ICurveRETHPool {
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy,
        bool use_eth
    ) external payable returns (uint256 dy);
}
