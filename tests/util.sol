// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CurveStETHPool} from "../contracts/mocks/CurveStETHPool.sol";
import {CurveRETHPool} from "../contracts/mocks/CurveRETHPool.sol";
import {WstETHToETH} from "../contracts/keth-vault/swappers/WstETHToETH.sol";
import {WstETHToDETH} from "../contracts/keth-vault/swappers/WstETHToDETH.sol";
import {RETHToETH} from "../contracts/keth-vault/swappers/RETHToETH.sol";
import {RETHToDETH} from "../contracts/keth-vault/swappers/RETHToDETH.sol";
import {RETHToGiantLP} from "../contracts/keth-vault/swappers/RETHToGiantLP.sol";
import {WstETHToGiantLP} from "../contracts/keth-vault/swappers/WstETHToGiantLP.sol";
import {GiantLPToDETH} from "../contracts/keth-vault/swappers/GiantLPToDETH.sol";
import {GiantLPToETH} from "../contracts/keth-vault/swappers/GiantLPToETH.sol";
import {IWstETH} from "../contracts/keth-vault/steth/IWstETH.sol";
import {IRocketDepositPool} from "../contracts/keth-vault/reth/IRocketDepositPool.sol";
import {MockAssetPriceAggregator} from "../contracts/mocks/MockAssetPriceAggregator.sol";

