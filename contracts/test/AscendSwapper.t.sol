// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MonarchyFixture} from "./utils/MonarchyFixture.sol";
import {AscendSwapper} from "../src/AscendSwapper.sol";
import {Lodestar} from "../src/Lodestar.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @dev Runs against the mock Infinity vault, which reverts unless every delta is settled.
/// Two concrete suites cover the quote sorting below and above the token.
abstract contract AscendSwapperTestBase is MonarchyFixture {
    MockERC20 internal token;
    bytes32 internal poolId;

    function _quoteAddress() internal pure virtual returns (address);
    function _expectTokenIs0() internal pure virtual returns (bool);

    function setUp() public {
        _deployCore(_quoteAddress());
        (token, poolId) = _launch("MONARCH");
    }

    function test_sorting() public view {
        assertEq(launchpad.poolTokenIs0(poolId), _expectTokenIs0());
    }

    function test_buyThenSell() public {
        uint256 out = _buy(poolId, trader, 1_000e6);
        // constant product with 1% fee
        uint256 inAfterFee = 1_000e6 * 99 / 100;
        assertEq(out, TOKEN_SEED * inAfterFee / (QUOTE_SEED + inAfterFee));
        assertEq(token.balanceOf(trader), out);
        assertEq(usdc.balanceOf(trader), 0);
        assertEq(usdc.balanceOf(address(swapper)), 0, "swapper holds nothing");

        uint256 back = _sell(poolId, token, trader, out);
        assertEq(usdc.balanceOf(trader), back);
        assertLt(back, 1_000e6, "round trip pays two fees");
        assertGt(back, 970e6);
        assertEq(token.balanceOf(address(swapper)), 0);
    }

    function test_minOutReverts() public {
        usdc.mint(trader, 1_000e6);
        vm.startPrank(trader);
        usdc.approve(address(swapper), 1_000e6);
        vm.expectRevert();
        swapper.buyExactIn(poolId, 1_000e6, type(uint256).max, trader);
        vm.stopPrank();
    }

    function test_onlyVaultCallsBack() public {
        vm.expectRevert(AscendSwapper.OnlyVault.selector);
        swapper.lockAcquired("");
    }

    function test_feesFlowToCreator() public {
        _buy(poolId, trader, 1_000e6);
        launchpad.collect(poolId);
        assertEq(launchpad.creatorOwedQuote(poolId), 1_000e6 / 100 / 2, "half of the 1% fee");
        uint256 before = usdc.balanceOf(dev);
        launchpad.claim(poolId);
        assertEq(usdc.balanceOf(dev) - before, 5e6);
    }

    /// @dev Spot pumped vs the EMA: the router's min-out (from the EMA) can't be met, so the
    /// buyback waits in reserve. When EMA and spot agree it goes through.
    function test_buybackGuardedByEma() public {
        Lodestar l = _activate(_params(token, 4_000, 4_000, 2_000, address(0), false));
        _buy(poolId, trader, 10_000e6);

        (uint160 sp,,,) = pool.getSlot0(poolId);
        // EMA says the token is half the spot price
        uint160 ema = _expectTokenIs0() ? uint160(uint256(sp) * 1e9 / 1414213562) : uint160(uint256(sp) * 1414213562 / 1e9);
        launchpad.setEma(poolId, ema);
        l.distribute();
        assertGt(l.buybackReserve(), 0, "skipped");
        assertEq(l.totalBuybackTokensBurned(), 0);

        launchpad.setEma(poolId, 0); // back to spot
        _buy(poolId, trader, 10_000e6);
        l.distribute(); // half size after the skip
        vm.warp(block.timestamp + 30 minutes); // buybacks are at least 30 minutes apart
        l.distribute(); // the rest
        assertEq(l.buybackReserve(), 0);
        assertGt(l.totalBuybackTokensBurned(), 0);
        assertEq(usdc.balanceOf(address(l)), 0);
    }

    function test_quoteMinOutTracksPrice() public {
        Lodestar l = _activate(_params(token, 4_000, 4_000, 2_000, address(0), false));
        // 1 USDC buys ~16,000 tokens at the seeded price; min-out takes 1% fee + 3% slippage off
        uint256 m = l.quoteMinOut(1e6, 300);
        uint256 expected = 16_000e18 * 96 / 100;
        assertApproxEqRel(m, expected, 1e12);
    }
}

contract AscendSwapperQuoteLowTest is AscendSwapperTestBase {
    function _quoteAddress() internal pure override returns (address) {
        return address(0x0000000000000000000000000000000000001000);
    }

    function _expectTokenIs0() internal pure override returns (bool) {
        return false;
    }
}

contract AscendSwapperQuoteHighTest is AscendSwapperTestBase {
    function _quoteAddress() internal pure override returns (address) {
        return address(0xFffffffFffFffFFFffFfFFFFFffFffFFFffF1000);
    }

    function _expectTokenIs0() internal pure override returns (bool) {
        return true;
    }
}
