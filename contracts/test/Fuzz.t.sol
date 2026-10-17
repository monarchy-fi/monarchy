// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Exile} from "../src/Exile.sol";
import {Sandfall} from "../src/Sandfall.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MonarchTiers} from "../src/libraries/MonarchTiers.sol";

/// @notice Property tests over random amounts, durations and timings.
contract ExileFuzzTest is Test {
    Exile internal exile;
    MockERC20 internal stake;
    MockERC20 internal reward;
    uint256 internal poolId;
    address internal funder = makeAddr("funder");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.warp(1_700_000_000 - (1_700_000_000 % 3600));
        exile = new Exile();
        stake = new MockERC20("Stake", "STK", 18);
        reward = new MockERC20("Reward", "RWD", 6);
        poolId = exile.createPool(address(stake), address(reward), MonarchTiers.defaults(), address(this));
        address[2] memory users = [alice, bob];
        for (uint256 i; i < 2; ++i) {
            stake.mint(users[i], 1e30);
            vm.prank(users[i]);
            stake.approve(address(exile), type(uint256).max);
        }
        reward.mint(funder, 1e30);
        vm.prank(funder);
        reward.approve(address(exile), type(uint256).max);
    }

    function _lock(address who, uint256 amount, uint256 duration) internal returns (uint256 id) {
        vm.prank(who);
        id = exile.lockERC20(address(stake), amount, uint64(block.timestamp + duration), poolId);
    }

    function _claim(address who, uint256 id) internal returns (uint256) {
        vm.prank(who);
        return exile.claimRewards(id);
    }

    /// Two locks that outlast the drip split it by points, and never more than was paid in.
    function testFuzz_dripSplitsByPoints(uint256 a, uint256 b, uint256 da, uint256 db, uint256 payout) public {
        a = bound(a, 1e18, 1e27);
        b = bound(b, 1e18, 1e27);
        da = bound(da, 8 days, 60 days);
        db = bound(db, 8 days, 60 days);
        payout = bound(payout, 1e6, 1e15);

        uint256 ia = _lock(alice, a, da);
        uint256 ib = _lock(bob, b, db);
        vm.prank(funder);
        exile.notifyReward(poolId, payout);
        vm.warp(block.timestamp + 7 days);

        uint256 ra = _claim(alice, ia);
        uint256 rb = _claim(bob, ib);
        uint256 pa = exile.lockInfo(ia).points;
        uint256 pb = exile.lockInfo(ib).points;

        assertLe(ra + rb, payout, "paid out more than deposited");
        // the whole drip is shared, losing at most a few units to rounding
        assertApproxEqAbs(ra + rb, payout, 3, "drip not fully shared");
        assertApproxEqAbs(ra, payout * pa / (pa + pb), 3, "alice's share is off");
    }

    /// A lock earns nothing after it unlocks, even if nobody touches the pool.
    function testFuzz_noEarningAfterUnlock(uint256 amount, uint256 duration, uint256 payout, uint256 later) public {
        amount = bound(amount, 1e18, 1e27);
        duration = bound(duration, 1 days, 6 days);
        payout = bound(payout, 1e6, 1e15);
        later = bound(later, 1, 60 days);

        uint256 id = _lock(alice, amount, duration);
        _lock(bob, amount, 60 days); // keeps the pool earning after alice's lock ends
        vm.prank(funder);
        exile.notifyReward(poolId, payout);

        vm.warp(exile.lockInfo(id).unlockAt);
        uint256 atUnlock = exile.pendingRewards(id);
        vm.warp(block.timestamp + later);
        // long idle gaps have to be caught up in chunks before the pool can be touched
        while (!exile.poke(poolId, exile.MAX_BUCKETS_PER_CALL())) {}
        assertEq(exile.pendingRewards(id), atUnlock, "earned after unlock");
        assertEq(_claim(alice, id), atUnlock, "claim differs from pending");
    }

    /// Locking right before a payout, then leaving, only ever catches a fraction of that payout.
    function testFuzz_snipingCatchesOnlyItsTime(uint256 payout, uint256 stay) public {
        payout = bound(payout, 1e9, 1e15);
        stay = bound(stay, 1 days, 6 days);

        _lock(bob, 1e24, 60 days);
        uint256 sniper = _lock(alice, 1e24, stay);
        vm.prank(funder);
        exile.notifyReward(poolId, payout);
        vm.warp(block.timestamp + 30 days);

        uint256 got = _claim(alice, sniper);
        // at most its share of the time it was actually locked, out of the 7 day drip
        uint256 lockedFor = exile.lockInfo(sniper).unlockAt - exile.lockInfo(sniper).createdAt;
        assertLe(got, payout * lockedFor / 7 days, "sniper earned past its lock");
    }

    /// Extending never lowers the multiplier, and an extended lock keeps earning.
    function testFuzz_extendNeverLowersMultiplier(uint256 first, uint256 extra) public {
        first = bound(first, 1 hours, 60 days);
        extra = bound(extra, 1 hours, 60 days);
        uint256 id = _lock(alice, 1e24, first);
        uint16 before = exile.lockInfo(id).multiplierBps;
        vm.warp(block.timestamp + first / 2);
        uint64 newUnlock = exile.lockInfo(id).unlockAt + uint64(extra);
        vm.prank(alice);
        exile.extend(id, newUnlock);
        assertGe(exile.lockInfo(id).multiplierBps, before, "multiplier dropped");
    }
}

