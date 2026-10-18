// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MonarchyFixture} from "./utils/MonarchyFixture.sol";
import {Lodestar} from "../src/Lodestar.sol";
import {LodestarFactory} from "../src/LodestarFactory.sol";
import {ILodestar} from "../src/interfaces/ILodestar.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @notice The demo, end to end on mock Ascend: launch, hand the creator role to Lodestar,
/// trade, distribute, lock in Exile, stream the treasury through Sandfall.
contract IntegrationTest is MonarchyFixture {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function test_fullDemoFlow() public {
        _deployCore(address(0));
        (MockERC20 monarch, bytes32 poolId) = _launch("MONARCH");

        // dev launched on Ascend and activates Lodestar: 40/40/20, listing on, role locked for good
        LodestarFactory.DeployParams memory p = _params(monarch, 4_000, 4_000, 2_000, address(0), true);
        Lodestar l = _activate(p);
        assertTrue(l.isCreator());

        // holders buy and lock: Alice for a month (Monarch 3x), Bob for a day (Peasant 0.5x)
        uint256 aliceTokens = _buy(poolId, alice, 2_000e6);
        uint256 bobTokens = _buy(poolId, bob, 2_000e6);
        uint256 exilePool = l.exilePoolId();
        vm.startPrank(alice);
        monarch.approve(address(exile), aliceTokens);
        uint256 aliceLock = exile.lockERC20(address(monarch), aliceTokens, uint64(block.timestamp + 30 days), exilePool);
        vm.stopPrank();
        vm.startPrank(bob);
        monarch.approve(address(exile), bobTokens);
        uint256 bobLock = exile.lockERC20(address(monarch), bobTokens, uint64(block.timestamp + 1 days), exilePool);
        vm.stopPrank();
        assertEq(exile.lockInfo(aliceLock).multiplierBps, 30_000);
        assertEq(exile.lockInfo(bobLock).multiplierBps, 5_000);

        // trading generates fees
        for (uint256 i; i < 5; ++i) {
            uint256 got = _buy(poolId, trader, 5_000e6);
            _sell(poolId, monarch, trader, got / 2);
        }
        uint256 supplyDeadBefore = monarch.balanceOf(DEAD);

        // anyone distributes
        vm.prank(trader);
        l.distribute();
        assertGt(monarch.balanceOf(DEAD), supplyDeadBefore, "token fees + buyback burned");
        assertGt(l.totalBuybackTokensBurned(), 0);
        assertGt(l.totalHoldersQuote(), 0);
        assertGt(l.totalTreasuryQuote(), 0);
        assertGt(launchpad.listingOwed(poolId), 0, "listing set-aside accrues for the router");
        assertEq(usdc.balanceOf(address(l)), 0);

        // rewards drip per second; Alice (3x) out-earns Bob (0.5x) 6:1 while both are locked
        vm.warp(block.timestamp + 12 hours);
        uint256 a = exile.pendingRewards(aliceLock);
        uint256 b = exile.pendingRewards(bobLock);
        assertGt(b, 0);
        assertApproxEqRel(a * bobTokens, b * aliceTokens * 6, 1e15);

        // Bob's lock ends after a day and stops earning; Alice keeps going
        vm.warp(block.timestamp + 2 days);
        uint256 bobFinal = exile.pendingRewards(bobLock);
        vm.warp(block.timestamp + 1 days);
        assertEq(exile.pendingRewards(bobLock), bobFinal);
        assertGt(exile.pendingRewards(aliceLock), a);
        vm.prank(bob);
        exile.withdraw(bobLock);
        vm.prank(bob);
        assertEq(exile.claimRewards(bobLock), bobFinal);
        assertEq(monarch.balanceOf(bob), bobTokens);

        // Team Treasury streams out through Sandfall
        uint256 sid = l.treasuryStreamId();
        uint256 claimable = sandfall.claimable(sid);
        assertGt(claimable, 0);
        vm.prank(treasury);
        sandfall.claim(sid);
        assertEq(usdc.balanceOf(treasury), claimable);

        // split change waits 12 hours
        vm.prank(dev);
        l.proposeConfig(ILodestar.Config(2_000, 6_000, 2_000, address(swapper), 300, false));
        vm.expectRevert(Lodestar.TimelockActive.selector);
        l.executeConfig();
        vm.warp(block.timestamp + 12 hours);
        l.executeConfig();
        assertEq(l.config().holdersBps, 6_000);

        // and the creator role can't be pulled while locked
        vm.prank(dev);
        vm.expectRevert(Lodestar.CreatorRoleIsLocked.selector);
        l.transferCreatorOut(dev);
    }
}
