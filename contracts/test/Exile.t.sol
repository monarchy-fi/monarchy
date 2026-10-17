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

    function test_dripOverSevenDays() public {
        uint256 id = _lock(alice, 1000e18, 30 days);
        _notify(7000e18);
        _skip(1 days);
        assertApproxEqRel(exile.pendingRewards(id), 1000e18, 1e12);
        _skip(6 days);
        assertApproxEqRel(exile.pendingRewards(id), 7000e18, 1e12);
        _skip(1 days);
        assertApproxEqRel(exile.pendingRewards(id), 7000e18, 1e12);
        uint256 got = _claim(alice, id);
        assertApproxEqRel(got, 7000e18, 1e12);
        assertLe(got, 7000e18);
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
        assertApproxEqRel(pa + pb, uint256(6000e18) * 2 / 7, 1e12);
    }

    function test_topUpMidDripRestreamsLeftover() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        _notify(7000e18);
        _skip(3.5 days);
        _notify(3500e18); // leftover 3500 + 3500 new over a fresh 7 days
        _skip(7 days);
        assertApproxEqRel(exile.pendingRewards(a), 10_500e18, 1e12);
    }

    // ---------------------------------------------------------------- expiry

    function test_expiryStopsEarningWithoutAnyoneTouching() public {
        uint256 a = _lock(alice, 1000e18, 30 days); // 3000 points
        uint256 b = _lock(bob, 6000e18, 1 days); // Peasant, 3000 points
        _notify(7000e18);
        _skip(1 days);
        assertApproxEqRel(exile.pendingRewards(b), 500e18, 1e12);
        _skip(7 days); // nobody pokes, withdraws or claims
        assertApproxEqRel(exile.pendingRewards(b), 500e18, 1e12, "Bob stopped at unlock");
        assertApproxEqRel(exile.pendingRewards(a), 6500e18, 1e12, "Alice got the rest");

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
        assertLt(sniped, 7000e18 * 15 / 100, "under 15% instead of 50%");
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

    function test_extendNeverLowersMultiplier() public {
        uint256 a = _lock(alice, 1000e18, 30 days);
        _skip(28 days);
        vm.prank(alice);
        exile.extend(a, uint64(block.timestamp + 3 days)); // 3 days left would be Knight, keeps Monarch
        assertEq(exile.lockInfo(a).multiplierBps, 30000);
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
        _skip(72 hours);
        exile.executeTiers(poolId);

        uint256 fresh = _lock(bob, 1000e18, 1 days);
        assertEq(exile.lockInfo(fresh).multiplierBps, 50000, "new locks use new tiers");
        assertEq(exile.lockInfo(old).multiplierBps, 30000, "old locks keep theirs");
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
