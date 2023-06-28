// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {ISavETHManager} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/ISavETHManager.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {SavETHManagerHandler} from "../SavETHManagerHandler.sol";
import {Errors} from "../Errors.sol";
import "hardhat/console.sol";

contract DETHVault is
    SavETHManagerHandler,
    OwnableUpgradeable,
    ERC20Upgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event Deposit(
        address indexed user,
        uint256 dETHAmount,
        uint256 share,
        address indexed recipient
    );
    event WithdrawToETH(
        address indexed user,
        uint256 ethAmount,
        uint256 share,
        address indexed recipient
    );
    event WithdrawToDETH(
        address indexed user,
        uint256 dETHAmount,
        uint256 share,
        address indexed recipient
    );
    event SwapETHToDETH(
        address indexed user,
        uint256 ethAmount,
        uint256 dETHAmount,
        address indexed recipient
    );

    address public constant ETH = address(0);

    address public dETH;

    uint256 public startTime;
    uint256 public minLockUpPeriodForPool;
    uint256 public minLockUpPeriodForUser;
    uint256 public minTransferAmount;
    uint256 public minDepositAmount; // asset => minimum deposit amount
    mapping(address => uint256) public userLastInteractedTimestamp; // user => last interacted timestamp
    mapping(address => uint256) private _reserves; // asset => reserve amount (principle)

    function initialize(
        string memory _name,
        string memory _symbol,
        address _savETHManager,
        address _dETH,
        address _savETH,
        uint256 _minDepositAmount,
        uint256 _minLockUpPeriodForPool,
        uint256 _minLockUpPeriodForUser
    ) public initializer {
        __Ownable_init();
        __ERC20_init(_name, _symbol);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __SavETHManagerHandler_init(_savETHManager, _savETH);

        startTime = block.timestamp;
        dETH = _dETH;
        minTransferAmount = 0.01 ether;
        minDepositAmount = _minDepositAmount;
        minLockUpPeriodForPool = _minLockUpPeriodForPool;
        minLockUpPeriodForUser = _minLockUpPeriodForUser;
    }

    // override SavETHManagerHandler

    /**
     * @dev Returns authorized user for SavETHManager
     */
    function _authorizedManager() internal view override returns (address) {
        return owner();
    }

    /**
     * @dev savETH balance change hook function (will be used to track savETH funds)
     * @param _beforeBalance balance before action
     * @param _afterBalance balance after action
     */
    function _savETHBalanceChanged(
        uint256 _beforeBalance,
        uint256 _afterBalance
    ) internal override {
        _reserves[savETH] = _reserves[savETH] + _afterBalance - _beforeBalance;
    }

    /**
     * @dev Authorize UUPS upgrades
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @dev Set minimum transfer amount
     * @param _minTransferAmount The minimum transfer amount
     */
    function setMinTransferAmount(
        uint256 _minTransferAmount
    ) external onlyOwner {
        minTransferAmount = _minTransferAmount;
    }

    /**
     * @dev Set minimum deposit amount
     * @param _minDepositAmount The minimum deposit amount
     */
    function setMinDepositAmount(uint256 _minDepositAmount) external onlyOwner {
        minDepositAmount = _minDepositAmount;
    }

    /**
     * @dev Set minimum lock up period
     * @param _minLockUpPeriodForPool The minimum lock up period for pool
     * @param _minLockUpPeriodForUser The minimum lock up period for user
     */
    function setMinLockUpPeriod(
        uint256 _minLockUpPeriodForPool,
        uint256 _minLockUpPeriodForUser
    ) external onlyOwner {
        minLockUpPeriodForPool = _minLockUpPeriodForPool;
        minLockUpPeriodForUser = _minLockUpPeriodForUser;
    }

    /**
     * @dev Return reserve value of token
     * @param _token The token address
     */
    function reserves(address _token) public view returns (uint256) {
        if (_token == savETH) {
            return _reserves[savETH] + _totalIsolatedSavETH();
        }

        return _reserves[_token];
    }

    /**
     * @dev Returns total ETH/dETH balance of vault
     */
    function totalAssets() public view returns (uint256) {
        return
            reserves(ETH) +
            reserves(dETH) +
            savETHManager.savETHToDETH(reserves(savETH));
    }

    /**
     * @dev Convert ETH/dETH amount to LP token amount
     */
    function amountToShare(uint256 _amount) public view returns (uint256) {
        if (totalSupply() == 0) {
            return _amount;
        }

        return (_amount * totalSupply()) / totalAssets();
    }

    /**
     * @dev Convert LP token amount to ETH/dETH amount
     */
    function shareToAmount(uint256 _share) public view returns (uint256) {
        if (totalSupply() == 0) {
            return _share;
        }

        return (_share * totalAssets()) / totalSupply();
    }

    /**
     * @dev Deposit dETH and get LP token back
     * @param _amount The dETH amount to deposit
     * @param _recipient The receiver address
     */
    function deposit(
        uint256 _amount,
        address _recipient
    ) external nonReentrant {
        if (_recipient == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (_amount < minDepositAmount) {
            revert Errors.TooSmall();
        }

        // calculate share
        uint256 share = amountToShare(_amount);

        // deposit into savETHManager
        _reserves[dETH] += _amount;
        IERC20Upgradeable(dETH).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        _depositToSavETHManager();

        // mint LP
        _mint(_recipient, share);

        emit Deposit(msg.sender, _amount, share, _recipient);
    }

    /**
     * @dev Burn LP token and get ETH back
     * @param _share The LP token amount to burn
     * @param _recipient The receiver address
     */
    function withdrawToETH(
        uint256 _share,
        address _recipient
    ) external nonReentrant {
        if (_recipient == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (
            startTime + minLockUpPeriodForPool > block.timestamp ||
            userLastInteractedTimestamp[msg.sender] + minLockUpPeriodForUser >
            block.timestamp
        ) {
            revert Errors.ComeBackLater();
        }

        // calculate amount
        uint256 amount = shareToAmount(_share);

        // burn LP
        _burn(msg.sender, _share);

        // withdraw ETH to user
        (bool sent, ) = payable(_recipient).call{value: amount}("");
        if (!sent) {
            revert Errors.FailedToSendETH();
        }

        // update _reserves
        _reserves[ETH] -= amount;

        emit WithdrawToETH(msg.sender, amount, _share, _recipient);
    }

    /**
     * @dev Burn LP token and get dETH back
     * @param _share The LP token amount to burn
     * @param _recipient The receiver address
     */
    function withdrawToDETH(
        uint256 _share,
        address _recipient
    ) external nonReentrant {
        if (_recipient == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (
            startTime + minLockUpPeriodForPool > block.timestamp ||
            userLastInteractedTimestamp[msg.sender] + minLockUpPeriodForUser >
            block.timestamp
        ) {
            revert Errors.ComeBackLater();
        }

        // calculate amount
        uint256 amount = shareToAmount(_share);

        // burn LP
        _burn(msg.sender, _share);

        // withdraw dETH to user
        _transferDETH(_recipient, amount, false);

        emit WithdrawToDETH(msg.sender, amount, _share, _recipient);
    }

    /**
     * @dev Deposit ETH and get dETH back
     * @param _recipient The receiver address
     */
    function swapETHToDETH(address _recipient) external payable nonReentrant {
        if (_recipient == address(0)) {
            revert Errors.ZeroAddress();
        }

        uint256 amount = msg.value;

        // update _reserves
        _reserves[ETH] += amount;

        _transferDETH(_recipient, amount, true);

        emit SwapETHToDETH(msg.sender, amount, amount, _recipient);
    }

    /**
     * @dev Deposit any existing dETH into SavETHManager contract
     */
    function _depositToSavETHManager() internal {
        uint256 dETHAmount = _reserves[dETH];
        uint256 savETHBalanceBefore = IERC20Upgradeable(savETH).balanceOf(
            address(this)
        );

        savETHManager.deposit(address(this), uint128(dETHAmount));

        // update _reserves
        _reserves[dETH] -= dETHAmount;
        _reserves[savETH] +=
            IERC20Upgradeable(savETH).balanceOf(address(this)) -
            savETHBalanceBefore;
    }

    /**
     * @dev Withdraw dETH from SavETHManager and transfer to the user address
     * @param _recipient The receiver address
     * @param _dETHAmount The dETH amount to withdraw and transfer
     * @param _exactAmount Transfer exact amount or not
     */
    function _transferDETH(
        address _recipient,
        uint256 _dETHAmount,
        bool _exactAmount
    ) internal {
        uint256 savETHAmountToWithdraw = savETHManager.dETHToSavETH(
            _dETHAmount
        );

        _savETHWithdrawCheck(savETHAmountToWithdraw + 1);

        if (savETHAmountToWithdraw + 1 <= reserves(savETH)) {
            // need to consider remainder from division
            savETHAmountToWithdraw += 1;
        }

        uint256 dETHBalanceBefore = IERC20Upgradeable(dETH).balanceOf(
            address(this)
        );

        savETHManager.withdraw(address(this), uint128(savETHAmountToWithdraw));

        uint256 withdrawnBalance = IERC20Upgradeable(dETH).balanceOf(
            address(this)
        ) - dETHBalanceBefore;

        // update _reserves
        _reserves[savETH] -= savETHAmountToWithdraw;
        _reserves[dETH] += withdrawnBalance;

        if (_exactAmount) {
            IERC20Upgradeable(dETH).safeTransfer(_recipient, _dETHAmount);

            // update _reserves
            _reserves[dETH] -= _dETHAmount;
        } else {
            IERC20Upgradeable(dETH).safeTransfer(_recipient, withdrawnBalance);

            // update _reserves
            _reserves[dETH] -= withdrawnBalance;
        }
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal view override {
        if (_from != address(0) && _to != address(0)) {
            if (_amount < minTransferAmount) {
                revert Errors.TooSmall();
            }
        }
    }

    function _afterTokenTransfer(
        address _from,
        address _to,
        uint256
    ) internal override {
        userLastInteractedTimestamp[_from] = block.timestamp;
        userLastInteractedTimestamp[_to] = block.timestamp;
    }
}
