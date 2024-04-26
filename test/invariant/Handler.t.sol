// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { PoolFactory } from "../../src/PoolFactory.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { ERC2Mock } from "../mocks/ERC20Mock.sol";
import { TSwapPool } from "../../src/TSwapPool.sol";

contract Handler is Test {
    // these pools have 2 assets
    ERC2Mock poolToken;
    ERC2Mock weth;
    address liquidityProvider = makeAddr("lp");
    address swapper = makeAddr("swapper");

    TSwapPool pool; // poolToken /Weth
    PoolFactory factory;

    // ghost variable
    int256 startingY;
    int256 startingX;

    int256 public expectedDeltaY;
    int256 public expectedDeltaX; // change in token balances

    int256 public actualDelataY;
    int256 public actualDeltaX; // actual token balance

    constructor(TSwapPool _pool) {
        pool = _pool;
        weth = ERC2Mock(pool.getWeth());
        poolToken = ERC2Mock(pool.getPoolToken());
    }

    // Final invariant equation without fees:
    // ∆x = (β/(1-β)) * x
    // ∆y = (α/(1+α)) * y
    // deposit, swapExactOutput

    function swapPollTokenForWethBasedOnOutputWeth(uint256 outputWeth) public {
        uint256 minWeth = pool.getMinimumWethDepositAmount();
        outputWeth = bound(outputWeth, minWeth, type(uint256).max);

        if (outputWeth >= weth.balanceOf(address(pool))) {
            return;
        }
        // delta x
        // dealta x = (b / 1-p * x)
        // x * y = x * y - x * outputAmount + deltax * y - x*outputAmount

        uint256 poolTokenAmount = pool.getInputAmountBasedOnOutput(
            outputWeth, poolToken.balanceOf(address(pool)), weth.balanceOf(address(pool))
        );

        if (poolTokenAmount > type(uint64).max) {
            return;
        }

        startingY = int256(weth.balanceOf(address(pool)));
        startingX = int256(poolToken.balanceOf(address(pool)));

        expectedDeltaY = int256(-1) * int256(outputWeth);
        //    return (wethToDeposit * poolTokenReserves) / wethReserves;
        expectedDeltaX = int256(poolTokenAmount);

        // return ((inputReserves * outputAmount) * 10000) / ((outputReserves - outputAmount) * 997);

        if (poolToken.balanceOf(swapper) < poolTokenAmount) {
            poolToken.mint(swapper, poolTokenAmount - poolToken.balanceOf(swapper) + 1);
        }

        // swap
        vm.startPrank(swapper);

        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));

        vm.stopPrank();

        uint256 endingY = weth.balanceOf(address(pool));
        uint256 endingX = poolToken.balanceOf(address(pool));
        // (△y * X) / Y = △x
        // ∆x = (β/(1-β)) * x
        actualDelataY = int256(endingY) - int256(startingY);
        actualDeltaX = int256(endingX) - int256(startingX);
    }

    function deposit(uint256 wethAmount) public {
        uint256 minWeth = pool.getMinimumWethDepositAmount();
        // uint256.max + 1 -> overflow
        wethAmount = bound(wethAmount, minWeth, type(uint64).max);
        //         18446744073709551615
        // 115792089237316195423570985008687907853269984665640564039457584007913129639935

        startingY = int256(weth.balanceOf(address(pool)));
        startingX = int256(poolToken.balanceOf(address(pool)));

        expectedDeltaY = int256(wethAmount);
        //    return (wethToDeposit * poolTokenReserves) / wethReserves;
        expectedDeltaX = int256(pool.getPoolTokensToDepositBasedOnWeth(uint256(wethAmount)));

        // deposit
        vm.startPrank(liquidityProvider);
        weth.mint(liquidityProvider, wethAmount);
        poolToken.mint(liquidityProvider, uint256(expectedDeltaX));

        weth.approve(address(pool), type(uint256).max);
        poolToken.approve(address(pool), type(uint256).max);

        pool.deposit(wethAmount, 0, uint256(expectedDeltaX), uint64(block.timestamp));
        vm.stopPrank();

        // actual
        uint256 endingY = weth.balanceOf(address(pool));
        uint256 endingX = poolToken.balanceOf(address(pool));

        // (△y * X) / Y = △x
        // ∆x = (β/(1-β)) * x
        actualDelataY = int256(endingY) - int256(startingY);
        actualDeltaX = int256(endingX) - int256(startingX);
    }
}
