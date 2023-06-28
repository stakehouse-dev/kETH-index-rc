// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

interface IRocketTokenRETH {
    function getEthValue(uint256 _rethAmount) external view returns (uint256);

    function getRethValue(uint256 _ethAmount) external view returns (uint256);

    function getExchangeRate() external view returns (uint256);

    function burn(uint256 _rethAmount) external;
}
