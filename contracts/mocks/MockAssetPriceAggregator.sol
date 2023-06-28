// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAssetPriceAggregator} from "../keth-vault/IAssetPriceAggregator.sol";

contract MockAssetPriceAggregator is IAssetPriceAggregator, Ownable {
    int256 public answer = 1e18;

    function setPrice(int256 _answer) external onlyOwner {
        answer = _answer;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, answer, block.timestamp, block.timestamp, 0);
    }
}
