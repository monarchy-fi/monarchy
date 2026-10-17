// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Sandfall} from "../src/Sandfall.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract RejectingRecipient {
    Sandfall internal sf;

    constructor(Sandfall sf_) {
        sf = sf_;
    }

    function claimFrom(uint256 id) external {
        sf.claim(id);
    }

    receive() external payable {
        sf.claim(1); // re-enter
    }
}

contract SandfallTest is Test {
    Sandfall internal sf;
    MockERC20 internal usdc;
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    uint64 internal t0;

    function setUp() public {
        vm.warp(1_700_000_000);
        t0 = uint64(block.timestamp);
        sf = new Sandfall();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdc.mint(creator, 1_000_000e6);
        vm.prank(creator);
        usdc.approve(address(sf), type(uint256).max);
        vm.deal(creator, 100 ether);
    }

    function _linear(bool cancellable) internal returns (uint256 id) {
        vm.prank(creator);
        id = sf.createFixed(address(usdc), alice, 1000e6, t0, t0 + 10 days, t0 + 100 days, 0, cancellable);
    }

    function test_linearVesting() public {
        uint256 id = _linear(false);
        assertEq(sf.vestedAmount(id), 0);
        vm.warp(t0 + 10 days - 1);
        assertEq(sf.vestedAmount(id), 0, "nothing before cliff");
        vm.warp(t0 + 10 days);
        assertEq(sf.vestedAmount(id), 100e6, "cliff releases accrued amount");
        vm.warp(t0 + 50 days);
        assertEq(sf.vestedAmount(id), 500e6);
        vm.warp(t0 + 200 days);
        assertEq(sf.vestedAmount(id), 1000e6);
    }

    function test_claimPaysVested() public {
        uint256 id = _linear(false);
        vm.warp(t0 + 50 days);
        vm.prank(alice);
        assertEq(sf.claim(id), 500e6);
        assertEq(usdc.balanceOf(alice), 500e6);
        vm.prank(alice);
        assertEq(sf.claim(id), 0);
        vm.warp(t0 + 100 days);
        vm.prank(alice);
        sf.claim(id);
        assertEq(usdc.balanceOf(alice), 1000e6);
    }

    function test_claimByNonRecipientReverts() public {
        uint256 id = _linear(false);
        vm.warp(t0 + 50 days);
        vm.expectRevert(Sandfall.NotRecipient.selector);
        sf.claim(id);
    }

    function test_steps() public {
        vm.prank(creator);
        uint256 id = sf.createFixed(address(usdc), alice, 900e6, t0, t0, t0 + 90 days, 30 days, false);
        vm.warp(t0 + 29 days);
        assertEq(sf.vestedAmount(id), 0);
        vm.warp(t0 + 30 days);
        assertEq(sf.vestedAmount(id), 300e6);
        vm.warp(t0 + 89 days);
        assertEq(sf.vestedAmount(id), 600e6);
        vm.warp(t0 + 90 days);
        assertEq(sf.vestedAmount(id), 900e6);
    }

    function test_stepsUnevenNeverExceedTotal() public {
        vm.prank(creator);
        uint256 id = sf.createFixed(address(usdc), alice, 1000e6, t0, t0, t0 + 75 days, 30 days, false);
        vm.warp(t0 + 60 days);
        assertEq(sf.vestedAmount(id), uint256(1000e6) * 2 / 3);
        vm.warp(t0 + 74 days);
        assertLe(sf.vestedAmount(id), 1000e6);
        vm.warp(t0 + 75 days);
        assertEq(sf.vestedAmount(id), 1000e6);
    }

    function test_cancelCancellable() public {
        uint256 id = _linear(true);
        vm.warp(t0 + 50 days);
        uint256 creatorBefore = usdc.balanceOf(creator);
        vm.prank(creator);
        sf.cancel(id);
        assertEq(usdc.balanceOf(creator) - creatorBefore, 500e6, "rest back to creator");
        assertEq(sf.claimable(id), 500e6, "vested stays claimable");
        vm.warp(t0 + 100 days);
        vm.prank(alice);
        assertEq(sf.claim(id), 500e6, "vested goes to recipient");
        vm.prank(alice);
        assertEq(sf.claim(id), 0, "frozen after cancel");
        vm.prank(creator);
        vm.expectRevert(Sandfall.AlreadyCancelled.selector);
        sf.cancel(id);
    }

    function test_cancelNonCancellableReverts() public {
        uint256 id = _linear(false);
        vm.prank(creator);
        vm.expectRevert(Sandfall.NotCancellable.selector);
        sf.cancel(id);
    }

    function test_cancelByNonCreatorReverts() public {
        uint256 id = _linear(true);
        vm.prank(alice);
        vm.expectRevert(Sandfall.NotCreator.selector);
        sf.cancel(id);
    }

    function test_invalidSchedules() public {
        vm.startPrank(creator);
        vm.expectRevert(Sandfall.InvalidSchedule.selector);
        sf.createFixed(address(usdc), alice, 1, t0, t0, t0, 0, false);
        vm.expectRevert(Sandfall.InvalidSchedule.selector);
        sf.createFixed(address(usdc), alice, 1, t0 + 1, t0, t0 + 10, 0, false);
        vm.expectRevert(Sandfall.InvalidAmount.selector);
        sf.createFixed(address(usdc), alice, 0, t0, t0, t0 + 10, 0, false);
        vm.expectRevert(Sandfall.InvalidRecipient.selector);
        sf.createFixed(address(usdc), address(0), 1, t0, t0, t0 + 10, 0, false);
        vm.stopPrank();
    }

    function test_nativeStream() public {
        vm.prank(creator);
        uint256 id = sf.createFixed{value: 10 ether}(address(0), alice, 10 ether, t0, t0, t0 + 10 days, 0, true);
        vm.warp(t0 + 5 days);
        vm.prank(alice);
        sf.claim(id);
        assertEq(alice.balance, 5 ether);
        uint256 before = creator.balance;
        vm.prank(creator);
        sf.cancel(id);
        assertEq(creator.balance - before, 5 ether);
    }

    function test_nativeWrongValueReverts() public {
        vm.prank(creator);
        vm.expectRevert(Sandfall.WrongValue.selector);
        sf.createFixed{value: 1 ether}(address(0), alice, 2 ether, t0, t0, t0 + 10 days, 0, true);
    }

    function test_rolling() public {
        uint256 id = sf.createRolling(address(usdc), alice, 7 days, creator, false);
        assertEq(sf.vestedAmount(id), 0);
        vm.prank(creator);
        sf.topUp(id, 700e6);
        vm.warp(block.timestamp + 3.5 days);
        assertApproxEqAbs(sf.vestedAmount(id), 350e6, 1);
        // second top-up: 350 left with 3.5 days to go plus 350 new over 7 days ends after 5.25 days
        vm.prank(creator);
        sf.topUp(id, 350e6);
        assertApproxEqAbs(sf.vestedAmount(id), 350e6, 1);
        assertApproxEqAbs(sf.stream(id).periodFinish, block.timestamp + 5.25 days, 1);
        vm.warp(sf.stream(id).periodFinish);
        assertEq(sf.vestedAmount(id), 1050e6);
        vm.warp(block.timestamp + 7 days);
        assertEq(sf.vestedAmount(id), 1050e6, "everything vested after window, no dust");
        vm.prank(alice);
        sf.claim(id);
        assertEq(usdc.balanceOf(alice), 1050e6);
    }

    function test_topUpFixedReverts() public {
        uint256 id = _linear(false);
        vm.prank(creator);
        vm.expectRevert(Sandfall.NotRolling.selector);
        sf.topUp(id, 1);
    }

    function test_rollingWindowBounds() public {
        vm.expectRevert(Sandfall.InvalidWindow.selector);
        sf.createRolling(address(usdc), alice, 1 hours, creator, false);
        vm.expectRevert(Sandfall.InvalidWindow.selector);
        sf.createRolling(address(usdc), alice, 400 days, creator, false);
    }

    function test_nonCancellableRollingCannotBeCancelled() public {
        uint256 id = sf.createRolling(address(usdc), alice, 7 days, creator, false);
        vm.prank(creator);
        vm.expectRevert(Sandfall.NotCancellable.selector);
        sf.cancel(id);
    }

    function test_reentrancyOnNativeClaim() public {
        RejectingRecipient r = new RejectingRecipient(sf);
        vm.prank(creator);
        uint256 id = sf.createFixed{value: 1 ether}(address(0), address(r), 1 ether, t0, t0, t0 + 1 days, 0, false);
        assertEq(id, 1);
        vm.warp(t0 + 1 days);
        vm.expectRevert(Sandfall.NativeTransferFailed.selector);
        r.claimFrom(id);
    }

    function test_cancelWorksEvenIfRecipientCannotReceive() public {
        RejectingRecipient r = new RejectingRecipient(sf);
        vm.prank(creator);
        uint256 id = sf.createFixed{value: 10 ether}(address(0), address(r), 10 ether, t0, t0, t0 + 10 days, 0, true);
        vm.warp(t0 + 5 days);
        uint256 before = creator.balance;
        vm.prank(creator);
        sf.cancel(id);
        assertEq(creator.balance - before, 5 ether, "unvested back to creator");
        assertEq(sf.claimable(id), 5 ether, "vested left for the recipient");
    }

    function test_dustTopUpDoesNotDelayVesting() public {
        uint256 id = sf.createRolling(address(usdc), alice, 30 days, creator, false);
        vm.prank(creator);
        sf.topUp(id, 3000e6);
        uint64 finish = sf.stream(id).periodFinish;
        vm.warp(block.timestamp + 10 days);
        vm.prank(creator);
        sf.topUp(id, 1); // a dust amount
        assertApproxEqAbs(sf.stream(id).periodFinish, finish, 1, "dust pushed vesting back");
        vm.warp(sf.stream(id).periodFinish);
        assertEq(sf.vestedAmount(id), 3000e6 + 1);
        vm.prank(creator);
        sf.topUp(id, 100e6); // nothing left vesting: the new amount gets a full window
        assertEq(sf.stream(id).periodFinish, block.timestamp + 30 days);
    }

    function test_splitTopUpsCannotSkipTheWindow() public {
        uint256 id = sf.createRolling(address(usdc), alice, 30 days, creator, true);
        vm.prank(creator);
        sf.topUp(id, 1000e6);
        vm.warp(block.timestamp + 30 days - 1 hours); // an hour before the window ends
        // many small top-ups in a row can't drag a big one into the ending window
        for (uint256 i; i < 200; ++i) {
            vm.prank(creator);
            sf.topUp(id, 9e6);
        }
        vm.prank(creator);
        sf.topUp(id, 10_000e6);
        vm.warp(block.timestamp + 1 hours);
        // the 10k (and the 1.8k) still mostly vest over about 30 days, not in the next hour
        assertLt(sf.vestedAmount(id), 1000e6 + 100e6, "top-up vested far too fast");
    }

    function test_claimToAnotherAddress() public {
        RejectingRecipient r = new RejectingRecipient(sf);
        vm.prank(creator);
        uint256 id = sf.createFixed{value: 1 ether}(address(0), address(r), 1 ether, t0, t0, t0 + 1 days, 0, false);
        vm.warp(t0 + 1 days);
        address safe = makeAddr("safe");
        vm.prank(address(r));
        assertEq(sf.claimTo(id, safe), 1 ether);
        assertEq(safe.balance, 1 ether);
        vm.prank(alice);
        vm.expectRevert(Sandfall.NotRecipient.selector);
        sf.claimTo(id, alice);
    }

    function test_listings() public {
        uint256 a = _linear(false);
        uint256 b = _linear(true);
        assertEq(sf.streamsOf(alice).length, 2);
        assertEq(sf.createdBy(creator)[1], b);
        assertTrue(sf.stream(b).cancellable);
        assertFalse(sf.stream(a).cancellable);
    }
}
