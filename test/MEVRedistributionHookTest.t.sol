// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MEVRedistributionHook} from "../src/MEVRedistributionHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {console} from "forge-std/console.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {SqrtPriceMath} from "v4-core/libraries/SqrtPriceMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

contract MEVRedistributionHookTest is Test, Deployers {
    MEVRedistributionHook public hook;
    MockERC20 public rewardToken;

    using BalanceDeltaLibrary for BalanceDelta;

    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    address public lp1;
    address public lp2;

    function setUp() public {
        deployFreshManagerAndRouters();

        vm.prank(address(this));
        // Deploy mock reward token
        rewardToken = new MockERC20("Reward Token", "RWT", 18);
        console.log("rewardToken address", address(rewardToken));
        tokenCurrency = Currency.wrap(address(rewardToken)); // Wrap the reward token address
        // Use CurrencyLibrary to get the address for native ETH
        ethCurrency = CurrencyLibrary.ADDRESS_ZERO;

        uint160 flags = uint160(Hooks.AFTER_ADD_LIQUIDITY_FLAG | Hooks.AFTER_SWAP_FLAG);

        deployCodeTo(
            "MEVRedistributionHook.sol",
            abi.encode(manager, "MEV Redistribution Token", rewardToken, "MEVRT"),
            address(flags)
        );

        hook = MEVRedistributionHook(address(flags));
        rewardToken.approve(address(swapRouter), type(uint256).max);
        rewardToken.approve(address(modifyLiquidityRouter), type(uint256).max);
        rewardToken.mint(address(hook), 5000 ether);
        // Assign LP addresses
        lp1 = address(0x123);
        lp2 = address(0x456);

        // Mint and distribute reward tokens to LPs
        rewardToken.mint(lp1, 1000000 ether);
        rewardToken.mint(lp2, 10000000 ether);

        // LPs approve hook contract to spend their tokens
        vm.prank(lp1);
        rewardToken.approve(address(hook), type(uint256).max);
        hook.approve(address(swapRouter), type(uint256).max);
        hook.approve(address(manager), type(uint256).max);

        vm.prank(lp2);
        rewardToken.approve(address(hook), type(uint256).max);
        hook.approve(address(swapRouter), type(uint256).max);
        hook.approve(address(manager), type(uint256).max);

        // Initialize a pool
        (key,) = initPool(
            ethCurrency, // Currency 0 = ETH
            tokenCurrency, // Currency 1 = TOKEN
            hook, // Hook Contract
            3000, // Swap Fees
            SQRT_PRICE_1_1 // Initial Sqrt(P) value = 1
        );

        // // Add LPs to the hook contract
        // hook._updateLPShares(lp1, 500 ether);
        // hook._updateLPShares(lp2, 500 ether);
    }

    function testAddLiquidityAndSimulateMEVAttack() public {
        // Initial balances
        uint256 initialLP1Balance = rewardToken.balanceOf(lp1);
        uint256 initialLP2Balance = rewardToken.balanceOf(lp2);
        vm.deal(address(hook), 100 ether);
        vm.deal(address(manager), 100 ether);
        vm.deal(address(lp1), 1000000 ether);
        vm.deal(address(lp2), 1000000 ether);

        // Set user address in hook data
        bytes memory hookData = abi.encode(address(this));

        // Define pool parameters
        int24 tickLower = -60;
        int24 tickUpper = 60;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);

        // Calculate liquidity amounts
        uint256 ethAmount = 0.1 ether;
        uint256 tokenAmount = 10 ether;
        // uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
        //     sqrtPriceX96,
        //     TickMath.getSqrtPriceAtTick(tickLower),
        //     TickMath.getSqrtPriceAtTick(tickUpper),
        //     ethAmount,
        //     tokenAmount
        // );

        rewardToken.mint((address(lp1)), 500000000000 ether);

        vm.startPrank(lp1);
        rewardToken.approve(address(hook), type(uint256).max);
        hook.approve(address(swapRouter), type(uint256).max);
        hook.approve(address(manager), type(uint256).max);
        uint128 liquidity =
            LiquidityAmounts.getLiquidityForAmount0(TickMath.getSqrtPriceAtTick(tickLower), SQRT_PRICE_1_1, ethAmount);

        // Add liquidity
        modifyLiquidityRouter.modifyLiquidity{value: ethAmount}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(0)
            }),
            hookData
        );
        vm.stopPrank();
        rewardToken.mint((address(lp2)), 5000000 ether);
        vm.startPrank(lp2);
        rewardToken.approve(address(hook), type(uint256).max);
        hook.approve(address(swapRouter), type(uint256).max);
        hook.approve(address(manager), type(uint256).max);
        liquidity =
            LiquidityAmounts.getLiquidityForAmount0(TickMath.getSqrtPriceAtTick(tickLower), SQRT_PRICE_1_1, ethAmount);

        // Add liquidity
        modifyLiquidityRouter.modifyLiquidity{value: ethAmount}(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(liquidity)),
                salt: bytes32(0)
            }),
            hookData
        );
        vm.stopPrank();
        // Simulate a swap that could be exploited for MEV
        // rewardToken.mint(address(hook), 5000000 ether);
        // uint256 swapAmount = 0.01 ether;
        // swapRouter.swap{value: swapAmount}(
        //     key,
        //     IPoolManager.SwapParams({
        //         zeroForOne: true,
        //         amountSpecified: int256(swapAmount),
        //         sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        //     }),
        //     PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
        //     hookData
        // );

        // Check if MEV was captured and redistributed
        uint256 finalLP1Balance = rewardToken.balanceOf(lp1);
        uint256 finalLP2Balance = rewardToken.balanceOf(lp2);

        // Assert that LP balances have increased due to MEV redistribution
        assert(finalLP1Balance > initialLP1Balance);
        assert(finalLP2Balance > initialLP2Balance);
    }

    // function testAddLiquidityAndSimulateMEVAttack() public {
    //     // Initial balances
    //     uint256 initialLP1Balance = rewardToken.balanceOf(lp1);
    //     uint256 initialLP2Balance = rewardToken.balanceOf(lp2);

    //     // Fund hook and manager
    //     vm.deal(address(hook), 100 ether);
    //     vm.deal(address(manager), 100 ether);
    //     vm.deal(address(lp1), 1000000 ether);
    //     vm.deal(address(lp2), 1000000 ether);

    //     // Set user address in hook data
    //     bytes memory hookData = abi.encode(address(this));

    //     // Define pool parameters
    //     int24 tickLower = -60;
    //     int24 tickUpper = 60;
    //     uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);

    //     // Calculate liquidity amounts
    //     uint256 ethAmount = 0.1 ether;
    //     uint256 tokenAmount = 10 ether;

    //     // Mint tokens for LP1
    //     rewardToken.mint(lp1, 500000000000 ether);

    //     vm.startPrank(lp1);
    //     rewardToken.approve(address(hook), type(uint256).max);

    //     // Calculate liquidity
    //     uint128 liquidity =
    //         LiquidityAmounts.getLiquidityForAmount0(TickMath.getSqrtPriceAtTick(tickLower), SQRT_PRICE_1_1, ethAmount);

    //     // Add liquidity
    //     modifyLiquidityRouter.modifyLiquidity{value: ethAmount}(
    //         key,
    //         IPoolManager.ModifyLiquidityParams({
    //             tickLower: tickLower,
    //             tickUpper: tickUpper,
    //             liquidityDelta: int256(uint256(liquidity)),
    //             salt: bytes32(0)
    //         }),
    //         hookData
    //     );

    //     vm.stopPrank();

    //     // Repeat for LP2
    //     rewardToken.mint(lp2, 5000000 ether);

    //     vm.startPrank(lp2);
    //     rewardToken.approve(address(hook), type(uint256).max);

    //     liquidity =
    //         LiquidityAmounts.getLiquidityForAmount0(TickMath.getSqrtPriceAtTick(tickLower), SQRT_PRICE_1_1, ethAmount);

    //     // Add liquidity for LP2
    //     modifyLiquidityRouter.modifyLiquidity{value: ethAmount}(
    //         key,
    //         IPoolManager.ModifyLiquidityParams({
    //             tickLower: tickLower,
    //             tickUpper: tickUpper,
    //             liquidityDelta: int256(uint256(liquidity)),
    //             salt: bytes32(0)
    //         }),
    //         hookData
    //     );

    //     vm.stopPrank();

    //     // Simulate a swap (uncomment when ready)
    //     /*
    //  * Simulate a swap here that could exploit MEV.
    //  */

    //     // Check final balances after potential MEV capture
    //     uint256 finalLP1Balance = rewardToken.balanceOf(lp1);
    //     uint256 finalLP2Balance = rewardToken.balanceOf(lp2);

    //     // Assert increases in LP balances due to MEV redistribution
    //     assert(finalLP1Balance > initialLP1Balance);
    //     assert(finalLP2Balance > initialLP2Balance);
    // }
}
