// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface ICurveStETHPool {
    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external payable returns (uint256 dy);
}
