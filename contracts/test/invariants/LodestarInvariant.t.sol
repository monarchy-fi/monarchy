// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MonarchyFixture} from "../utils/MonarchyFixture.sol";
import {Lodestar} from "../../src/Lodestar.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockSwapper} from "../../src/mocks/MockSwapper.sol";
import {MockAscendLaunchpad} from "../../src/mocks/MockAscendLaunchpad.sol";

/// @notice Drives a live Lodestar with random fees, direct donations, failing buybacks and distributes.
contract LodestarHandler is Test {
    Lodestar internal l;
    MockAscendLaunchpad internal launchpad;
    MockSwapper internal swapper;
    MockERC20 internal token;
    MockERC20 internal usdc;
    bytes32 internal poolId;

    uint256 public distributes;
    bool public leftoverAfterDistribute;
    bool public tokenLeftAfterDistribute;

    constructor(
        Lodestar l_,
        MockAscendLaunchpad launchpad_,
        MockSwapper swapper_,
        MockERC20 token_,
        MockERC20 usdc_,
        bytes32 poolId_
    ) {
        l = l_;
        launchpad = launchpad_;
        swapper = swapper_;
        token = token_;
        usdc = usdc_;
        poolId = poolId_;
    }

    function fees(uint256 tokenFees, uint256 quoteFees) external {
        launchpad.injectFees(poolId, bound(tokenFees, 0, 1e27), bound(quoteFees, 0, 1e15));
    }

    function donate(uint256 quoteAmt) external {
        usdc.mint(address(l), bound(quoteAmt, 1, 1e13));
    }

    function setSwapFails(bool fail) external {
        swapper.setFail(fail);
    }

    function distribute() external {
        l.distribute();
        ++distributes;
        if (usdc.balanceOf(address(l)) != l.buybackReserve() + l.holdersReserve() + l.treasuryReserve()) {
            leftoverAfterDistribute = true;
        }
        if (token.balanceOf(address(l)) != 0) tokenLeftAfterDistribute = true;
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, 2 days));
    }
}

contract LodestarInvariantTest is MonarchyFixture {
    MockERC20 internal token;
    bytes32 internal poolId;
    MockSwapper internal mockSwapper;
    Lodestar internal l;
    LodestarHandler internal handler;

    uint256 internal constant TOKENS_PER_QUOTE = 16_000e18 * 1e12;

    function setUp() public {
        _deployCore(address(0));
        (token, poolId) = _launch("DEMO");
        mockSwapper = new MockSwapper(usdc, token, TOKENS_PER_QUOTE);
        l = _activate(_params(token, 4_000, 4_000, 2_000, address(mockSwapper), false));
        handler = new LodestarHandler(l, launchpad, mockSwapper, token, usdc, poolId);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 40
    /// forge-config: offline.invariant.runs = 64
    /// forge-config: offline.invariant.depth = 40
    function invariant_everyQuoteUnitAccountedFor() public view {
        assertEq(usdc.balanceOf(address(mockSwapper)), l.totalBuybackQuote(), "buyback total off");
        assertEq(usdc.balanceOf(address(exile)), l.totalHoldersQuote(), "holder total off");
        assertEq(usdc.balanceOf(address(sandfall)), l.totalTreasuryQuote(), "treasury total off");
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 40
    /// forge-config: offline.invariant.runs = 64
    /// forge-config: offline.invariant.depth = 40
    function invariant_distributeLeavesOnlyTheReserve() public view {
        assertFalse(handler.leftoverAfterDistribute(), "quote left behind besides the reserve");
        assertFalse(handler.tokenLeftAfterDistribute(), "token fees left unburned");
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 40
    /// forge-config: offline.invariant.runs = 64
    /// forge-config: offline.invariant.depth = 40
    function invariant_burnsReachTheDeadAddress() public view {
        assertEq(
            token.balanceOf(DEAD), l.totalTokenBurned() + l.totalBuybackTokensBurned(), "burn totals don't match DEAD"
        );
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 40
    /// forge-config: offline.invariant.runs = 64
    /// forge-config: offline.invariant.depth = 40
    function invariant_holdersGetTwiceTheTreasury() public view {
        // 40% holders, 20% treasury; rounding remainders go to the treasury
        uint256 h = l.totalHoldersQuote();
        uint256 t = l.totalTreasuryQuote();
        assertLe(h, 2 * t, "holders over-paid");
        assertLe(2 * t, h + 5 * handler.distributes(), "treasury over-paid beyond rounding");
    }
}
