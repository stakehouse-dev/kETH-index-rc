// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {ISavETHManager} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/ISavETHManager.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {EnumerableSetUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import {SavETHManagerHandler} from "../SavETHManagerHandler.sol";
import {Errors} from "../Errors.sol";
import {DETHVault} from "../deth-vault/DETHVault.sol";
import {AssetRegistry} from "./AssetRegistry.sol";
import {IStrategy} from "./IStrategy.sol";
import {IWstETH} from "./steth/IWstETH.sol";
import {ICurveStETHPool} from "./steth/ICurveStETHPool.sol";
import {IRocketTokenRETH} from "./reth/IRocketTokenRETH.sol";
import {ICurveRETHPool} from "./reth/ICurveRETHPool.sol";
import {ISwapper} from "./swappers/ISwapper.sol";

contract KETHStrategy is
    IStrategy,
    SavETHManagerHandler,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    event UpdateManager(address indexed newManager);
    event UpdateAssetRegistry(address indexed assetRegistry);
    event UpdateDepositCeiling(address indexed underlying, uint256 ceiling);
    event UpdateUnderlyingAsset(address indexed underlying, bool supported);
    event UpdateMinDepositAmount(
        address indexed underlying,
        uint256 minDepositAmount
    );
    event TokenSwap(
        address indexed tokenIn,
        uint256 amountIn,
        address indexed tokenOut,
        uint256 amountOut
    );
    event MigrateFunds(address indexed newStrategy);
    event AcceptMigration(address indexed prevStrategy);

    struct AddressConfig {
        address wstETH;
        address stETH;
        address curveStETHPool; // address for stETH swap
        address rETH;
        address curveRETHPool; // address for rETH swap
    }

    address public constant ETH = address(0);

    AddressConfig public addressConfig;
    address public dETH;
    address public dETHVault;
    address public kETHVault;
    address public manager;
    address public assetRegistry;
    EnumerableSetUpgradeable.AddressSet private _underlyings; // wsteth, reth
    EnumerableSetUpgradeable.AddressSet private _holdingAssets; // wsteth, reth, dETH, savETH
    mapping(address => uint256) public minDepositAmount; // asset => minimum deposit amount
    mapping(address => uint256) private _reserves; // asset => reserve amount (principle)
    mapping(address => uint256) public depositCeiling; // 0: unlimited deposit ceiling
    mapping(address => mapping(address => mapping(address => bool)))
        public swappers; // input token => output token => swapper => supported
    mapping(address => mapping(address => address)) public defaultSwapper;

    // Upgrade for Giant LP support
    address public giantLP;

    function initialize(
        AddressConfig memory _addressConfig,
        address _savETHManager,
        address _dETH,
        address _savETH,
        address _dETHVault,
        address _kETHVault,
        address _giantLP
    ) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __SavETHManagerHandler_init(_savETHManager, _savETH);

        manager = msg.sender;
        addressConfig = _addressConfig;
        dETH = _dETH;
        dETHVault = _dETHVault;
        kETHVault = _kETHVault;
        giantLP = _giantLP;

        // add wstETH, rETH for underlying assets
        minDepositAmount[_addressConfig.wstETH] = 0.01 ether;
        minDepositAmount[_addressConfig.rETH] = 0.01 ether;
        _underlyings.add(_addressConfig.wstETH);
        _underlyings.add(_addressConfig.rETH);

        // add wstETH, rETH, dETH, savETH for holding assets
        _holdingAssets.add(_addressConfig.wstETH);
        _holdingAssets.add(_addressConfig.rETH);
        _holdingAssets.add(_dETH);
        _holdingAssets.add(_savETH);
    }

    modifier onlyManager() {
        if (msg.sender != manager) {
            revert Errors.Unauthorized();
        }
        _;
    }

    modifier onlyVault() {
        if (msg.sender != kETHVault) {
            revert Errors.Unauthorized();
        }
        _;
    }

    // override SavETHManagerHandler

    /**
     * @dev Returns authorized user for SavETHManager
     */
    function _authorizedManager() internal view override returns (address) {
        return manager;
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

    receive() external payable {}

    /**
     * @dev Set strategy manager
     * @param _manager The new strategy manager address
     */
    function setManager(address _manager) external onlyOwner {
        manager = _manager;

        emit UpdateManager(_manager);
    }

    function setGiantLP(address _giantLP) external onlyOwner {
        require(giantLP == address(0), "giantLP already set");

        giantLP = _giantLP;
    }

    /**
     * @dev Set deposit ceiling of each underlying asset
     * @param _underlying The underlying asset address
     * @param _ceiling The deposit ceiling amount of underlying asset
     */
    function setDepositCeiling(
        address _underlying,
        uint256 _ceiling
    ) external onlyManager {
        depositCeiling[_underlying] = _ceiling;

        emit UpdateDepositCeiling(_underlying, _ceiling);
    }

    /**
     * @dev Add swapper
     * @param _input Input asset address
     * @param _output Output asset address
     * @param _swapper The swapper address
     * @param _isDefault Set as default or not
     */
    function addSwapper(
        address _input,
        address _output,
        address _swapper,
        bool _isDefault
    ) external onlyOwner {
        swappers[_input][_output][_swapper] = true;
        if (_isDefault) {
            defaultSwapper[_input][_output] = _swapper;
        }
    }

    /**
     * @dev Remove swapper
     * @param _input Input asset address
     * @param _output Output asset address
     * @param _swapper The swapper address
     */
    function removeSwapper(
        address _input,
        address _output,
        address _swapper
    ) external onlyOwner {
        if (defaultSwapper[_input][_output] == _swapper) {
            revert Errors.RemoveDefaultSwapperBefore();
        }
        swappers[_input][_output][_swapper] = false;
    }

    /**
     * @dev Set default swapper
     * @param _input Input asset address
     * @param _output Output asset address
     * @param _swapper The swapper address
     */
    function setDefaultSwapper(
        address _input,
        address _output,
        address _swapper
    ) external onlyOwner {
        if (!swappers[_input][_output][_swapper]) {
            revert Errors.NotSupportedSwapper();
        }
        defaultSwapper[_input][_output] = _swapper;
    }

    /**
     * @dev Set minimum deposit amount
     * @param _underlying The underlying asset address
     * @param _minDepositAmount The minimum deposit amount
     */
    function setMinDepositAmount(
        address _underlying,
        uint256 _minDepositAmount
    ) external onlyOwner {
        minDepositAmount[_underlying] = _minDepositAmount;

        emit UpdateMinDepositAmount(_underlying, _minDepositAmount);
    }

    /**
     * @dev Add/Remove underlying asset
     * @param _underlying The underlying asset address
     * @param _supported enable or disable
     */
    function setUnderlyingAsset(
        address _underlying,
        bool _supported
    ) external onlyOwner {
        if (_supported) {
            _underlyings.add(_underlying);
            if (!isHoldingAsset(_underlying)) {
                _holdingAssets.add(_underlying);
            }
        } else {
            _underlyings.remove(_underlying);
        }

        emit UpdateUnderlyingAsset(_underlying, _supported);
    }

    /**
     * @dev Returns if the given underlying asset is supported
     * @param _underlying The underlying asset address
     */
    function isUnderlyingAsset(address _underlying) public view returns (bool) {
        return _underlyings.contains(_underlying);
    }

    /**
     * @dev Returns supported underlying assets in array
     */
    function underlyingAssets()
        public
        view
        returns (address[] memory underlyings)
    {
        uint256 length = _underlyings.length();
        underlyings = new address[](length);
        for (uint256 i = 0; i < length; ++i) {
            underlyings[i] = _underlyings.at(i);
        }
    }

    /**
     * @dev Add/Remove holding asset
     * @param _asset The holding asset address
     * @param _supported enable or disable
     */
    function setHoldingAsset(
        address _asset,
        bool _supported
    ) external onlyOwner {
        if (_supported) {
            _holdingAssets.add(_asset);
        } else {
            if (reserves(_asset) > 0) {
                revert Errors.CannotRemoveHoldingAsset();
            }

            _holdingAssets.remove(_asset);
            if (isUnderlyingAsset(_asset)) {
                _underlyings.remove(_asset);
            }
        }
    }

    /**
     * @dev Returns if the given holding asset is supported
     * @param _asset The holding asset address
     */
    function isHoldingAsset(
        address _asset
    ) public view override returns (bool) {
        return _holdingAssets.contains(_asset);
    }

    /**
     * @dev Returns supported holding assets in array
     */
    function holdingAssets() public view returns (address[] memory assets) {
        uint256 length = _holdingAssets.length();
        assets = new address[](length);
        for (uint256 i = 0; i < length; ++i) {
            assets[i] = _holdingAssets.at(i);
        }
    }

    /**
     * @dev Set asset registry
     * @param _assetRegistry The asset regisitry address
     */
    function setAssetRegistry(address _assetRegistry) external onlyOwner {
        assetRegistry = _assetRegistry;

        emit UpdateAssetRegistry(_assetRegistry);
    }

    /**
     * @dev Returns asset value in ETH
     * @param _asset The asset address
     * @param _balance The asset amount
     */
    function assetValue(
        address _asset,
        uint256 _balance
    ) public view override returns (uint256) {
        return AssetRegistry(assetRegistry).assetValue(_asset, _balance);
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
     * @dev Returns total assets value of strategy in ETH
     */
    function totalAssets() public view override returns (uint256 total) {
        address[] memory assets = holdingAssets();
        uint256 length = assets.length;
        for (uint256 i = 0; i < length; ++i) {
            address asset = assets[i];
            total += assetValue(asset, reserves(asset));
        }
    }

    struct AssetRatio {
        address token;
        uint256 valueInETH;
    }

    /**
     * @dev Returns assets ratio
     */
    function assetsRatio() public view returns (AssetRatio[] memory info) {
        address[] memory assets = holdingAssets();
        uint256 length = assets.length;
        info = new AssetRatio[](length);
        for (uint256 i = 0; i < length; ++i) {
            address asset = assets[i];
            info[i].token = asset;
            info[i].valueInETH = assetValue(asset, reserves(asset));
        }
    }

    /**
     * @dev Deposit hook function from kETH vault
     * @param _underlying The underlying asset address
     * @param _amount The underlying asset amount
     * @param _sellForDETH sell or not
     */
    function deposit(
        address _underlying,
        uint256 _amount,
        bool _sellForDETH
    ) external override onlyVault {
        if (_underlying == addressConfig.stETH) {
            _underlying = addressConfig.wstETH;
            _amount = _sellStETHForWstETH(_amount);
        }

        _reserves[_underlying] += _amount;

        if (!isUnderlyingAsset(_underlying)) {
            revert Errors.UnknownAsset();
        }
        if (_amount < minDepositAmount[_underlying]) {
            revert Errors.TooSmall();
        }

        if (_underlying == dETH) {
            _depositToSavETHManager(_amount);
        } else {
            // check deposit ceiling
            uint256 ceiling = depositCeiling[_underlying];
            if (ceiling != 0 && ceiling < reserves(_underlying)) {
                revert Errors.ExceedsDepositCeiling();
            }

            if (_sellForDETH) {
                uint256 dETHAmount = _swapTokenForToken(
                    _underlying,
                    _amount,
                    dETH
                );
                _depositToSavETHManager(dETHAmount);
            }
        }
    }

    /**
     * @dev Withdraw hook function from kETH vault
     * note share/totalSupply represents the withdraw portion of total assets
     * @param _share The kETH amount to burn
     * @param _totalSupply The kETH total supply
     * @param _recipient The recipient address
     * @return ethAmount The withdrawn ETH amount
     * @return dETHAmount The withdrawn dETH amount
     */
    function withdraw(
        uint256 _share,
        uint256 _totalSupply,
        address _recipient
    )
        external
        override
        onlyVault
        returns (uint256 ethAmount, uint256 dETHAmount, uint256 giantLPAmount)
    {
        address[] memory assets = holdingAssets();
        uint256 length = assets.length;
        for (uint256 i = 0; i < length; ++i) {
            address asset = assets[i];
            uint256 amountToWithdraw = (reserves(asset) * _share) /
                _totalSupply;
            if (amountToWithdraw > 0) {
                if (asset == ETH) {
                    ethAmount += amountToWithdraw;
                    _reserves[ETH] -= amountToWithdraw;
                } else if (asset == dETH) {
                    dETHAmount += amountToWithdraw; // there can be some dust dETH which is not deposited into savETH vault
                    _reserves[dETH] -= amountToWithdraw;
                } else if (asset == giantLP) {
                    giantLPAmount += amountToWithdraw;
                    _reserves[giantLP] -= amountToWithdraw;
                } else if (asset == savETH) {
                    if (amountToWithdraw >= 0.001 ether) {
                        _savETHWithdrawCheck(amountToWithdraw);

                        // calculate withdrawn dETH balance
                        uint256 balanceBefore = IERC20Upgradeable(dETH)
                            .balanceOf(address(this));
                        savETHManager.withdraw(
                            address(this),
                            uint128(amountToWithdraw)
                        );
                        uint256 dETHAmountWithdrawn = IERC20Upgradeable(dETH)
                            .balanceOf(address(this)) - balanceBefore;

                        _reserves[savETH] -= amountToWithdraw;

                        dETHAmount += dETHAmountWithdrawn;
                    }
                } else {
                    uint256 ethToWithdraw = _swapTokenForToken(
                        asset,
                        amountToWithdraw,
                        ETH
                    );
                    ethAmount += ethToWithdraw;
                    _reserves[ETH] -= ethToWithdraw;
                }
            }
        }

        if (dETHAmount > 0) {
            // transfer dETH
            IERC20Upgradeable(dETH).safeTransfer(_recipient, dETHAmount);
        }

        if (ethAmount > 0) {
            // transfer eth
            (bool sent, ) = payable(_recipient).call{value: ethAmount}("");
            if (!sent) {
                revert Errors.FailedToSendETH();
            }
        }

        if (giantLPAmount > 0) {
            // transfer Giant LP
            IERC20Upgradeable(giantLP).safeTransfer(_recipient, giantLPAmount);
        }
    }

    /**
     * @dev Sell tokenIn for tokenOut
     * @param _swapper The swapper address
     * @param _tokenIn The input token address
     * @param _amountIn The input token amount
     * @param _tokenOut The output token address
     * @param _minAmountOut The min output token amount
     */
    function invokeSwap(
        address _swapper,
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _minAmountOut,
        bytes memory _extraData
    ) external onlyManager returns (uint256 amountOut) {
        if (!swappers[_tokenIn][_tokenOut][_swapper]) {
            revert Errors.InvalidSwapper();
        }
        if (!isHoldingAsset(_tokenOut)) {
            revert Errors.InvalidTokenOut();
        }

        uint256 tokenInAmountBefore = IERC20Upgradeable(_tokenIn).balanceOf(
            address(this)
        );
        uint256 ethAmountBefore = address(this).balance;
        if (_tokenIn == ETH) {
            amountOut = ISwapper(_swapper).swap{value: _amountIn}(
                _tokenIn,
                _amountIn,
                _tokenOut,
                _minAmountOut,
                _extraData
            );
        } else {
            IERC20Upgradeable(_tokenIn).approve(_swapper, _amountIn);
            amountOut = ISwapper(_swapper).swap(
                _tokenIn,
                _amountIn,
                _tokenOut,
                _minAmountOut,
                _extraData
            );
            IERC20Upgradeable(_tokenIn).approve(_swapper, 0);
        }
        uint256 tokenInAmountUsed = tokenInAmountBefore -
            IERC20Upgradeable(_tokenIn).balanceOf(address(this));
        uint256 ethAmountChanged = address(this).balance - ethAmountBefore;

        _reserves[_tokenIn] -= tokenInAmountUsed;
        _reserves[_tokenOut] += amountOut;

        if (_tokenOut != ETH) {
            _reserves[ETH] += ethAmountChanged;
        }

        if (_tokenOut == dETH) {
            _depositToSavETHManager(amountOut);
        } else if (_tokenOut == giantLP) {
            require(
                IERC20Upgradeable(_tokenOut).balanceOf(address(this)) <=
                    24 ether,
                "Not more than 24 ether"
            );
        }
    }

    function _swapTokenForToken(
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut
    ) internal returns (uint256 amountOut) {
        address swapper = defaultSwapper[_tokenIn][_tokenOut];

        if (_tokenIn == ETH) {
            amountOut = ISwapper(swapper).swap{value: _amountIn}(
                _tokenIn,
                _amountIn,
                _tokenOut,
                0,
                "0x"
            );
        } else {
            IERC20Upgradeable(_tokenIn).approve(swapper, _amountIn);
            amountOut = ISwapper(swapper).swap(
                _tokenIn,
                _amountIn,
                _tokenOut,
                0,
                "0x"
            );
            IERC20Upgradeable(_tokenIn).approve(swapper, 0);
        }

        _reserves[_tokenIn] -= _amountIn;
        _reserves[_tokenOut] += amountOut;
    }

    /**
     * @dev Sell stETH for wstETH
     * @param _stETHAmount The wstETH amount for sell
     */
    function _sellStETHForWstETH(
        uint256 _stETHAmount
    ) internal returns (uint256 wstETHAmount) {
        // wrap steth to wsteth
        IERC20Upgradeable(addressConfig.stETH).approve(
            addressConfig.wstETH,
            _stETHAmount
        );
        wstETHAmount = IWstETH(addressConfig.wstETH).wrap(_stETHAmount);
        IERC20Upgradeable(addressConfig.stETH).approve(
            addressConfig.wstETH,
            _stETHAmount
        );

        emit TokenSwap(
            addressConfig.stETH,
            _stETHAmount,
            addressConfig.wstETH,
            wstETHAmount
        );
    }

    /**
     * @dev Deposit any existing dETH into SavETHManager contract
     * @param _dETHAmount The dETH amount
     */
    function _depositToSavETHManager(uint256 _dETHAmount) internal {
        uint256 savETHBalanceBefore = IERC20Upgradeable(savETH).balanceOf(
            address(this)
        );

        savETHManager.deposit(address(this), uint128(_dETHAmount));

        // update _reserves
        _reserves[dETH] -= _dETHAmount;
        _reserves[savETH] +=
            IERC20Upgradeable(savETH).balanceOf(address(this)) -
            savETHBalanceBefore;
    }

    // Strategy Migration

    /**
     * @dev Transfer existing funds to new strategy address
     * @param _newStrategy The new strategy address
     */
    function migrateFunds(address _newStrategy) external override onlyVault {
        address[] memory assets = holdingAssets();
        uint256 length = assets.length;

        uint256 dETHAmount;
        for (uint256 i = 0; i < length; ++i) {
            address asset = assets[i];
            uint256 reserve = reserves(asset);

            if (!IStrategy(_newStrategy).isHoldingAsset(asset)) {
                revert Errors.AssetNotAllowedInNewStrategy();
            }

            if (reserve > 0) {
                if (asset == savETH) {
                    _savETHWithdrawCheck(reserve);
                    reserve = reserves(savETH);
                }

                if (asset == ETH) {
                    // transfer eth
                    (bool sent, ) = payable(_newStrategy).call{value: reserve}(
                        ""
                    );
                    if (!sent) {
                        revert Errors.FailedToSendETH();
                    }
                    _reserves[ETH] -= reserve;
                } else {
                    IERC20Upgradeable(asset).safeTransfer(
                        _newStrategy,
                        reserve
                    );
                    _reserves[asset] -= reserve;
                }
            }
        }

        // transfer dETH
        IERC20Upgradeable(dETH).safeTransfer(_newStrategy, dETHAmount);
        _reserves[dETH] -= dETHAmount;

        emit MigrateFunds(_newStrategy);
    }

    /**
     * @dev Additional logic to accept funds from previous strategy
     * @param _prevStrategy The previous strategy address
     */
    function acceptMigration(
        address _prevStrategy
    ) external override onlyVault {
        address[] memory assets = holdingAssets();
        uint256 length = assets.length;
        for (uint256 i = 0; i < length; ++i) {
            address asset = assets[i];
            if (asset == ETH) {
                _reserves[asset] = address(this).balance;
            } else {
                _reserves[asset] = IERC20Upgradeable(asset).balanceOf(
                    address(this)
                );
            }
        }
        emit AcceptMigration(_prevStrategy);
    }
}