contract TestUtils is Test {
    bool isMainnet = false;

    address public constant ETH = address(0);
    address savETHManager;
    address dETH;
    address savETH;
    address giantLP;
    address giantSavETHVaultPool;
    address wstETH;
    address stETH;
    address rETH;
    address rocketDepositPool;
    address curveStETHPool;
    address curveRETHPool;
    address dETHHolder;
    address rETHHolder;
    address stETHHolder;
    address wstETHHolder;

    address stETHPriceAggregator;

    /// Define some test accounts
    address strategyManager = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address user1 = 0xdD2FD4581271e230360230F9337D5c0430Bf44C0;
    address user2 = 0xbDA5747bFD65F08deb54cb465eB87D40e51B197E;
    address user3 = 0x2546BcD3c84621e976D8185a91A922aE77ECEc30;
    address user4 = 0xbE3381530BA425Eb0322f66586e11e17B1643255;

    address wstETHToETH;
    address wstETHToDETH;
    address rETHToETH;
    address rETHToDETH;
    address rETHToGiantLP;
    address wstETHToGiantLP;
    address giantLPToETH;
    address giantLPToDETH;

    function prepareGoerliEnvironment() public {
        // fork goerli by default
        string memory GOERLI_URL = vm.envString("GOERLI_URL");
        uint256 goerliFork = vm.createFork(GOERLI_URL);
        vm.selectFork(goerliFork);
        assertEq(vm.activeFork(), goerliFork);

        isMainnet = false;
        savETHManager = 0x9Ef3Bb02CadA3e332Bbaa27cd750541c5FFb5b03;
        dETH = 0x506C2B850D519065a4005b04b9ceed946A64CB6F;
        savETH = 0x6BC3266716Df5881A9856491AB93303f725a3047;
        giantLP = 0x873920ca5128dBd6B9b3138e91ff2e3eB4586f47;
        giantSavETHVaultPool = 0x7e30089243E412291e9e5b981F9018Ca40e84eED;
        wstETH = 0x6320cD32aA674d2898A68ec82e869385Fc5f7E2f;
        stETH = 0x1643E812aE58766192Cf7D2Cf9567dF2C37e9B7F;
        rETH = 0x178E141a0E3b34152f73Ff610437A7bf9B83267A;
        rocketDepositPool = 0xa9A6A14A3643690D0286574976F45abBDAD8f505;
        dETHHolder = 0x2cEf68303e40be7bb3b89B93184368fC5fCE6653;
        rETHHolder = 0xc14A6AEec328C0690d0387584b3f92348629917F;
        stETHHolder = 0x97E6F3c884117a48A4e9526d7541FD95D712e9bf;
        wstETHHolder = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

        // charge more wstETH for testing (should be at least 100 wstETH)
        vm.startPrank(0xF890982f9310df57d00f659cf4fd87e65adEd8d7);
        IERC20(wstETH).transfer(
            wstETHHolder,
            IERC20(wstETH).balanceOf(0xF890982f9310df57d00f659cf4fd87e65adEd8d7)
        );
        vm.stopPrank();

        vm.startPrank(0xF99834937715255079849BE25ba31BF8b5D5B45D);
        IERC20(wstETH).transfer(
            wstETHHolder,
            IERC20(wstETH).balanceOf(0xF99834937715255079849BE25ba31BF8b5D5B45D)
        );
        vm.stopPrank();

        // deploy mocked curve pools
        curveStETHPool = address(new CurveStETHPool(stETH));
        curveRETHPool = address(new CurveRETHPool(rETH));

        // charge ETH for curve pools
        vm.deal(curveStETHPool, 100 ether);
        vm.deal(curveRETHPool, 100 ether);
        stETHPriceAggregator = address(new MockAssetPriceAggregator());
    }

    function prepareMainnetEnvironment() public {
        // fork mainnet by default
        string memory MAINNET_URL = vm.envString("MAINNET_URL");
        uint256 mainnetFork = vm.createFork(MAINNET_URL);
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);

        isMainnet = true;
        savETHManager = 0x9CbC2Bf747510731eE3A38bf209a299261038369;
        dETH = 0x3d1E5Cf16077F349e999d6b21A4f646e83Cd90c5;
        savETH = 0x00EE7ea7CA2B5cC47908f0cad1f296efbde1402e;
        wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        rETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
        rocketDepositPool = 0x2cac916b2A963Bf162f076C0a8a4a8200BCFBfb4;
        dETHHolder = 0x919c550eF1ca909e71bE72Bb792Adbafa6ab5A25;
        rETHHolder = 0x5313b39bf226ced2332C81eB97BB28c6fD50d1a3;
        stETHHolder = 0x41318419CFa25396b47A94896FfA2C77c6434040;
        wstETHHolder = 0x5fEC2f34D80ED82370F733043B6A536d7e9D7f8d;

        // charge more dETH for testing (should be at least 100 dETH)
        vm.startPrank(0x1A31C94f97C649bC2a8aDbCeb54D1f4a075be4b1);
        IERC20(dETH).transfer(
            dETHHolder,
            IERC20(dETH).balanceOf(0x1A31C94f97C649bC2a8aDbCeb54D1f4a075be4b1)
        );
        vm.stopPrank();

        vm.startPrank(0x3F55db8aa07EaEB4a5541954481eb4B5056301d5);
        IERC20(dETH).transfer(
            dETHHolder,
            IERC20(dETH).balanceOf(0x3F55db8aa07EaEB4a5541954481eb4B5056301d5)
        );
        vm.stopPrank();

        vm.startPrank(0x634c594De9d4154ed93251e6C0692Fe00a4b9797);
        IERC20(dETH).transfer(
            dETHHolder,
            IERC20(dETH).balanceOf(0x634c594De9d4154ed93251e6C0692Fe00a4b9797)
        );
        vm.stopPrank();

        vm.startPrank(0x0DF02a9c5fE1B67b0D82c7113B7D1b27388cef78);
        IERC20(dETH).transfer(
            dETHHolder,
            IERC20(dETH).balanceOf(0x0DF02a9c5fE1B67b0D82c7113B7D1b27388cef78)
        );
        vm.stopPrank();

        vm.startPrank(0x552262a0a3470b6ee9Dc296A0c33dC152412bEf7);
        IERC20(dETH).transfer(
            dETHHolder,
            IERC20(dETH).balanceOf(0x552262a0a3470b6ee9Dc296A0c33dC152412bEf7)
        );
        vm.stopPrank();

        curveStETHPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        curveRETHPool = 0x0f3159811670c117c372428D4E69AC32325e4D0F;
        stETHPriceAggregator = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    }

    function deploySwappers(address dETHVault) public {
        wstETHToETH = address(new WstETHToETH(wstETH, stETH, curveStETHPool));
        wstETHToDETH = address(
            new WstETHToDETH(wstETH, stETH, curveStETHPool, dETH, dETHVault)
        );
        rETHToETH = address(new RETHToETH(rETH, curveRETHPool));
        rETHToDETH = address(
            new RETHToDETH(rETH, curveRETHPool, dETH, dETHVault)
        );
        rETHToGiantLP = address(
            new RETHToGiantLP(
                rETH,
                curveRETHPool,
                giantLP,
                giantSavETHVaultPool
            )
        );
        wstETHToGiantLP = address(
            new WstETHToGiantLP(
                wstETH,
                stETH,
                curveStETHPool,
                giantLP,
                giantSavETHVaultPool
            )
        );
        giantLPToETH = address(new GiantLPToETH(giantLP, giantSavETHVaultPool));
        giantLPToDETH = address(
            new GiantLPToDETH(dETH, giantLP, giantSavETHVaultPool)
        );
    }

    function prepareStETH(
        address account,
        uint256 amount
    ) public returns (uint256) {
        vm.startPrank(stETHHolder);
        IERC20(stETH).transfer(account, amount);
        vm.stopPrank();

        return IERC20(stETH).balanceOf(account);
    }

    function prepareWstETH(
        address account,
        uint256 amount
    ) public returns (uint256) {
        vm.startPrank(wstETHHolder);
        IERC20(wstETH).transfer(account, amount);
        vm.stopPrank();

        return IERC20(wstETH).balanceOf(account);
    }

    function prepareRETH(
        address account,
        uint256 amount
    ) public returns (uint256) {
        vm.startPrank(rETHHolder);
        IERC20(rETH).transfer(account, amount);
        vm.stopPrank();

        return IERC20(rETH).balanceOf(account);
    }

    function prepareDETH(
        address account,
        uint256 amount
    ) public returns (uint256) {
        vm.startPrank(dETHHolder);
        IERC20(dETH).transfer(account, amount);
        vm.stopPrank();

        return IERC20(dETH).balanceOf(account);
    }

    function assertRange(
        uint256 value,
        uint256 expectedValue,
        uint256 range
    ) public {
        if (expectedValue > range) {
            assertGt(value, expectedValue - range);
        } else {
            assertGt(value, expectedValue);
        }

        assertLt(value, expectedValue + range);
    }
}
