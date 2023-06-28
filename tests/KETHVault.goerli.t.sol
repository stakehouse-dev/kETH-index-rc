// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {TestUtils} from "./util.sol";
import {DETHVault} from "../contracts/deth-vault/DETHVault.sol";
import {KETHStrategy} from "../contracts/keth-vault/KETHStrategy.sol";
import {KETHVault} from "../contracts/keth-vault/KETHVault.sol";
import {AssetRegistry} from "../contracts/keth-vault/AssetRegistry.sol";
import {GiantLPToDETH} from "../contracts/keth-vault/swappers/GiantLPToDETH.sol";

contract KETHVaultGoerliTest is TestUtils {
    uint256 constant SLIPPAGE = 0.00001 ether;

    DETHVault dETHVault;
    KETHStrategy kETHStrategy;
    KETHVault kETHVault;
    AssetRegistry assetRegistry;

    function setUp() public {
        prepareGoerliEnvironment();

        // deploy DETH vault
        ERC1967Proxy dETHVaultProxy = new ERC1967Proxy(
            address(new DETHVault()),
            abi.encodeCall(
                DETHVault.initialize,
                (
                    "kwETH",
                    "kwETH",
                    savETHManager,
                    dETH,
                    savETH,
                    0.01 ether,
                    1 weeks,
                    1 weeks
                )
            )
        );
        dETHVault = DETHVault(address(dETHVaultProxy));

        deploySwappers(address(dETHVault));

        // deploy KETH vault
        ERC1967Proxy kETHVaultProxy = new ERC1967Proxy(
            address(new KETHVault()),
            abi.encodeCall(
                KETHVault.initialize,
                ("kETH", "kETH", 30 days, 30 days)
            )
        );
        kETHVault = KETHVault(payable(address(kETHVaultProxy)));

        // deploy KETH strategist
        ERC1967Proxy kETHStrategyProxy = new ERC1967Proxy(
            address(new KETHStrategy()),
            abi.encodeCall(
                KETHStrategy.initialize,
                (
                    KETHStrategy.AddressConfig({
                        wstETH: wstETH,
                        stETH: stETH,
                        curveStETHPool: curveStETHPool,
                        rETH: rETH,
                        curveRETHPool: curveRETHPool
                    }),
                    savETHManager,
                    dETH,
                    savETH,
                    address(dETHVault),
                    address(kETHVault),
                    giantLP
                )
            )
        );
        kETHStrategy = KETHStrategy(payable(address(kETHStrategyProxy)));

        // set strategy
        kETHVault.setStrategy(address(kETHStrategy));

        // set swappers
        kETHStrategy.addSwapper(wstETH, ETH, wstETHToETH, true);
        kETHStrategy.addSwapper(wstETH, dETH, wstETHToDETH, true);
        kETHStrategy.addSwapper(rETH, ETH, rETHToETH, true);
        kETHStrategy.addSwapper(rETH, dETH, rETHToDETH, true);
        kETHStrategy.addSwapper(rETH, giantLP, rETHToGiantLP, true);
        kETHStrategy.addSwapper(wstETH, giantLP, wstETHToGiantLP, true);
        kETHStrategy.addSwapper(giantLP, ETH, giantLPToETH, true);
        kETHStrategy.addSwapper(giantLP, dETH, giantLPToDETH, true);

        // set strategy manager
        kETHStrategy.setManager(strategyManager);
        kETHStrategy.setHoldingAsset(giantLP, true);

        // deploy asset registry
        assetRegistry = new AssetRegistry(
            savETHManager,
            dETH,
            savETH,
            wstETH,
            stETH,
            rETH,
            giantLP
        );
        assetRegistry.setExternalSource(stETH, stETHPriceAggregator);

        // set asset registry
        kETHStrategy.setAssetRegistry(address(assetRegistry));

        // deposit dETH into dETHVault for liquidity
        uint256 dETHAmount = 5 ether;
        prepareDETH(user1, dETHAmount);
        vm.startPrank(user1);
        IERC20(dETH).approve(address(dETHVault), dETHAmount);
        dETHVault.deposit(dETHAmount, user1);
        vm.stopPrank();
    }

    function testSetStrategyManager() public {
        assertEq(kETHStrategy.manager(), strategyManager);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(user1);
        kETHStrategy.setManager(user1);
        vm.stopPrank();

        kETHStrategy.setManager(user1);

        assertEq(kETHStrategy.manager(), user1);
    }

    function testSetDepositCeiling() public {
        assertEq(kETHStrategy.depositCeiling(wstETH), 0);

        vm.expectRevert(bytes4(keccak256("Unauthorized()")));
        vm.startPrank(user1);
        kETHStrategy.setDepositCeiling(wstETH, 1 ether);
        vm.stopPrank();

        vm.startPrank(strategyManager);
        kETHStrategy.setDepositCeiling(wstETH, 1 ether);
        vm.stopPrank();

        assertEq(kETHStrategy.depositCeiling(wstETH), 1 ether);
    }

    function testAddSwapper() public {
        address mockSwapper = address(1);

        assertEq(kETHStrategy.swappers(wstETH, ETH, mockSwapper), false);
        assertEq(kETHStrategy.defaultSwapper(wstETH, ETH), wstETHToETH);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(user1);
        kETHStrategy.addSwapper(wstETH, ETH, mockSwapper, false);
        vm.stopPrank();

        kETHStrategy.addSwapper(wstETH, ETH, mockSwapper, false);
        assertEq(kETHStrategy.swappers(wstETH, ETH, mockSwapper), true);

        kETHStrategy.addSwapper(wstETH, ETH, mockSwapper, true);
        assertEq(kETHStrategy.swappers(wstETH, ETH, mockSwapper), true);
        assertEq(kETHStrategy.defaultSwapper(wstETH, ETH), mockSwapper);
    }

    function testRemoveSwapper() public {
        address mockSwapper = address(1);

        assertEq(kETHStrategy.swappers(wstETH, ETH, wstETHToETH), true);
        assertEq(kETHStrategy.defaultSwapper(wstETH, ETH), wstETHToETH);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(user1);
        kETHStrategy.removeSwapper(wstETH, ETH, wstETHToETH);
        vm.stopPrank();

        vm.expectRevert(bytes4(keccak256("RemoveDefaultSwapperBefore()")));
        kETHStrategy.removeSwapper(wstETH, ETH, wstETHToETH);

        kETHStrategy.addSwapper(wstETH, ETH, mockSwapper, true);

        kETHStrategy.removeSwapper(wstETH, ETH, wstETHToETH);

        assertEq(kETHStrategy.swappers(wstETH, ETH, wstETHToETH), false);
        assertEq(kETHStrategy.defaultSwapper(wstETH, ETH), mockSwapper);
    }

    function testSetDefaultSwapper() public {
        address mockSwapper = address(1);

        assertEq(kETHStrategy.swappers(wstETH, ETH, wstETHToETH), true);
        assertEq(kETHStrategy.defaultSwapper(wstETH, ETH), wstETHToETH);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(user1);
        kETHStrategy.setDefaultSwapper(wstETH, ETH, mockSwapper);
        vm.stopPrank();

        vm.expectRevert(bytes4(keccak256("NotSupportedSwapper()")));
        kETHStrategy.setDefaultSwapper(wstETH, ETH, mockSwapper);

        kETHStrategy.addSwapper(wstETH, ETH, mockSwapper, false);
        assertEq(kETHStrategy.swappers(wstETH, ETH, mockSwapper), true);

        kETHStrategy.setDefaultSwapper(wstETH, ETH, mockSwapper);

        assertEq(kETHStrategy.swappers(wstETH, ETH, wstETHToETH), true);
        assertEq(kETHStrategy.defaultSwapper(wstETH, ETH), mockSwapper);
    }

    function testUnderlyingAssets() public {
        address[] memory underlyingAssets = kETHStrategy.underlyingAssets();
        assertEq(underlyingAssets[0], wstETH);
        assertEq(underlyingAssets[1], rETH);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(user1);
        kETHStrategy.setUnderlyingAsset(stETH, true);
        vm.stopPrank();

        kETHStrategy.setUnderlyingAsset(stETH, true);
        assertEq(kETHStrategy.isUnderlyingAsset(stETH), true);

        // add to holding asset if not
        assertEq(kETHStrategy.isHoldingAsset(ETH), false);

        kETHStrategy.setUnderlyingAsset(ETH, true);
        assertEq(kETHStrategy.isUnderlyingAsset(stETH), true);
        assertEq(kETHStrategy.isHoldingAsset(ETH), true);

        // remove underlying asset
        kETHStrategy.setUnderlyingAsset(stETH, false);
        assertEq(kETHStrategy.isUnderlyingAsset(stETH), false);
    }

    function testHoldingAssets() public {
        address[] memory underlyingAssets = kETHStrategy.holdingAssets();
        assertEq(underlyingAssets[0], wstETH);
        assertEq(underlyingAssets[1], rETH);
        assertEq(underlyingAssets[2], dETH);
        assertEq(underlyingAssets[3], savETH);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(user1);
        kETHStrategy.setHoldingAsset(stETH, true);
        vm.stopPrank();

        kETHStrategy.setHoldingAsset(stETH, true);
        assertEq(kETHStrategy.isHoldingAsset(stETH), true);

        kETHStrategy.setHoldingAsset(stETH, false);
        assertEq(kETHStrategy.isHoldingAsset(stETH), false);

        // remove from underlying asset
        assertEq(kETHStrategy.isUnderlyingAsset(rETH), true);
        kETHStrategy.setHoldingAsset(rETH, false);
        assertEq(kETHStrategy.isUnderlyingAsset(rETH), false);
        assertEq(kETHStrategy.isHoldingAsset(rETH), false);

        prepareWstETH(user1, 30 ether);
        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 30 ether);
        kETHVault.deposit(wstETH, 30 ether, user1, false);
        vm.stopPrank();

        vm.expectRevert(bytes4(keccak256("CannotRemoveHoldingAsset()")));
        kETHStrategy.setHoldingAsset(wstETH, false);
    }

    function testAssetValueWithUnsupportedAsset() public {
        assertEq(kETHStrategy.assetValue(curveStETHPool, 1 ether), 0);
    }

    function testSetStrategyFromUnauthorizedUser() public {
        vm.startPrank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        kETHVault.setStrategy(address(kETHStrategy));
        vm.stopPrank();
    }

    function testSetStrategyWithZeroAddress() public {
        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        kETHVault.setStrategy(address(0));
    }

    function testSetMinTransferAmount() public {
        assertEq(kETHVault.minTransferAmount(), 0.005 ether);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(user1);
        kETHVault.setMinTransferAmount(0.02 ether);
        vm.stopPrank();

        kETHVault.setMinTransferAmount(0.02 ether);

        assertEq(kETHVault.minTransferAmount(), 0.02 ether);
    }

    function testSetMinLockUpPeriod() public {
        assertEq(kETHVault.minLockUpPeriodForPool(), 30 days);
        assertEq(kETHVault.minLockUpPeriodForUser(), 30 days);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(user1);
        kETHVault.setMinLockUpPeriod(2 weeks, 2 weeks);
        vm.stopPrank();

        kETHVault.setMinLockUpPeriod(2 weeks, 2 weeks);

        assertEq(kETHVault.minLockUpPeriodForPool(), 2 weeks);
        assertEq(kETHVault.minLockUpPeriodForUser(), 2 weeks);
    }

    function testRevertWhenSmallAmountTransfer() public {
        prepareStETH(user1, 1 ether);
        vm.startPrank(user1);
        IERC20(stETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(stETH, 1 ether, user1, false);
        vm.stopPrank();

        assertGt(kETHVault.balanceOf(user1), 0);

        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("TooSmall()")));
        kETHVault.transfer(user2, 0.0005 ether);
        vm.stopPrank();
    }

    function testKETHVaultUUPSUpgradeable() public {
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        // upgrade to new implementation address
        KETHVault newImplementation = new KETHVault();
        kETHVault.upgradeTo(address(newImplementation));
        assertEq(
            address(
                uint160(
                    uint256(vm.load(address(kETHVault), implementationSlot))
                )
            ),
            address(newImplementation)
        );

        // test upgrade after renounce ownership
        kETHVault.renounceOwnership();
        assertEq(kETHVault.owner(), address(0));

        vm.expectRevert("Ownable: caller is not the owner");
        kETHVault.upgradeTo(address(newImplementation));
    }

    function testKETHStrategyUUPSUpgradeable() public {
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        // upgrade to new implementation address
        KETHStrategy newImplementation = new KETHStrategy();
        kETHStrategy.upgradeTo(address(newImplementation));
        assertEq(
            address(
                uint160(
                    uint256(vm.load(address(kETHStrategy), implementationSlot))
                )
            ),
            address(newImplementation)
        );

        // test upgrade after renounce ownership
        kETHStrategy.renounceOwnership();
        assertEq(kETHStrategy.owner(), address(0));

        vm.expectRevert("Ownable: caller is not the owner");
        kETHStrategy.upgradeTo(address(newImplementation));
    }

    function testDepositWithZeroAddressRecipient() public {
        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        kETHVault.deposit(wstETH, 1 ether, address(0), false);
    }

    function testDepositWithUnsupportedUnderlyingAsset() public {
        vm.deal(user1, 2 ether);

        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("UnknownAsset()")));
        kETHVault.deposit{value: 1 ether}(address(0), 1 ether, user1, false);
        vm.stopPrank();
    }

    function testDepositTooSmall() public {
        vm.deal(user1, 2 ether);

        kETHStrategy.setUnderlyingAsset(address(0), true);
        kETHStrategy.setMinDepositAmount(address(0), 0.01 ether);

        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("TooSmall()")));
        kETHVault.deposit{value: 0.005 ether}(
            address(0),
            0.005 ether,
            user1,
            false
        );
        vm.stopPrank();
    }

    function testDepositExceedDepositCeiling() public {
        vm.deal(user1, 2 ether);

        kETHStrategy.setUnderlyingAsset(address(0), true);
        kETHStrategy.setMinDepositAmount(address(0), 0.01 ether);

        vm.startPrank(strategyManager);
        kETHStrategy.setDepositCeiling(address(0), 0.9 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("ExceedsDepositCeiling()")));
        kETHVault.deposit{value: 1 ether}(address(0), 1 ether, user1, false);
        vm.stopPrank();
    }

    function testDepositETHIntoKETHVault() public {
        vm.deal(user1, 2 ether);

        kETHStrategy.setUnderlyingAsset(address(0), true);
        kETHStrategy.setMinDepositAmount(address(0), 0.01 ether);

        uint256 expectedShare = kETHVault.amountToShare(1 ether);
        assertEq(kETHVault.shareToAmount(expectedShare), 1 ether);

        vm.startPrank(user1);
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        kETHVault.deposit{value: 1.0001 ether}(
            address(0),
            1 ether,
            user1,
            false
        );
        vm.stopPrank();

        vm.startPrank(user1);
        kETHVault.deposit{value: 1 ether}(address(0), 1 ether, user1, false);
        vm.stopPrank();

        assertEq(kETHVault.balanceOf(user1), 1 ether);
        assertEq(address(kETHStrategy).balance, 1 ether);
    }

    function testDepositWstETHIntoKETHVault() public {
        prepareWstETH(user1, 1 ether);

        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(wstETH, 1 ether, user1, false);
        vm.stopPrank();

        assertGt(kETHVault.balanceOf(user1), 0);
        assertEq(IERC20(wstETH).balanceOf(address(kETHStrategy)), 1 ether);
    }

    function testDepositStETHIntoKETHVault() public {
        prepareStETH(user1, 1 ether);

        vm.startPrank(user1);
        IERC20(stETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(stETH, 1 ether, user1, false);
        vm.stopPrank();

        assertGt(kETHVault.balanceOf(user1), 0);
        assertGt(IERC20(wstETH).balanceOf(address(kETHStrategy)), 0);
    }

    function testDepositWstETHIntoKETHVaultWithSell() public {
        prepareWstETH(user1, 1 ether);

        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(wstETH, 1 ether, user1, true);
        vm.stopPrank();

        assertGt(kETHVault.balanceOf(user1), 0);
        // wstETH is swapped to dETH and deposited into savETHRegistry
        assertEq(IERC20(wstETH).balanceOf(address(kETHStrategy)), 0);
        assertGt(IERC20(savETH).balanceOf(address(kETHStrategy)), 0);
    }

    function testDepositRETHIntoKETHVault() public {
        prepareRETH(user1, 1 ether);

        vm.startPrank(user1);
        IERC20(rETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(rETH, 1 ether, user1, false);
        vm.stopPrank();

        assertGt(kETHVault.balanceOf(user1), 0);
        assertEq(IERC20(rETH).balanceOf(address(kETHStrategy)), 1 ether);
    }

    function testDepositRETHIntoKETHVaultWithSell() public {
        prepareRETH(user1, 1 ether);

        vm.startPrank(user1);
        IERC20(rETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(rETH, 1 ether, user1, true);
        vm.stopPrank();

        assertGt(kETHVault.balanceOf(user1), 0);
        // wstETH is swapped to dETH and deposited into savETHRegistry
        assertEq(IERC20(rETH).balanceOf(address(kETHStrategy)), 0);
        assertGt(IERC20(savETH).balanceOf(address(kETHStrategy)), 0);
    }

    function testWithdrawWithZeroAddressRecipient() public {
        // user 1 deposit wsteth
        prepareWstETH(user1, 1 ether);
        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(wstETH, 1 ether, user1, false);
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 kethBalance = kETHVault.balanceOf(user1);
        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        kETHVault.withdraw(kethBalance, address(0));
        vm.stopPrank();
    }

    function testWithdrawBeforeLockUpPeriod() public {
        // user 1 deposit wsteth
        prepareWstETH(user1, 1 ether);
        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(wstETH, 1 ether, user1, false);
        vm.stopPrank();

        vm.startPrank(user1);
        uint256 kethBalance = kETHVault.balanceOf(user1);
        vm.expectRevert(bytes4(keccak256("ComeBackLater()")));
        kETHVault.withdraw(kethBalance, user1);
        vm.stopPrank();
    }

    function testWithdrawAndReceiveETHAndDETH() public {
        // user 1 deposit wsteth
        prepareWstETH(user1, 1 ether);
        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(wstETH, 1 ether, user1, false);
        vm.stopPrank();

        // user 2 deposit reth with sell
        prepareRETH(user2, 1 ether);
        vm.startPrank(user2);
        IERC20(rETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(rETH, 1 ether, user2, true);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        // user1 withdraw
        vm.startPrank(user1);
        uint256 ethBalance = user1.balance;
        uint256 kethBalance = kETHVault.balanceOf(user1);
        kETHVault.withdraw(kethBalance, user1);
        vm.stopPrank();

        assertEq(kETHVault.balanceOf(user1), 0);
        assertGt(user1.balance, ethBalance);
        assertGt(IERC20(dETH).balanceOf(user1), 0);
    }

    function testSellWstETHForDETH() public {
        // user 1 deposit wsteth
        prepareWstETH(user1, 1 ether);
        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(wstETH, 1 ether, user1, false);
        vm.stopPrank();

        // user 2 deposit reth with sell
        prepareRETH(user2, 1 ether);
        vm.startPrank(user2);
        IERC20(rETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(rETH, 1 ether, user2, false);
        vm.stopPrank();

        // strategy manager sell wstETH for dETH
        vm.startPrank(strategyManager);
        kETHStrategy.invokeSwap(wstETHToDETH, wstETH, 1 ether, dETH, 0, "0x");
        vm.stopPrank();

        assertEq(IERC20(wstETH).balanceOf(address(kETHStrategy)), 0);
        assertGt(IERC20(savETH).balanceOf(address(kETHStrategy)), 0);
    }

    function testSellRETHForDETH() public {
        // user 1 deposit wsteth
        prepareWstETH(user1, 1 ether);
        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(wstETH, 1 ether, user1, false);
        vm.stopPrank();

        // user 2 deposit reth with sell
        prepareRETH(user2, 1 ether);
        vm.startPrank(user2);
        IERC20(rETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(rETH, 1 ether, user2, false);
        vm.stopPrank();

        KETHStrategy.AssetRatio[] memory ratios = kETHStrategy.assetsRatio();
        assertEq(
            ratios[0].valueInETH,
            assetRegistry.assetValue(wstETH, 1 ether)
        );
        assertEq(ratios[1].valueInETH, assetRegistry.assetValue(rETH, 1 ether));

        // strategy manager sell rETH for DETH
        vm.startPrank(strategyManager);
        kETHStrategy.invokeSwap(rETHToDETH, rETH, 1 ether, dETH, 0, "0x");
        vm.stopPrank();

        assertEq(IERC20(rETH).balanceOf(address(kETHStrategy)), 0);
        assertGt(IERC20(savETH).balanceOf(address(kETHStrategy)), 0);

        ratios = kETHStrategy.assetsRatio();
        assertEq(ratios[1].valueInETH, 0);
        assertRange(ratios[3].valueInETH, 1 ether, SLIPPAGE);
    }

    function testSellRETHForGiantLP() public {
        // user 1 deposit wsteth
        prepareWstETH(user1, 1 ether);
        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(wstETH, 1 ether, user1, false);
        vm.stopPrank();

        // user 2 deposit reth with sell
        prepareRETH(user2, 1 ether);
        vm.startPrank(user2);
        IERC20(rETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(rETH, 1 ether, user2, false);
        vm.stopPrank();

        KETHStrategy.AssetRatio[] memory ratios = kETHStrategy.assetsRatio();
        assertEq(
            ratios[0].valueInETH,
            assetRegistry.assetValue(wstETH, 1 ether)
        );
        assertEq(ratios[1].valueInETH, assetRegistry.assetValue(rETH, 1 ether));

        // strategy manager sell rETH for Giant LP
        vm.startPrank(strategyManager);
        kETHStrategy.invokeSwap(rETHToGiantLP, rETH, 1 ether, giantLP, 0, "0x");
        vm.stopPrank();

        assertEq(IERC20(rETH).balanceOf(address(kETHStrategy)), 0);
        assertGt(IERC20(giantLP).balanceOf(address(kETHStrategy)), 0);

        ratios = kETHStrategy.assetsRatio();
        assertEq(ratios[1].valueInETH, 0);
        assertEq(ratios[4].valueInETH, 1 ether);
    }

    function testSellWstETHForGiantLP() public {
        // user 1 deposit wsteth
        prepareWstETH(user1, 1 ether);
        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(wstETH, 1 ether, user1, false);
        vm.stopPrank();

        // user 2 deposit reth with sell
        prepareRETH(user2, 1 ether);
        vm.startPrank(user2);
        IERC20(rETH).approve(address(kETHVault), 1 ether);
        kETHVault.deposit(rETH, 1 ether, user2, false);
        vm.stopPrank();

        // strategy manager sell wstETH for giantLP
        vm.startPrank(strategyManager);
        kETHStrategy.invokeSwap(
            wstETHToGiantLP,
            wstETH,
            1 ether,
            giantLP,
            0,
            "0x"
        );
        vm.stopPrank();

        assertEq(IERC20(wstETH).balanceOf(address(kETHStrategy)), 0);
        assertGt(IERC20(giantLP).balanceOf(address(kETHStrategy)), 1 ether);
    }

    function testSellGiantLPForDETH() public {
        address holder = 0x4AA9833E5D1aA406880D291E3ab7aa284f6E8e86;
        uint256 amount = 140000000000000000;
        vm.startPrank(holder);
        IERC20(giantLP).approve(address(giantLPToDETH), amount);

        address[] memory savETHVaults = new address[](1);
        savETHVaults[0] = 0xA10231d878c859ec22c58CbE93BCe79466AEBc16;
        address[][] memory lpTokens = new address[][](1);
        lpTokens[0] = new address[](1);
        lpTokens[0][0] = 0x6964dD8Ca6cc15aF03cac3fA1B9F2deF9b8e42CE;
        uint256[][] memory amounts = new uint256[][](1);
        amounts[0] = new uint256[](1);
        amounts[0][0] = amount;

        GiantLPToDETH(payable(giantLPToDETH)).swap(
            giantLP,
            amount,
            dETH,
            0,
            abi.encode(savETHVaults, lpTokens, amounts)
        );
        vm.stopPrank();

        assertRange(
            IERC20(dETH).balanceOf(address(holder)),
            amount,
            0.00001 ether
        );
    }

    function testFirstDepositorPotentialAttackWithShares() public {
        // user1 deposit 0.02 stETH
        prepareStETH(user1, 1 ether);
        vm.startPrank(user1);
        IERC20(stETH).approve(address(kETHVault), 0.02 ether);
        kETHVault.deposit(stETH, 0.02 ether, user1, false);
        vm.stopPrank();

        assertRange(kETHStrategy.totalAssets(), 0.02 ether, 0.0005 ether);

        // user1 tries to transfer 100 wstETH
        prepareWstETH(user1, 100 ether);
        vm.startPrank(user1);
        IERC20(wstETH).transfer(address(kETHStrategy), 100 ether);
        vm.stopPrank();

        assertRange(kETHStrategy.totalAssets(), 0.02 ether, 0.0005 ether);

        // user2 deposit 0.02 stETH
        prepareStETH(user2, 3 ether);
        vm.startPrank(user2);
        IERC20(stETH).approve(address(kETHVault), 0.02 ether);
        kETHVault.deposit(stETH, 0.02 ether, user2, false);
        vm.stopPrank();

        assertRange(kETHStrategy.totalAssets(), 0.04 ether, 0.0005 ether);

        // user2 withdraw
        vm.warp(block.timestamp + 30 days);
        uint256 kethBalance = kETHVault.balanceOf(user2);
        vm.startPrank(user2);
        kETHVault.withdraw(kethBalance, user2);
        vm.stopPrank();

        assertRange(user2.balance, 0.02 ether, 0.0005 ether);
    }

    function testWithdrawAssets() public {
        prepareWstETH(user1, 30 ether);
        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 30 ether);
        kETHVault.deposit(wstETH, 30 ether, user1, false);
        vm.stopPrank();

        prepareRETH(user2, 20 ether);
        vm.startPrank(user2);
        IERC20(rETH).approve(address(kETHVault), 20 ether);
        kETHVault.deposit(rETH, 20 ether, user2, false);
        vm.stopPrank();

        kETHStrategy.setUnderlyingAsset(dETH, true);
        kETHStrategy.setMinDepositAmount(dETH, 0.01 ether);
        prepareDETH(user3, 50 ether);
        vm.startPrank(user3);
        IERC20(dETH).approve(address(kETHVault), 50 ether);
        kETHVault.deposit(dETH, 50 ether, user3, false);
        vm.stopPrank();

        kETHStrategy.setUnderlyingAsset(ETH, true);
        kETHStrategy.setMinDepositAmount(ETH, 0.01 ether);
        vm.deal(user4, 50 ether);
        vm.startPrank(user4);
        kETHVault.deposit{value: 50 ether}(ETH, 50 ether, user4, false);
        vm.stopPrank();

        address stakeHouse = 0xC31a8e5d944F011927E9C884DF5a990Ee6B72071;
        bytes
            memory blsPublicKey = hex"8021cca323eb594a275752032852777098ef5bc7970db412c9c2c10be3f083d1e02fbe5d0992f24e9aa52a9f7815fe59";
        vm.startPrank(strategyManager);
        kETHStrategy.isolateKnotFromOpenIndex(stakeHouse, blsPublicKey);
        vm.stopPrank();

        uint256 totalAssetsBefore = kETHStrategy.totalAssets();
        uint256 balance = kETHVault.balanceOf(user4);
        uint256 assetsToWithdraw = kETHVault.shareToAmount(balance);
        vm.warp(block.timestamp + 30 days);
        vm.startPrank(user4);
        kETHVault.withdraw(balance, user4);
        vm.stopPrank();

        uint256 totalAssetsAfter = kETHStrategy.totalAssets();
        assertRange(
            totalAssetsAfter,
            totalAssetsBefore - assetsToWithdraw,
            SLIPPAGE
        );
    }

    function testWithdrawAllAssets() public {
        prepareWstETH(user1, 30 ether);
        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 30 ether);
        kETHVault.deposit(wstETH, 30 ether, user1, false);
        vm.stopPrank();

        prepareRETH(user1, 20 ether);
        vm.startPrank(user1);
        IERC20(rETH).approve(address(kETHVault), 20 ether);
        kETHVault.deposit(rETH, 20 ether, user1, false);
        vm.stopPrank();

        kETHStrategy.setUnderlyingAsset(dETH, true);
        kETHStrategy.setMinDepositAmount(dETH, 0.01 ether);
        prepareDETH(user1, 50 ether);
        vm.startPrank(user1);
        IERC20(dETH).approve(address(kETHVault), 50 ether);
        kETHVault.deposit(dETH, 50 ether, user1, false);
        vm.stopPrank();

        kETHStrategy.setUnderlyingAsset(ETH, true);
        kETHStrategy.setMinDepositAmount(ETH, 0.01 ether);
        vm.deal(user1, 50 ether);
        vm.startPrank(user1);
        kETHVault.deposit{value: 50 ether}(ETH, 50 ether, user1, false);
        vm.stopPrank();

        address stakeHouse = 0xC31a8e5d944F011927E9C884DF5a990Ee6B72071;
        bytes
            memory blsPublicKey = hex"8021cca323eb594a275752032852777098ef5bc7970db412c9c2c10be3f083d1e02fbe5d0992f24e9aa52a9f7815fe59";
        vm.startPrank(strategyManager);
        kETHStrategy.isolateKnotFromOpenIndex(stakeHouse, blsPublicKey);
        vm.stopPrank();

        uint256 totalAssetsBefore = kETHStrategy.totalAssets();
        uint256 balance = kETHVault.balanceOf(user1);
        uint256 assetsToWithdraw = kETHVault.shareToAmount(balance);
        assertEq(totalAssetsBefore, assetsToWithdraw);
        vm.warp(block.timestamp + 30 days);
        vm.startPrank(user1);
        kETHVault.withdraw(balance, user1);
        vm.stopPrank();

        uint256 totalAssetsAfter = kETHStrategy.totalAssets();
        assertEq(totalAssetsAfter, 0);
    }

    function testStrategyMigration() public {
        prepareWstETH(user1, 30 ether);
        vm.startPrank(user1);
        IERC20(wstETH).approve(address(kETHVault), 30 ether);
        kETHVault.deposit(wstETH, 30 ether, user1, false);
        vm.stopPrank();

        prepareRETH(user2, 20 ether);
        vm.startPrank(user2);
        IERC20(rETH).approve(address(kETHVault), 20 ether);
        kETHVault.deposit(rETH, 20 ether, user2, false);
        vm.stopPrank();

        kETHStrategy.setUnderlyingAsset(dETH, true);
        kETHStrategy.setMinDepositAmount(dETH, 0.01 ether);
        prepareDETH(user3, 50 ether);
        vm.startPrank(user3);
        IERC20(dETH).approve(address(kETHVault), 50 ether);
        kETHVault.deposit(dETH, 50 ether, user3, false);
        vm.stopPrank();

        kETHStrategy.setUnderlyingAsset(ETH, true);
        kETHStrategy.setMinDepositAmount(ETH, 0.01 ether);
        vm.deal(user4, 50 ether);
        vm.startPrank(user4);
        kETHVault.deposit{value: 50 ether}(ETH, 50 ether, user4, false);
        vm.stopPrank();

        address stakeHouse = 0xC31a8e5d944F011927E9C884DF5a990Ee6B72071;
        bytes
            memory blsPublicKey = hex"8021cca323eb594a275752032852777098ef5bc7970db412c9c2c10be3f083d1e02fbe5d0992f24e9aa52a9f7815fe59";
        vm.startPrank(strategyManager);
        kETHStrategy.isolateKnotFromOpenIndex(stakeHouse, blsPublicKey);
        vm.stopPrank();

        // deploy KETH strategist
        ERC1967Proxy kETHStrategyProxy = new ERC1967Proxy(
            address(new KETHStrategy()),
            abi.encodeCall(
                KETHStrategy.initialize,
                (
                    KETHStrategy.AddressConfig({
                        wstETH: wstETH,
                        stETH: stETH,
                        curveStETHPool: curveStETHPool,
                        rETH: rETH,
                        curveRETHPool: curveRETHPool
                    }),
                    savETHManager,
                    dETH,
                    savETH,
                    address(dETHVault),
                    address(kETHVault),
                    giantLP
                )
            )
        );
        KETHStrategy newStrategy = KETHStrategy(
            payable(address(kETHStrategyProxy))
        );
        // set asset registry
        newStrategy.setAssetRegistry(address(assetRegistry));

        uint256 totalAssetsBefore = kETHStrategy.totalAssets();

        vm.expectRevert(bytes4(keccak256("AssetNotAllowedInNewStrategy()")));
        kETHVault.setStrategy(address(newStrategy));

        newStrategy.setUnderlyingAsset(ETH, true);
        kETHVault.setStrategy(address(newStrategy));

        uint256 totalAssetsAfter = newStrategy.totalAssets();
        assertRange(totalAssetsBefore, totalAssetsAfter, 100);
    }
}
