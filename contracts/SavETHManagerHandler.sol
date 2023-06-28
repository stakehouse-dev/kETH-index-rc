// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ISavETHManager} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/ISavETHManager.sol";
import {Errors} from "./Errors.sol";

abstract contract SavETHManagerHandler {
    struct IsolatedKey {
        address stakeHouse;
        bytes blsPublicKey;
    }

    ISavETHManager public savETHManager;
    address public savETH;
    uint256 public savETHIndexOwned;

    uint256 public numOfIsolatedKeys;
    mapping(uint256 => IsolatedKey) public isolatedKeys;

    modifier authorized() {
        if (msg.sender != _authorizedManager()) {
            revert Errors.Unauthorized();
        }
        _;
    }

    function __SavETHManagerHandler_init(
        address _savETHManager,
        address _savETH
    ) internal {
        savETHManager = ISavETHManager(_savETHManager);
        savETH = _savETH;
        savETHIndexOwned = ISavETHManager(_savETHManager).createIndex(
            address(this)
        );
    }

    /**
     * @dev Returns authorized user for SavETHManager
     */
    function _authorizedManager() internal view virtual returns (address) {}

    /**
     * @dev Returns total isolated balance in savETH
     */
    function _totalIsolatedSavETH() internal view returns (uint256) {
        uint256 dETHAmount;
        for (uint256 i = 0; i < numOfIsolatedKeys; ++i) {
            dETHAmount += savETHManager.knotDETHBalanceInIndex(
                savETHIndexOwned,
                isolatedKeys[i].blsPublicKey
            );
        }

        return savETHManager.dETHToSavETH(dETHAmount);
    }

    /**
     * @dev isolateKnotFromOpenIndex
     * @param _stakeHouse Address of StakeHouse that the KNOT belongs to
     * @param _blsPublicKey KNOT ID within the StakeHouse
     */
    function isolateKnotFromOpenIndex(
        address _stakeHouse,
        bytes calldata _blsPublicKey
    ) external authorized {
        uint256 balanceBefore = IERC20Upgradeable(savETH).balanceOf(
            address(this)
        );

        savETHManager.isolateKnotFromOpenIndex(
            _stakeHouse,
            _blsPublicKey,
            savETHIndexOwned
        );

        isolatedKeys[numOfIsolatedKeys] = IsolatedKey({
            stakeHouse: _stakeHouse,
            blsPublicKey: _blsPublicKey
        });
        numOfIsolatedKeys += 1;

        _savETHBalanceChanged(
            balanceBefore,
            IERC20Upgradeable(savETH).balanceOf(address(this))
        );
    }

    /**
     * @dev addKnotToOpenIndex
     * @param _indexOfIsolatedKeys index of isolated keys array
     */
    function addKnotToOpenIndex(
        uint256 _indexOfIsolatedKeys
    ) external authorized {
        _addKnotToOpenIndex(_indexOfIsolatedKeys);
    }

    /**
     * @dev addKnotToOpenIndex
     * @param _indexOfIsolatedKeys index of isolated keys array
     */
    function _addKnotToOpenIndex(uint256 _indexOfIsolatedKeys) internal {
        if (_indexOfIsolatedKeys >= numOfIsolatedKeys) {
            revert Errors.InvalidIndex();
        }

        uint256 balanceBefore = IERC20Upgradeable(savETH).balanceOf(
            address(this)
        );

        IsolatedKey memory isolatedKey = isolatedKeys[_indexOfIsolatedKeys];
        savETHManager.addKnotToOpenIndex(
            isolatedKey.stakeHouse,
            isolatedKey.blsPublicKey,
            address(this)
        );

        isolatedKeys[_indexOfIsolatedKeys] = isolatedKeys[
            numOfIsolatedKeys - 1
        ];
        delete isolatedKeys[numOfIsolatedKeys - 1];
        numOfIsolatedKeys -= 1;

        _savETHBalanceChanged(
            balanceBefore,
            IERC20Upgradeable(savETH).balanceOf(address(this))
        );
    }

    /**
     * @dev rotateSavETH
     * @param _indexOfIsolatedKeys index of isolated keys array
     * @param _newStakeHouse Address of StakeHouse that the KNOT belongs to
     * @param _newBlsPublicKey KNOT ID within the StakeHouse
     */
    function rotateSavETH(
        uint256 _indexOfIsolatedKeys,
        address _newStakeHouse,
        bytes calldata _newBlsPublicKey
    ) external authorized {
        if (_indexOfIsolatedKeys >= numOfIsolatedKeys) {
            revert Errors.InvalidIndex();
        }

        uint256 balanceBefore = IERC20Upgradeable(savETH).balanceOf(
            address(this)
        );

        IsolatedKey memory isolatedKey = isolatedKeys[_indexOfIsolatedKeys];
        savETHManager.addKnotToOpenIndex(
            isolatedKey.stakeHouse,
            isolatedKey.blsPublicKey,
            address(this)
        );

        savETHManager.isolateKnotFromOpenIndex(
            _newStakeHouse,
            _newBlsPublicKey,
            savETHIndexOwned
        );

        isolatedKeys[_indexOfIsolatedKeys] = IsolatedKey({
            stakeHouse: _newStakeHouse,
            blsPublicKey: _newBlsPublicKey
        });

        _savETHBalanceChanged(
            balanceBefore,
            IERC20Upgradeable(savETH).balanceOf(address(this))
        );
    }

    /**
     * @dev make sure strategy has enough savETH balance before withdraw
     * @param _savETHAmountToWithdraw the savETH amount to withdraw
     */
    function _savETHWithdrawCheck(uint256 _savETHAmountToWithdraw) internal {
        while (
            IERC20Upgradeable(savETH).balanceOf(address(this)) <
            _savETHAmountToWithdraw &&
            numOfIsolatedKeys > 0
        ) {
            _addKnotToOpenIndex(0);
        }
    }

    /**
     * @dev savETH balance change hook function (will be used to track savETH funds)
     * @param _beforeBalance balance before action
     * @param _afterBalance balance after action
     */
    function _savETHBalanceChanged(
        uint256 _beforeBalance,
        uint256 _afterBalance
    ) internal virtual {}
}
