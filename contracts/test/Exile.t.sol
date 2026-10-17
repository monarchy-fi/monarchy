// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Exile} from "../src/Exile.sol";
import {IExile} from "../src/interfaces/IExile.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721, MockERC1155} from "../src/mocks/MockNFTs.sol";
import {MonarchTiers} from "../src/libraries/MonarchTiers.sol";

contract ExileTest is Test {
    Exile internal exile;
    MockERC20 internal monarch;
    MockERC20 internal reward;
    uint256 internal poolId;

    address internal admin = makeAddr("admin");
    address internal funder = makeAddr("funder");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant T0 = 1_700_000_000 - (1_700_000_000 % 3600); // hour aligned

    function setUp() public {
        vm.warp(T0);
        exile = new Exile();
        monarch = new MockERC20("Monarch", "MONARCH", 18);
        reward = new MockERC20("Reward", "RWD", 18);
        poolId = exile.createPool(address(monarch), address(reward), MonarchTiers.defaults(), admin);

        address[3] memory users = [alice, bob, carol];
        for (uint256 i; i < users.length; ++i) {
            monarch.mint(users[i], 1_000_000e18);
            vm.prank(users[i]);
            monarch.approve(address(exile), type(uint256).max);
        }
        reward.mint(funder, 1_000_000_000e18);
        vm.prank(funder);
        reward.approve(address(exile), type(uint256).max);
    }

    // ---------------------------------------------------------------- helpers

    function _lock(address who, uint256 amount, uint256 duration) internal returns (uint256 id) {
        vm.prank(who);
        id = exile.lockERC20(address(monarch), amount, uint64(block.timestamp + duration), poolId);
    }

    function _notify(uint256 amount) internal {
        vm.prank(funder);
        exile.notifyReward(poolId, amount);
    }

    function _claim(address who, uint256 id) internal returns (uint256) {
        vm.prank(who);
        return exile.claimRewards(id);
    }

    function _skip(uint256 secs) internal {
        vm.warp(block.timestamp + secs);
    }

    // ---------------------------------------------------------------- tiers

    function test_tierSelection() public {
        uint256 a = _lock(alice, 1000e18, 23 hours);
        assertEq(exile.lockInfo(a).points, 0, "below first tier earns nothing");
        assertEq(exile.lockInfo(_lock(alice, 1000e18, 1 days)).multiplierBps, 5000, "Peasant");
        assertEq(exile.lockInfo(_lock(alice, 1000e18, 3 days)).multiplierBps, 10000, "Knight");
        assertEq(exile.lockInfo(_lock(alice, 1000e18, 7 days)).multiplierBps, 15000, "Duke");
        assertEq(exile.lockInfo(_lock(alice, 1000e18, 30 days)).multiplierBps, 30000, "Monarch");
        assertEq(exile.lockInfo(_lock(alice, 1000e18, 31 days)).points, 3000e18, "Monarch points");
        (, bytes32 label) = exile.tierFor(poolId, 30 days);
        assertEq(label, bytes32("Monarch"));
    }

    function test_unlockRoundsUpToHour() public {
        _skip(10 minutes);
        uint256 id = _lock(alice, 1e18, 1 days);
        assertEq(exile.lockInfo(id).unlockAt, T0 + 1 days + 1 hours);
    }

    // ---------------------------------------------------------------- drip

    function test_dripOverThreeDays() public {
        uint256 id = _lock(alice, 1000e18, 30 days);
        _notify(3000e18);
        _skip(1 days);
        assertApproxEqRel(exile.pendingRewards(id), 1000e18, 1e12);
        _skip(2 days);
        assertApproxEqRel(exile.pendingRewards(id), 3000e18, 1e12);
        _skip(1 days);
        assertApproxEqRel(exile.pendingRewards(id), 3000e18, 1e12);
        uint256 got = _claim(alice, id);
        assertApproxEqRel(got, 3000e18, 1e12);
        assertLe(got, 3000e18);
        assertEq(reward.balanceOf(alice), got);
    }

    function test_proportionalByPoints() public {
        uint256 a = _lock(alice, 1000e18, 30 days); // 3000 points
        uint256 b = _lock(bob, 1000e18, 7 days); // 1500 points
        _notify(6000e18);
        _skip(2 days);
        uint256 pa = exile.pendingRewards(a);
        uint256 pb = exile.pendingRewards(b);
        assertApproxEqRel(pa, 2 * pb, 1e12);
        assertApproxEqRel(pa + pb, uint256(6000e18) * 2 / 3, 1e12);
    }

    function test_topUpMidDripRestreamsLeftover() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        _notify(3000e18);
        _skip(1.5 days);
        _notify(1500e18); // leftover 1500 over its 1.5 days + 1500 new over 3: ends 2.25 days out
        assertApproxEqAbs(exile.poolInfo(poolId).periodFinish, block.timestamp + 2.25 days, 1);
        _skip(3 days);
        assertApproxEqRel(exile.pendingRewards(a), 4500e18, 1e12);
    }

    // ---------------------------------------------------------------- expiry

    function test_expiryStopsEarningWithoutAnyoneTouching() public {
        uint256 a = _lock(alice, 1000e18, 30 days); // 3000 points
        uint256 b = _lock(bob, 6000e18, 1 days); // Peasant, 3000 points
        _notify(3000e18);
        _skip(1 days);
        assertApproxEqRel(exile.pendingRewards(b), 500e18, 1e12);
        _skip(3 days); // nobody pokes, withdraws or claims
        assertApproxEqRel(exile.pendingRewards(b), 500e18, 1e12, "Bob stopped at unlock");
        assertApproxEqRel(exile.pendingRewards(a), 2500e18, 1e12, "Alice got the rest");

        uint256 shown = exile.pendingRewards(b);
        vm.prank(bob);
        exile.withdraw(b);
        assertEq(_claim(bob, b), shown, "claim equals what the view showed");
        assertEq(_claim(alice, a), exile.pendingRewards(a) + reward.balanceOf(alice));
    }

    function test_longIdlePoolNeedsPoke() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        uint256 b = _lock(bob, 6000e18, 1 days);
        _notify(7000e18);
        _skip(40 days); // 960 hour boundaries
        uint256 viewA = exile.pendingRewards(a);
        uint256 viewB = exile.pendingRewards(b);
        vm.prank(alice);
        vm.expectRevert(Exile.PoolNeedsPoke.selector);
        exile.claimRewards(a);

        assertFalse(exile.poke(poolId, 500));
        assertTrue(exile.poke(poolId, 500));
        assertEq(_claim(alice, a), viewA);
        assertEq(_claim(bob, b), viewB);
        assertApproxEqRel(viewA + viewB, 7000e18, 1e12);
    }

    function test_withdrawRules() public {
        uint256 a = _lock(alice, 1000e18, 1 days);
        vm.startPrank(alice);
        vm.expectRevert(Exile.StillLocked.selector);
        exile.withdraw(a);
        vm.stopPrank();
        _skip(1 days);
        vm.prank(bob);
        vm.expectRevert(Exile.NotOwner.selector);
        exile.withdraw(a);
        uint256 before = monarch.balanceOf(alice);
        vm.startPrank(alice);
        exile.withdraw(a);
        assertEq(monarch.balanceOf(alice) - before, 1000e18);
        vm.expectRevert(Exile.AlreadyWithdrawn.selector);
        exile.withdraw(a);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- gaming

    function test_snipingADripCatchesOnlyASliver() public {
        _lock(alice, 1000e18, 30 days); // 3000 points, locked well before
        _skip(5 days);
        uint256 b = _lock(bob, 6000e18, 1 days); // 3000 points, one second before payout
        _skip(1);
        _notify(7000e18);
        _skip(1 days);
        vm.prank(bob);
        exile.withdraw(b);
        uint256 sniped = _claim(bob, b);
        // half the points for one day of a three day drip: a sixth, not half
        assertLt(sniped, 7000e18 * 17 / 100, "under 17% instead of 50%");
    }

    function test_splittingWalletsGivesNoEdge() public {
        uint256 single = _lock(alice, 1000e18, 30 days);
        uint256[] memory parts = new uint256[](10);
        for (uint256 i; i < 10; ++i) {
            parts[i] = _lock(bob, 100e18, 30 days);
        }
        _notify(7000e18);
        _skip(7 days);
        uint256 sum;
        for (uint256 i; i < 10; ++i) {
            sum += exile.pendingRewards(parts[i]);
        }
        assertApproxEqRel(sum, exile.pendingRewards(single), 1e12);
    }

    function test_chainingShortLocksEarnsLessThanMonarch() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        uint256 bobTotal;
        uint256 b = _lock(bob, 1000e18, 1 days);
        for (uint256 day; day < 30; ++day) {
            if (day % 7 == 0) _notify(7000e18);
            _skip(1 days);
            vm.prank(bob);
            exile.withdraw(b);
            bobTotal += _claim(bob, b);
            if (day < 29) b = _lock(bob, 1000e18, 1 days);
        }
        uint256 aliceTotal = _claim(alice, a);
        assertGt(aliceTotal, bobTotal * 5, "Monarch earns 6x a daily Peasant");
    }

    // ---------------------------------------------------------------- extend

    function test_extendUpgradesTierFromNow() public {
        uint256 b = _lock(bob, 1000e18, 7 days); // Duke 1.5x
        uint256 a = _lock(alice, 1000e18, 30 days); // Monarch 3x
        _notify(7000e18);
        _skip(7 days - 1 hours);
        uint256 beforeExtend = exile.pendingRewards(b);
        vm.prank(bob);
        exile.extend(b, uint64(block.timestamp + 30 days));
        Exile.Lock memory l = exile.lockInfo(b);
        assertEq(l.multiplierBps, 30000);
        assertEq(l.points, 3000e18);
        assertApproxEqAbs(exile.pendingRewards(b), beforeExtend, 1, "earlier rewards kept");
        _notify(7000e18);
        _skip(7 days);
        // after extension both earn equally on the new deposit
        uint256 gainA = exile.pendingRewards(a);
        uint256 gainB = exile.pendingRewards(b) - beforeExtend;
        assertGt(gainB, 3400e18);
        assertGt(gainA, gainB);
    }

    function test_extendCannotShortenOrBeDoneByOthers() public {
        uint256 a = _lock(alice, 1000e18, 7 days);
        uint64 unlockAt = exile.lockInfo(a).unlockAt;
        vm.prank(alice);
        vm.expectRevert(Exile.NotExtending.selector);
        exile.extend(a, unlockAt - 1 hours);
        vm.prank(alice);
        vm.expectRevert(Exile.NotExtending.selector);
        exile.extend(a, unlockAt);
        vm.prank(bob);
        vm.expectRevert(Exile.NotOwner.selector);
        exile.extend(a, unlockAt + 1 days);
    }

    function test_extendReTiersFromNow() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        _skip(28 days);
        vm.prank(alice);
        exile.extend(a, uint64(block.timestamp + 3 days)); // only 3 days still committed: Knight
        assertEq(exile.lockInfo(a).multiplierBps, 10000);
        vm.prank(alice);
        exile.extend(a, uint64(block.timestamp + 30 days)); // 30 days ahead again: Monarch
        assertEq(exile.lockInfo(a).multiplierBps, 30000);
    }

    function test_hourlyExtensionsCannotHoldMonarch() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        _skip(30 days - 1 hours);
        exile.poke(poolId, 744);
        vm.prank(alice);
        exile.extend(a, uint64(block.timestamp + 2 hours));
        assertEq(exile.lockInfo(a).points, 0, "two hours committed earns no tier");
    }

    function test_unlockNearMaxCannotWrapIntoThePast() public {
        vm.prank(alice);
        vm.expectRevert(Exile.InvalidUnlock.selector);
        exile.lockERC20(address(monarch), 1000e18, type(uint64).max, poolId);
    }

    function test_emptyPoolCarryIsNotSqueezedIntoTheLastSecond() public {
        _notify(3000e18); // drips with nobody locked, so it all goes to the carry
        _skip(3 days - 1);
        uint256 jit = _lock(bob, 1000e18, 1 days);
        _notify(1); // dust right before the drip ends
        _skip(1);
        // the carry re-drips over about 3 days, so the late locker gets a sliver, not all of it
        assertLt(exile.pendingRewards(jit), 10e18, "just-in-time lock scooped the carry");
    }

    function test_extendExpiredLockResumesWithoutBackpay() public {
        uint256 a = _lock(alice, 1000e18, 1 days); // 500 points
        uint256 c = _lock(carol, 1000e18, 30 days); // 3000 points, keeps the pool non-empty
        _notify(7000e18);
        _skip(2 days); // alice expired one day ago
        uint256 earned = exile.pendingRewards(a);
        vm.prank(alice);
        exile.extend(a, uint64(block.timestamp + 1 days));
        assertApproxEqAbs(exile.pendingRewards(a), earned, 1, "no earnings for the gap");
        _skip(1 days);
        assertGt(exile.pendingRewards(a), earned, "earning again after extension");
        c;
    }

    function test_tooShortLockCanExtendIntoRewards() public {
        uint256 a = _lock(alice, 1000e18, 12 hours);
        assertEq(exile.lockInfo(a).points, 0);
        vm.prank(alice);
        exile.extend(a, uint64(block.timestamp + 30 days));
        assertEq(exile.lockInfo(a).points, 3000e18);
        _notify(7000e18);
        _skip(7 days);
        assertApproxEqRel(exile.pendingRewards(a), 7000e18, 1e12);
    }

    // ---------------------------------------------------------------- empty pool

    function test_rewardsWhileEmptyRollIntoNextNotify() public {
        _notify(7000e18);
        _skip(7 days); // nobody locked: all 7000 unallocated
        uint256 a = _lock(alice, 1000e18, 30 days);
        _notify(1);
        _skip(7 days);
        assertApproxEqRel(exile.pendingRewards(a), 7000e18, 1e12);
    }

    // ---------------------------------------------------------------- tiers timelock

    function test_tierTimelock() public {
        IExile.Tier[] memory t = new IExile.Tier[](1);
        t[0] = IExile.Tier({minDuration: 1 days, multiplierBps: 50000, label: "Emperor"});

        vm.prank(bob);
        vm.expectRevert(Exile.NotAdmin.selector);
        exile.proposeTiers(poolId, t);

        uint256 old = _lock(alice, 1000e18, 30 days);
        vm.prank(admin);
        exile.proposeTiers(poolId, t);
        vm.expectRevert(Exile.TimelockActive.selector);
        exile.executeTiers(poolId);
        _skip(12 hours);
        exile.executeTiers(poolId);

        uint256 fresh = _lock(bob, 1000e18, 1 days);
        assertEq(exile.lockInfo(fresh).multiplierBps, 50000, "new locks use new tiers");
        assertEq(exile.lockInfo(old).multiplierBps, 30000, "old locks keep theirs");
    }

    function test_readyTiersExpire() public {
        vm.prank(admin);
        exile.proposeTiers(poolId, MonarchTiers.defaults());
        _skip(12 hours + 7 days + 1);
        vm.expectRevert(Exile.ProposalExpired.selector);
        exile.executeTiers(poolId);
    }

    function test_dustNotifyDoesNotDelayTheDrip() public {
        _lock(alice, 1000e18, 30 days);
        _notify(3000e18);
        uint64 finish = exile.poolInfo(poolId).periodFinish;
        _skip(1 days);
        _notify(1); // dust: joins the running drip
        uint64 finishAfterDust = exile.poolInfo(poolId).periodFinish;
        assertEq(finishAfterDust, finish, "dust pushed the drip back");
        _notify(2000e18); // a real payout moves the end out by its weight: 2k left over 2 days + 2k over 3
        uint64 finishAfterReal = exile.poolInfo(poolId).periodFinish;
        assertApproxEqAbs(finishAfterReal, block.timestamp + 2.5 days, 60);
    }

    function test_expiredLockIsReTieredOnExtend() public {
        uint256 id = _lock(alice, 1000e18, 30 days);
        assertEq(exile.lockInfo(id).multiplierBps, 30000);
        _skip(31 days);
        exile.poke(poolId, 744);
        vm.prank(alice);
        exile.extend(id, uint64(block.timestamp + 1 days));
        assertEq(exile.lockInfo(id).multiplierBps, 5000, "an hour-long re-lock doesn't keep Monarch");
    }

    function test_cancelTiers() public {
        IExile.Tier[] memory t = MonarchTiers.defaults();
        vm.startPrank(admin);
        exile.proposeTiers(poolId, t);
        exile.cancelTiers(poolId);
        vm.expectRevert(Exile.NoPendingTiers.selector);
        exile.executeTiers(poolId);
        vm.stopPrank();
    }

    function test_invalidTiers() public {
        IExile.Tier[] memory t = new IExile.Tier[](2);
        t[0] = IExile.Tier({minDuration: 3 days, multiplierBps: 10000, label: "A"});
        t[1] = IExile.Tier({minDuration: 1 days, multiplierBps: 5000, label: "B"});
        vm.expectRevert(Exile.InvalidTiers.selector);
        exile.createPool(address(monarch), address(reward), t, admin);
        vm.expectRevert(Exile.InvalidTiers.selector);
        exile.createPool(address(monarch), address(reward), new IExile.Tier[](0), admin);
        // a longer tier can't pay less than a shorter one
        t[0] = IExile.Tier({minDuration: 1 days, multiplierBps: 30000, label: "A"});
        t[1] = IExile.Tier({minDuration: 3 days, multiplierBps: 10000, label: "B"});
        vm.expectRevert(Exile.InvalidTiers.selector);
        exile.createPool(address(monarch), address(reward), t, admin);
        // a tier can't be shorter than a bucket or promise more than 5x, so an admin can't add a tier
        // that farms the drip with capital committed for seconds
        t[0] = IExile.Tier({minDuration: 1, multiplierBps: 5000, label: "A"});
        t[1] = IExile.Tier({minDuration: 3 days, multiplierBps: 10000, label: "B"});
        vm.expectRevert(Exile.InvalidTiers.selector);
        exile.createPool(address(monarch), address(reward), t, admin);
        t[0] = IExile.Tier({minDuration: 1 hours, multiplierBps: 5000, label: "A"});
        t[1] = IExile.Tier({minDuration: 3 days, multiplierBps: 50_001, label: "B"});
        vm.expectRevert(Exile.InvalidTiers.selector);
        exile.createPool(address(monarch), address(reward), t, admin);
        t[1].multiplierBps = 50_000;
        exile.createPool(address(monarch), address(reward), t, admin); // the bounds themselves are fine
    }

    function test_erc721CannotGoThroughTheTokenPath() public {
        MockERC721 nft = new MockERC721();
        nft.mint(alice, 7);
        vm.startPrank(alice);
        nft.setApprovalForAll(address(exile), true);
        vm.expectRevert(Exile.NotAnERC20.selector);
        exile.lockERC20(address(nft), 7, uint64(block.timestamp + 3 days), 0);
        vm.stopPrank();
        assertEq(nft.ownerOf(7), alice, "the NFT never left");
    }

    function test_claimRewardsToAnotherAddress() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        _notify(3000e18);
        _skip(3 days);
        vm.prank(bob);
        vm.expectRevert(Exile.NotOwner.selector);
        exile.claimRewardsTo(a, bob);
        vm.prank(alice);
        vm.expectRevert(Exile.ZeroAddress.selector);
        exile.claimRewardsTo(a, address(0));
        vm.prank(alice);
        uint256 got = exile.claimRewardsTo(a, carol);
        assertApproxEqAbs(got, 3000e18, 1e6);
        assertEq(reward.balanceOf(carol), got, "paid to the chosen address");
        assertEq(reward.balanceOf(alice), 0);
        assertEq(exile.pendingRewards(a), 0);
    }

    function test_emptyPoolCarryIsVisible() public {
        _notify(3000e18); // nobody locked
        _skip(1 days);
        assertApproxEqAbs(exile.poolInfo(poolId).carry, 1000e18, 1e6, "the carry shows as it accrues");
        _skip(2 days);
        assertApproxEqAbs(exile.poolInfo(poolId).carry, 3000e18, 1e6, "all of it once the drip is over");
        _lock(bob, 1000e18, 30 days);
        _notify(1);
        assertEq(exile.poolInfo(poolId).carry, 0, "the next payout picks it up and re-drips it");
        _skip(3 days);
        assertApproxEqAbs(exile.pendingRewards(1), 3000e18, 1e6);
    }

    // ---------------------------------------------------------------- misc

    function test_wrongStakeTokenReverts() public {
        MockERC20 other = new MockERC20("X", "X", 18);
        other.mint(alice, 1e18);
        vm.startPrank(alice);
        other.approve(address(exile), 1e18);
        vm.expectRevert(Exile.WrongStakeToken.selector);
        exile.lockERC20(address(other), 1e18, uint64(block.timestamp + 1 days), poolId);
        // plain lock without rewards works for any token
        exile.lockERC20(address(other), 1e18, uint64(block.timestamp + 1 days), 0);
        vm.stopPrank();
    }

    function test_plainLockHasNoRewards() public {
        vm.prank(alice);
        uint256 id = exile.lockERC20(address(monarch), 1000e18, uint64(block.timestamp + 30 days), 0);
        _notify(7000e18);
        _skip(7 days);
        assertEq(exile.pendingRewards(id), 0);
    }

    function test_earningRateMatchesAccrual() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        _lock(bob, 1000e18, 30 days);
        _notify(7000e18);
        uint256 rate = exile.earningRatePerSecond(a);
        uint256 p0 = exile.pendingRewards(a);
        _skip(1 hours);
        assertApproxEqRel(exile.pendingRewards(a) - p0, rate * 1 hours / 1e18, 1e12);
    }

    function test_sixDecimalRewardPrecision() public {
        MockERC20 usdc = new MockERC20("USDC", "USDC", 6);
        uint256 pid = exile.createPool(address(monarch), address(usdc), MonarchTiers.defaults(), admin);
        vm.prank(alice);
        uint256 a = exile.lockERC20(address(monarch), 400_000e18, uint64(block.timestamp + 30 days), pid);
        vm.prank(bob);
        uint256 b = exile.lockERC20(address(monarch), 600_000e18, uint64(block.timestamp + 30 days), pid);
        usdc.mint(funder, 1e6);
        vm.startPrank(funder);
        usdc.approve(address(exile), 1e6);
        exile.notifyReward(pid, 1e6); // 1 USDC
        vm.stopPrank();
        _skip(1 minutes);
        assertGt(exile.pendingRewards(a), 0, "per-second accrual is nonzero");
        _skip(7 days);
        uint256 total = exile.pendingRewards(a) + exile.pendingRewards(b);
        assertApproxEqAbs(total, 1e6, 2);
        assertLe(total, 1e6);
    }

    // ---------------------------------------------------------------- NFTs

    function test_erc721Lock() public {
        MockERC721 nft = new MockERC721();
        nft.mint(alice, 7);
        vm.startPrank(alice);
        nft.approve(address(exile), 7);
        uint256 id = exile.lockERC721(address(nft), 7, uint64(block.timestamp + 3 days));
        assertEq(nft.ownerOf(7), address(exile));
        assertEq(exile.lockInfo(id).points, 0);
        vm.expectRevert(Exile.StillLocked.selector);
        exile.withdraw(id);
        exile.extend(id, uint64(block.timestamp + 5 days));
        vm.warp(block.timestamp + 5 days);
        exile.withdraw(id);
        vm.stopPrank();
        assertEq(nft.ownerOf(7), alice);
    }

    function test_erc1155Lock() public {
        MockERC1155 items = new MockERC1155();
        items.mint(alice, 1, 50);
        vm.startPrank(alice);
        items.setApprovalForAll(address(exile), true);
        uint256 id = exile.lockERC1155(address(items), 1, 20, uint64(block.timestamp + 1 days));
        assertEq(items.balanceOf(address(exile), 1), 20);
        vm.warp(block.timestamp + 1 days);
        exile.withdraw(id);
        vm.stopPrank();
        assertEq(items.balanceOf(alice, 1), 50);
    }

    function test_unsolicitedNFTRejected() public {
        MockERC721 nft = new MockERC721();
        nft.mint(alice, 1);
        vm.prank(alice);
        vm.expectRevert(Exile.UnexpectedNFT.selector);
        nft.safeTransferFrom(alice, address(exile), 1);
    }

    // ---------------------------------------------------------------- stake-token rewards

    function _fundStake(uint256 amount) internal {
        monarch.mint(funder, amount);
        vm.startPrank(funder);
        monarch.approve(address(exile), type(uint256).max);
        exile.notifyStakeReward(poolId, amount);
        vm.stopPrank();
    }

    /// @dev Token-side fees paid in the stake token drip on the same points as the reward token, and one
    /// claim pays both.
    function test_stakeRewardsDripByPointsAndClaimPaysBoth() public {
        uint256 a = _lock(alice, 1000e18, 30 days); // Monarch, 3000 points
        uint256 b = _lock(bob, 1000e18, 3 days); // Knight, 1000 points
        _notify(400e18);
        _fundStake(800e18);
        _skip(1 days);
        // a third of each drip has gone out, split 3 : 1
        assertApproxEqRel(exile.pendingStakeRewards(a), 200e18, 1e12);
        assertApproxEqRel(exile.pendingStakeRewards(b), uint256(800e18) / 12, 1e12);
        assertApproxEqRel(exile.pendingRewards(a), 100e18, 1e12);

        uint256 monarchBefore = monarch.balanceOf(alice);
        uint256 rewardBefore = reward.balanceOf(alice);
        vm.expectEmit(true, true, false, false);
        emit Exile.StakeRewardsClaimed(a, alice, 0);
        _claim(alice, a);
        assertApproxEqRel(monarch.balanceOf(alice) - monarchBefore, 200e18, 1e12, "stake-token rewards paid");
        assertApproxEqRel(reward.balanceOf(alice) - rewardBefore, 100e18, 1e12, "reward token paid too");
        assertEq(exile.pendingStakeRewards(a), 0);
        assertApproxEqRel(exile.stakeEarningRatePerSecond(a) * 1 days / 1e18, 200e18, 1e9);
    }

    /// @dev A lock stops earning stake-token rewards at unlock, exactly like the reward token, and the
    /// principal is never used to pay them.
    function test_stakeRewardsStopAtUnlockAndLeavePrincipalAlone() public {
        uint256 a = _lock(alice, 1000e18, 1 days); // Peasant, 500 points, ends after one day
        uint256 b = _lock(bob, 500e18, 30 days); // Monarch, 1500 points
        _fundStake(3000e18);
        _skip(3 days);
        exile.poke(poolId, 1000);
        // day one splits 1000 by 500 : 1500, the other two days go to bob alone
        assertApproxEqRel(exile.pendingStakeRewards(a), 250e18, 1e12, "alice earns only while locked");
        assertApproxEqRel(exile.pendingStakeRewards(b), 2750e18, 1e12);

        vm.prank(alice);
        exile.withdraw(a);
        assertEq(exile.lockInfo(a).withdrawn, true);
        _claim(alice, a);
        _claim(bob, b);
        // what is left is bob's principal plus rounding dust, never less
        assertGe(monarch.balanceOf(address(exile)), 500e18);
        assertLt(monarch.balanceOf(address(exile)) - 500e18, 1e9);
    }

    /// @dev A lock made after a stake-token payout started only earns what drips from then on.
    function test_lateLockDoesNotTakeEarlierStakeRewards() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        _fundStake(3000e18);
        _skip(1 days);
        uint256 b = _lock(bob, 1000e18, 30 days);
        assertEq(exile.pendingStakeRewards(b), 0);
        _skip(2 days);
        assertApproxEqRel(exile.pendingStakeRewards(a), 1000e18 + 1000e18, 1e12);
        assertApproxEqRel(exile.pendingStakeRewards(b), 1000e18, 1e12);
    }

    /// @dev A lock that ended before any stake-token payout existed earns none of it, and the skipped
    /// bucket write doesn't hand it anything later.
    function test_lockThatEndedBeforeStakeRewardsGetsNone() public {
        uint256 a = _lock(alice, 1000e18, 1 days);
        uint256 b = _lock(bob, 1000e18, 30 days);
        _skip(2 days);
        _fundStake(3000e18);
        _skip(3 days);
        exile.poke(poolId, 1000);
        assertEq(exile.pendingStakeRewards(a), 0, "ended before the payout");
        assertApproxEqRel(exile.pendingStakeRewards(b), 3000e18, 1e12);
        _claim(alice, a);
        assertEq(monarch.balanceOf(alice), 1_000_000e18 - 1000e18, "nothing paid to alice");
    }

    /// @dev Stake-token rewards that drip while nobody is locked show as `stakeCarry` and re-drip with
    /// the next stake-token payout, like the reward-token carry.
    function test_stakeCarryIsVisibleAndRedrips() public {
        _fundStake(3000e18);
        _skip(1 days);
        Exile.PoolView memory v = exile.poolInfo(poolId);
        assertApproxEqAbs(v.stakeCarry, 1000e18, 1e6);
        assertEq(v.stakeTotalDistributed, 3000e18);
        assertEq(v.carry, 0, "the reward-token stream is separate");
        uint256 a = _lock(alice, 1000e18, 30 days);
        _fundStake(1);
        assertEq(exile.poolInfo(poolId).stakeCarry, 0);
        _skip(3 days);
        assertApproxEqRel(exile.pendingStakeRewards(a), 3000e18, 1e9, "all of it reaches the locker");
    }

    /// @dev claimRewardsTo sends both streams to the other address.
    function test_claimRewardsToPaysBothStreams() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        _notify(300e18);
        _fundStake(300e18);
        _skip(3 days);
        vm.prank(alice);
        exile.claimRewardsTo(a, carol);
        assertApproxEqRel(reward.balanceOf(carol), 300e18, 1e12);
        assertApproxEqRel(monarch.balanceOf(carol) - 1_000_000e18, 300e18, 1e12);
    }

    /// @dev The heaviest catch-up one call can do: a month of hourly buckets, the most it may snapshot with
    /// points expiring, and both streams dripping. It has to fit a 32M gas transaction with room to spare.
    function test_fullCatchUpWithBothStreamsFitsInABlock() public {
        for (uint256 i; i < exile.MAX_EXPIRING_PER_CALL(); ++i) {
            _lock(alice, 1e18, 1 days + i * 1 hours);
        }
        _notify(1000e18);
        _fundStake(1000e18);
        _skip(exile.MAX_BUCKETS_PER_CALL() * 1 hours);
        uint256 g = gasleft();
        assertTrue(exile.poke(poolId, exile.MAX_BUCKETS_PER_CALL()), "one call catches up");
        g -= gasleft();
        emit log_named_uint("full catch-up gas", g);
        assertLt(g, 20_000_000, "catch-up too heavy");
    }

    /// @dev With points expiring in more buckets than one call may snapshot, an action waits for a poke, and
    /// nothing is lost once the pool is caught up.
    function test_catchUpStopsAtTheSnapshotCap() public {
        uint256 n = exile.MAX_EXPIRING_PER_CALL() + 10;
        uint256[] memory ids = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            ids[i] = _lock(i % 2 == 0 ? alice : bob, 1e18, 1 days + i * 1 hours);
        }
        _notify(1000e18);
        _fundStake(1000e18);
        _skip(1 days + n * 1 hours);
        vm.prank(alice);
        vm.expectRevert(Exile.PoolNeedsPoke.selector);
        exile.claimRewards(ids[0]);
        assertFalse(exile.poke(poolId, exile.MAX_BUCKETS_PER_CALL()), "capped at the snapshot limit");
        // the claims below each catch up what is left
        uint256 paid;
        uint256 paidStake;
        for (uint256 i; i < n; ++i) {
            address who = i % 2 == 0 ? alice : bob;
            uint256 before = monarch.balanceOf(who);
            paid += _claim(who, ids[i]);
            paidStake += monarch.balanceOf(who) - before;
        }
        assertApproxEqAbs(paid, 1000e18, 1e9, "every reward paid out once caught up");
        assertApproxEqAbs(paidStake, 1000e18, 1e9, "every stake reward paid out once caught up");
    }

    /// @dev Dust locks expiring hour after hour can make users wait for a poke, but never block a payout.
    function test_dustLocksCannotBlockPayouts() public {
        uint256 n = exile.MAX_EXPIRING_PER_CALL() + 1;
        for (uint256 i; i < n; ++i) {
            _lock(bob, 2, 1 days + i * 1 hours);
        }
        _skip(1 days + n * 1 hours);
        _notify(100e18);
        _fundStake(100e18);
        assertTrue(exile.poke(poolId, 1), "the payouts caught the pool up");
    }

    /// @dev A reward token that can't be paid out right now doesn't hold the stake-token rewards hostage.
    function test_stakeRewardsClaimableWhileRewardTokenIsStuck() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        _notify(300e18);
        _fundStake(300e18);
        _skip(3 days);
        vm.mockCallRevert(address(reward), abi.encodeWithSelector(reward.transfer.selector), "paused");
        vm.prank(alice);
        vm.expectRevert();
        exile.claimRewards(a);
        uint256 before = monarch.balanceOf(carol);
        vm.prank(alice);
        uint256 got = exile.claimStakeRewardsTo(a, carol);
        assertApproxEqAbs(got, 300e18, 1e9, "stake rewards paid on their own");
        assertEq(monarch.balanceOf(carol) - before, got);
        vm.clearMockedCalls();
        assertApproxEqAbs(_claim(alice, a), 300e18, 1e9, "reward token still owed once it works again");
        assertEq(exile.pendingStakeRewards(a), 0, "stake rewards not paid twice");
    }

    function test_stakeRewardRejectsZero() public {
        vm.prank(funder);
        vm.expectRevert(Exile.InvalidAmount.selector);
        exile.notifyStakeReward(poolId, 0);
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_rewardsNeverExceedDeposits(uint256 seed) public {
        uint256[] memory ids = new uint256[](6);
        uint256 deposited;
        for (uint256 i; i < 6; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            address who = i % 2 == 0 ? alice : bob;
            uint256 duration = 1 days + seed % (40 days);
            ids[i] = _lock(who, 1e18 + seed % 10_000e18, duration);
            uint256 amt = 1e18 + (seed >> 64) % 5000e18;
            _notify(amt);
            deposited += amt;
            _skip((seed >> 128) % 10 days);
        }
        _skip(41 days);
        exile.poke(poolId, 10_000);
        uint256 owed;
        for (uint256 i; i < 6; ++i) {
            owed += exile.pendingRewards(ids[i]);
        }
        assertLe(owed, deposited);
        assertGe(reward.balanceOf(address(exile)), owed);
    }
}
