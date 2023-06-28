// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISavETHManager} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/ISavETHManager.sol";

import {IWstETH} from "./steth/IWstETH.sol";
import {IRocketTokenRETH} from "./reth/IRocketTokenRETH.sol";
import {IAssetPriceAggregator} from "./IAssetPriceAggregator.sol";

contract AssetRegistry is Ownable {
    event UpdateExternalSource(address asset, address source);

    address public constant ETH = address(0);

    ISavETHManager public savETHManager;
    address public dETH;
    address public savETH;
    address public wstETH;
    address public stETH;
    address public rETH;
    address public giantLP;

    mapping(address => address) public externalSources; // asset price aggregator (ETH price)

    constructor(
        address _savETHManager,
        address _dETH,
        address _savETH,
        address _wstETH,
        address _stETH,
        address _rETH,
        address _giantLP
    ) {
        savETHManager = ISavETHManager(_savETHManager);
        dETH = _dETH;
        savETH = _savETH;
        wstETH = _wstETH;
        stETH = _stETH;
        rETH = _rETH;
        giantLP = _giantLP;
    }

    function assetValue(
        address _asset,
        uint256 _balance
    ) external view returns (uint256) {
        if (_asset == ETH || _asset == dETH || _asset == giantLP) {
            return _balance;
        } else if (_asset == wstETH) {
            return
                this.assetValue(
                    stETH,
                    IWstETH(wstETH).getStETHByWstETH(_balance)
                );
        } else if (_asset == rETH) {
            return IRocketTokenRETH(rETH).getEthValue(_balance);
        } else if (_asset == savETH) {
            return savETHManager.savETHToDETH(_balance);
        }

        address externalSource = externalSources[_asset];
        if (externalSource != address(0)) {
            (, int256 answer, , , ) = IAssetPriceAggregator(externalSource)
                .latestRoundData();
            return (uint256(answer) * _balance) / 1e18;
        }

        return 0;
    }

    function setExternalSource(
        address _asset,
        address _source
    ) external onlyOwner {
        externalSources[_asset] = _source;

        emit UpdateExternalSource(_asset, _source);
    }
}
