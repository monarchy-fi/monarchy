// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Exile} from "../../src/Exile.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MonarchTiers} from "../../src/libraries/MonarchTiers.sol";

/// @notice Drives Exile with random locks, extensions, payouts, claims, withdrawals and time jumps.
contract ExileHandler is Test {
    Exile internal exile;
    MockERC20 internal stake;
    MockERC20 internal reward;
    uint256 internal poolId;
    address internal funder = makeAddr("funder");

    address[] public actors;
    uint256[] public lockIds;
    mapping(uint256 => uint16) public multiplierSeen;

    uint256 public ghostNotified;
    uint256 public ghostClaimed;
    uint256 public ghostLockedOutstanding;
    bool public multiplierDropped;

    constructor(Exile exile_, MockERC20 stake_, MockERC20 reward_, uint256 poolId_) {
        exile = exile_;
        stake = stake_;
        reward = reward_;
        poolId = poolId_;
        for (uint256 i; i < 4; ++i) {
            address a = makeAddr(string.concat("actor", vm.toString(i)));
            actors.push(a);
            stake.mint(a, 1e30);
            vm.prank(a);
            stake.approve(address(exile), type(uint256).max);
        }
        reward.mint(funder, 1e30);
        vm.prank(funder);
        reward.approve(address(exile), type(uint256).max);
    }

    function lock(uint256 actorSeed, uint256 amount, uint256 duration) external {
        address a = actors[actorSeed % actors.length];
        amount = bound(amount, 1, 1e24);
        duration = bound(duration, 1, 60 days);
        vm.prank(a);
        uint256 id = exile.lockERC20(address(stake), amount, uint64(block.timestamp + duration), poolId);
        lockIds.push(id);
        multiplierSeen[id] = exile.lockInfo(id).multiplierBps;
        ghostLockedOutstanding += amount;
    }

    function extend(uint256 lockSeed, uint256 extra) external {
        if (lockIds.length == 0) return;
        uint256 id = lockIds[lockSeed % lockIds.length];
        Exile.Lock memory l = exile.lockInfo(id);
        if (l.withdrawn) return;
        uint256 base = l.unlockAt > block.timestamp ? l.unlockAt : block.timestamp;
        uint64 newUnlock = uint64(base + bound(extra, 1 hours, 45 days));
        vm.prank(l.owner);
        exile.extend(id, newUnlock);
        uint16 m = exile.lockInfo(id).multiplierBps;
        if (m < multiplierSeen[id]) multiplierDropped = true;
        multiplierSeen[id] = m;
    }

    function notify(uint256 amount) external {
        amount = bound(amount, 1, 1e24);
        vm.prank(funder);
        exile.notifyReward(poolId, amount);
        ghostNotified += amount;
    }

    function claim(uint256 lockSeed) external {
        if (lockIds.length == 0) return;
        uint256 id = lockIds[lockSeed % lockIds.length];
        vm.prank(exile.lockInfo(id).owner);
        ghostClaimed += exile.claimRewards(id);
    }

    function withdraw(uint256 lockSeed) external {
        if (lockIds.length == 0) return;
        uint256 id = lockIds[lockSeed % lockIds.length];
        Exile.Lock memory l = exile.lockInfo(id);
        if (l.withdrawn || block.timestamp < l.unlockAt) return;
        uint256 before = reward.balanceOf(l.owner);
        vm.prank(l.owner);
        exile.withdraw(id);
        // withdraw settles but does not pay out rewards; they stay claimable
        assertEq(reward.balanceOf(l.owner), before, "withdraw moved rewards");
        ghostLockedOutstanding -= l.amount;
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, 3 days));
    }

    function poke(uint256 buckets) external {
        exile.poke(poolId, bound(buckets, 1, exile.MAX_BUCKETS_PER_CALL()));
    }

    function lockCount() external view returns (uint256) {
        return lockIds.length;
    }
}

contract ExileInvariantTest is Test {
    Exile internal exile;
    MockERC20 internal stake;
    MockERC20 internal reward;
    ExileHandler internal handler;

    function setUp() public {
        vm.warp(1_700_000_000 - (1_700_000_000 % 3600));
        exile = new Exile();
        stake = new MockERC20("Stake", "STK", 18);
        reward = new MockERC20("Reward", "RWD", 6);
        uint256 poolId = exile.createPool(address(stake), address(reward), MonarchTiers.defaults(), address(this));
        handler = new ExileHandler(exile, stake, reward, poolId);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 60
    /// forge-config: offline.invariant.runs = 64
    /// forge-config: offline.invariant.depth = 60
    function invariant_solvent() public view {
        uint256 owed;
        for (uint256 i; i < handler.lockCount(); ++i) {
            owed += exile.pendingRewards(handler.lockIds(i));
        }
        assertLe(owed, reward.balanceOf(address(exile)), "Exile owes more than it holds");
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 60
    /// forge-config: offline.invariant.runs = 64
    /// forge-config: offline.invariant.depth = 60
    function invariant_rewardsConserved() public view {
        assertEq(
            reward.balanceOf(address(exile)) + handler.ghostClaimed(), handler.ghostNotified(), "reward tokens leaked"
        );
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 60
    /// forge-config: offline.invariant.runs = 64
    /// forge-config: offline.invariant.depth = 60
    function invariant_principalHeld() public view {
        assertEq(stake.balanceOf(address(exile)), handler.ghostLockedOutstanding(), "locked tokens don't match");
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 60
    /// forge-config: offline.invariant.runs = 64
    /// forge-config: offline.invariant.depth = 60
    function invariant_multiplierNeverDrops() public view {
        assertFalse(handler.multiplierDropped(), "an extension lowered a multiplier");
    }
}
