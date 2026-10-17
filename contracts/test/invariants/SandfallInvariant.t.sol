// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Sandfall} from "../../src/Sandfall.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Drives Sandfall with random fixed and rolling streams, top-ups, claims, cancels and time jumps.
contract SandfallHandler is Test {
    Sandfall internal sf;
    MockERC20 internal token;
    address public creator = makeAddr("creator");
    address public recipient = makeAddr("recipient");

    uint256[] public ids;
    mapping(uint256 => uint256) public lastVested;
    uint256 public ghostIn;
    uint256 public ghostOut;
    bool public vestingWentBackwards;

    constructor(Sandfall sf_, MockERC20 token_) {
        sf = sf_;
        token = token_;
        token.mint(creator, 1e36);
        vm.prank(creator);
        token.approve(address(sf), type(uint256).max);
        vm.prank(creator);
        ids.push(sf.createRolling(address(token), recipient, 30 days, creator, true));
    }

    function createFixed(uint128 amount, uint32 startIn, uint32 cliffAfter, uint32 length, uint32 step, bool cancellable)
        external
    {
        amount = uint128(bound(amount, 1, 1e27));
        uint64 start = uint64(block.timestamp + bound(startIn, 0, 10 days));
        uint64 cliff = start + uint64(bound(cliffAfter, 0, 30 days));
        uint64 end = cliff + uint64(bound(length, 1, 365 days));
        uint32 stepSeconds = step % 3 == 0 ? 0 : uint32(bound(step, 1 hours, 30 days));
        vm.prank(creator);
        ids.push(sf.createFixed(address(token), recipient, amount, start, cliff, end, stepSeconds, cancellable));
        ghostIn += amount;
    }

    function topUp(uint128 amount) external {
        Sandfall.Stream memory s = sf.stream(ids[0]);
        if (s.cancelled) return;
        amount = uint128(bound(amount, 1, 1e27));
        vm.prank(creator);
        sf.topUp(ids[0], amount);
        ghostIn += amount;
    }

    function claim(uint256 seed) external {
        uint256 id = ids[seed % ids.length];
        vm.prank(recipient);
        ghostOut += sf.claim(id);
    }

    function cancel(uint256 seed) external {
        uint256 id = ids[seed % ids.length];
        Sandfall.Stream memory s = sf.stream(id);
        if (!s.cancellable || s.cancelled) return;
        uint256 owedBefore = uint256(s.total) - s.claimed;
        uint256 balBefore = token.balanceOf(address(sf));
        vm.prank(creator);
        sf.cancel(id);
        // cancelling pays out exactly what the stream still held, split between recipient and creator
        assertEq(balBefore - token.balanceOf(address(sf)), owedBefore, "cancel paid the wrong total");
        ghostOut += owedBefore;
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, 20 days));
        for (uint256 i; i < ids.length; ++i) {
            uint256 v = sf.vestedAmount(ids[i]);
            if (v < lastVested[ids[i]] && !sf.stream(ids[i]).cancelled) vestingWentBackwards = true;
            lastVested[ids[i]] = v;
        }
    }

    function count() external view returns (uint256) {
        return ids.length;
    }
}

contract SandfallInvariantTest is Test {
    Sandfall internal sf;
    MockERC20 internal token;
    SandfallHandler internal handler;

    function setUp() public {
        vm.warp(1_700_000_000);
        sf = new Sandfall();
        token = new MockERC20("Vest", "VST", 18);
        handler = new SandfallHandler(sf, token);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 60
    /// forge-config: offline.invariant.runs = 64
    /// forge-config: offline.invariant.depth = 60
    function invariant_balanceCoversEveryStream() public view {
        uint256 owed;
        for (uint256 i; i < handler.count(); ++i) {
            Sandfall.Stream memory s = sf.stream(handler.ids(i));
            assertLe(s.claimed, sf.vestedAmount(handler.ids(i)), "claimed more than vested");
            assertLe(sf.vestedAmount(handler.ids(i)), s.total, "vested more than deposited");
            owed += uint256(s.total) - s.claimed;
        }
        assertEq(token.balanceOf(address(sf)), owed, "balance doesn't match what streams still owe");
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 60
    /// forge-config: offline.invariant.runs = 64
    /// forge-config: offline.invariant.depth = 60
    function invariant_conservation() public view {
        assertEq(token.balanceOf(address(sf)) + handler.ghostOut(), handler.ghostIn(), "tokens leaked");
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 60
    /// forge-config: offline.invariant.runs = 64
    /// forge-config: offline.invariant.depth = 60
    function invariant_vestingOnlyMovesForward() public view {
        assertFalse(handler.vestingWentBackwards(), "vested amount decreased");
    }
}
