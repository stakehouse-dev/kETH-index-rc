// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICurveRETHPool} from "../keth-vault/reth/ICurveRETHPool.sol";

contract CurveRETHPool is Ownable, ICurveRETHPool {
    using SafeERC20 for IERC20;

    uint256 public rate = 1e18;
    address public rETH;

    constructor(address _rETH) Ownable() {
        rETH = _rETH;
    }

    receive() external payable {}

    function setExchangeRate(uint256 _rate) external onlyOwner {
        rate = _rate;
    }

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 min_dy,
        bool use_eth
    ) external payable override returns (uint256 dy) {
        if (i == 1 && j == 0) {
            IERC20(rETH).safeTransferFrom(msg.sender, address(this), dx);

            dy = (dx * rate) / 1e18;
            require(dy >= min_dy, "min dy");

            if (use_eth) {
                (bool sent, ) = payable(msg.sender).call{value: dy}("");
                require(sent, "failed to send eth");
                return dy;
            }
        }

        revert("not implemented");
    }
}