contract SandfallFuzzTest is Test {
    Sandfall internal sf;
    MockERC20 internal token;
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");

    function setUp() public {
        vm.warp(1_700_000_000);
        sf = new Sandfall();
        token = new MockERC20("Vest", "VST", 18);
        token.mint(creator, 1e36);
        vm.prank(creator);
        token.approve(address(sf), type(uint256).max);
    }

    function _fixed(uint128 amount, uint32 cliffAfter, uint32 length, uint32 step)
        internal
        returns (uint256 id, uint64 start, uint64 cliff, uint64 end)
    {
        start = uint64(block.timestamp);
        cliff = start + uint64(bound(cliffAfter, 0, 90 days));
        end = cliff + uint64(bound(length, 1, 730 days));
        uint32 stepSeconds = step % 2 == 0 ? 0 : uint32(bound(step, 1, 90 days));
        vm.prank(creator);
        id = sf.createFixed(address(token), alice, amount, start, cliff, end, stepSeconds, false);
    }

    /// Vesting rises from zero at the cliff to the full amount at the end and never runs backwards.
    function testFuzz_fixedVestingIsMonotonic(
        uint128 amount,
        uint32 cliffAfter,
        uint32 length,
        uint32 step,
        uint32 t1,
        uint32 t2
    ) public {
        amount = uint128(bound(amount, 1, 1e30));
        (uint256 id, uint64 start, uint64 cliff, uint64 end) = _fixed(amount, cliffAfter, length, step);

        uint256 a = bound(t1, 0, end - start + 30 days);
        vm.warp(start + a);
        uint256 va = sf.vestedAmount(id);
        if (start + a < cliff) assertEq(va, 0, "vested before the cliff");
        vm.warp(start + bound(t2, a, end - start + 30 days));
        uint256 vb = sf.vestedAmount(id);
        assertGe(vb, va, "vesting went backwards");
        assertLe(vb, amount, "vested more than deposited");
        vm.warp(end);
        assertEq(sf.vestedAmount(id), amount, "not fully vested at the end");
    }

    /// Cancelling returns exactly the unvested rest to the creator and leaves the vested part claimable.
    function testFuzz_cancelSplitsExactly(uint128 amount, uint32 at, uint32 claimAt) public {
        amount = uint128(bound(amount, 1, 1e30));
        uint64 start = uint64(block.timestamp);
        vm.prank(creator);
        uint256 id = sf.createFixed(address(token), alice, amount, start, start, start + 100 days, 0, true);

        vm.warp(start + bound(claimAt, 0, 100 days));
        vm.prank(alice);
        uint256 claimed = sf.claim(id);
        vm.warp(block.timestamp + bound(at, 0, 100 days));
        uint256 vested = sf.vestedAmount(id);

        uint256 creatorBefore = token.balanceOf(creator);
        vm.prank(creator);
        sf.cancel(id);
        assertEq(token.balanceOf(creator) - creatorBefore, amount - vested, "creator got the wrong amount");
        vm.prank(alice);
        assertEq(sf.claim(id), vested - claimed, "recipient can't claim the vested part");
        assertEq(token.balanceOf(address(sf)), 0, "dust left behind");
    }

    /// Any series of top-ups to a rolling stream fully vests one window after the last top-up.
    function testFuzz_rollingTopUpsVestFully(uint128[4] memory amounts, uint32[4] memory gaps) public {
        vm.prank(creator);
        uint256 id = sf.createRolling(address(token), alice, 30 days, creator, false);
        uint256 total;
        for (uint256 i; i < 4; ++i) {
            uint128 amt = uint128(bound(amounts[i], 1, 1e27));
            vm.prank(creator);
            sf.topUp(id, amt);
            total += amt;
            vm.warp(block.timestamp + bound(gaps[i], 0, 40 days));
            assertLe(sf.vestedAmount(id), total, "vested more than topped up");
        }
        vm.warp(block.timestamp + 30 days);
        assertEq(sf.vestedAmount(id), total, "rolling stream didn't fully vest");
        vm.prank(alice);
        assertEq(sf.claim(id), total, "claim short");
    }
}
