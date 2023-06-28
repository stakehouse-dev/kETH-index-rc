// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {Errors} from "../Errors.sol";
import {IStrategy} from "./IStrategy.sol";

contract KETHVault is
    OwnableUpgradeable,
    ERC20Upgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event UpdateStrategy(address indexed newStrategy);
    event UpdateMinLockUpPeriod(uint256 minLockUpPeriod);
    event Deposit(
        address indexed user,
        address indexed underlying,
        uint256 amount,
        address indexed recipient,
        bool sellForDETH
    );
    event Withdraw(
        address indexed user,
        uint256 share,
        uint256 ethAmount,
        uint256 dETHAmount,
        address indexed recipient
    );

    address public constant ETH = address(0);

    address public strategy;
    uint256 public startTime;
    uint256 public minLockUpPeriodForPool;
    uint256 public minLockUpPeriodForUser;
    uint256 public minTransferAmount;
    mapping(address => uint256) public userLastInteractedTimestamp; // user => last interacted timestamp

    function initialize(
        string memory _name,
        string memory _symbol,
        uint256 _minLockUpPeriodForPool,
        uint256 _minLockUpPeriodForUser
    ) public initializer {
        __Ownable_init();
        __ERC20_init(_name, _symbol);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        startTime = block.timestamp;
        minTransferAmount = 0.005 ether;
        minLockUpPeriodForPool = _minLockUpPeriodForPool;
        minLockUpPeriodForUser = _minLockUpPeriodForUser;
    }

    /**
     * @dev Authorize UUPS upgrades
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /**
     * @dev Migrate strategy
     * @param _newStrategy The new strategy address
     */
    function setStrategy(address _newStrategy) external onlyOwner {
        if (_newStrategy == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (strategy != address(0)) {
            // if strategy migration
            // transfer existing funds from previous strategy to new strategy
            IStrategy(strategy).migrateFunds(_newStrategy);
            // accept migration on new strategy (can implement some additional logic for funds migration)
            IStrategy(_newStrategy).acceptMigration(strategy);
        }

        strategy = _newStrategy;

        emit UpdateStrategy(_newStrategy);
    }

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
     * @dev Returns total assets value of vault in ETH
     */
    function totalAssets() public view returns (uint256) {
        return IStrategy(strategy).totalAssets();
    }

    /**
     * @dev Convert ETH value to kETH amount
     */
    function amountToShare(uint256 _amount) public view returns (uint256) {
        if (totalSupply() == 0) {
            return _amount;
        }

        return (_amount * totalSupply()) / totalAssets();
    }

    /**
     * @dev Convert kETH amount to ETH value
     */
    function shareToAmount(uint256 _share) public view returns (uint256) {
        if (totalSupply() == 0) {
            return _share;
        }

        return (_share * totalAssets()) / totalSupply();
    }

    /**
     * @dev Deposit underlying asset
     * @param _underlying The underlying asset address
     * @param _amount The underlying asset amount
     * @param _recipient The receiver address
     * @param _sellForDETH Sell or not
     */
    function deposit(
        address _underlying,
        uint256 _amount,
        address _recipient,
        bool _sellForDETH
    ) external payable nonReentrant returns (uint256 share) {
        if (_recipient == address(0)) {
            revert Errors.ZeroAddress();
        }

        // calculate share
        share = amountToShare(
            IStrategy(strategy).assetValue(_underlying, _amount)
        );

        if (_underlying == ETH) {
            if (msg.value != _amount) {
                revert Errors.InvalidAmount();
            }
            // transfer eth
            (bool sent, ) = payable(address(strategy)).call{value: _amount}("");
            if (!sent) {
                revert Errors.FailedToSendETH();
            }
        } else {
            // deposit into strategy
            // calculate actual deposit amount (consider stETH)
            uint256 balanceBefore = IERC20Upgradeable(_underlying).balanceOf(
                address(strategy)
            );
            IERC20Upgradeable(_underlying).safeTransferFrom(
                msg.sender,
                address(strategy),
                _amount
            );
            _amount =
                IERC20Upgradeable(_underlying).balanceOf(address(strategy)) -
                balanceBefore;
        }

        IStrategy(strategy).deposit(_underlying, _amount, _sellForDETH);

        // mint LP
        _mint(_recipient, share);

        emit Deposit(
            msg.sender,
            _underlying,
            _amount,
            _recipient,
            _sellForDETH
        );
    }

    /**
     * @dev Burn kETH and get ETH and dETH back
     * @param _share The kETH amount to burn
     * @param _recipient The receiver address
     * @return ethAmount The withdrawn ETH amount
     * @return dETHAmount The withdrawn dETH amount
     */
    function withdraw(
        uint256 _share,
        address _recipient
    )
        external
        nonReentrant
        returns (uint256 ethAmount, uint256 dETHAmount, uint256 giantLPAmount)
    {
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

        uint256 _totalSupply = totalSupply();

        // burn LP
        _burn(msg.sender, _share);

        // withdraw funds to user
        (ethAmount, dETHAmount, giantLPAmount) = IStrategy(strategy).withdraw(
            _share,
            _totalSupply,
            _recipient
        );

        emit Withdraw(msg.sender, _share, ethAmount, dETHAmount, _recipient);
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
