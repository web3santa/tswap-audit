// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { PoolFactory } from "../../src/PoolFactory.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { ERC2Mock } from "../mocks/ERC20Mock.sol";
import { TSwapPool } from "../../src/TSwapPool.sol";
import { Handler } from "./Handler.t.sol";

contract Invariant is StdInvariant, Test {
    // these pools have 2 assets
    ERC2Mock poolToken;
    ERC2Mock weth;

    TSwapPool pool; // poolToken /Weth
    PoolFactory factory;
    Handler handler;

    int256 constant STARTING_X = 100e18; // starting ERC20 / poolToken
    int256 constant STARTING_Y = 50e18; // starting WETH

    function setUp() public {
        weth = new ERC2Mock();
        poolToken = new ERC2Mock();
        factory = new PoolFactory(address(weth));
        pool = TSwapPool(factory.createPool(address(poolToken)));

        // create those initial x & y balances;
        poolToken.mint(address(this), 100e18);
        weth.mint(address(this), 50e18);

        poolToken.approve(address(pool), type(uint256).max);
        weth.approve(address(pool), type(uint256).max);

        // deposit
        pool.deposit(uint256(STARTING_Y), uint256(STARTING_Y), uint256(STARTING_X), uint64(block.timestamp));

        handler = new Handler(pool);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = Handler.deposit.selector;
        selectors[1] = Handler.swapPollTokenForWethBasedOnOutputWeth.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        targetContract(address(handler));
    }

    function statefulFuzz_contantProdictFormulaStayStheSame() public view {
        // Final invariant equation without fees:
        // ∆x = (β/(1-β)) * x
        // ∆y = (α/(1+α)) * y

        // actual delta x =

        assert(handler.actualDeltaX() == handler.expectedDeltaX());
    }
}
