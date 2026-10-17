// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MonarchyFixture} from "./utils/MonarchyFixture.sol";
import {Lodestar} from "../src/Lodestar.sol";
import {LodestarFactory} from "../src/LodestarFactory.sol";
import {ILodestar} from "../src/interfaces/ILodestar.sol";
import {Sandfall} from "../src/Sandfall.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockSwapper} from "../src/mocks/MockSwapper.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LodestarTest is MonarchyFixture {
    MockERC20 internal token;
    bytes32 internal poolId;
    MockSwapper internal mockSwapper;

    // pool price: 800M tokens per 50k USDC = 1.6e16 token wei per USDC wei
    uint256 internal constant TOKENS_PER_QUOTE = 16_000e18 * 1e12;

    function setUp() public {
        _deployCore(address(0));
        (token, poolId) = _launch("MONARCH");
        mockSwapper = new MockSwapper(usdc, token, TOKENS_PER_QUOTE);
    }

    function _activateDefault(bool listing) internal returns (Lodestar) {
        return _activate(_params(token, 4_000, 4_000, 2_000, address(mockSwapper), listing));
    }

    // ---------------------------------------------------------------- 1. factory

    function test_predictMatchesDeployedClone() public {
        (address predicted, bytes32 id) = factory.predict(address(token), address(usdc));
        assertEq(id, poolId);
        Lodestar l = _activateDefault(false);
        assertEq(address(l), predicted);
        assertEq(launchpad.poolCreator(poolId), address(l));
        assertEq(launchpad.pendingCreator(poolId), address(0));
        assertTrue(l.isCreator());
        assertEq(l.steward(), dev);
        assertEq(factory.lodestarOf(address(token)), address(l));
        assertEq(factory.allLodestarsLength(), 1);
        // satellites are wired to the router
        Sandfall.Stream memory s = sandfall.stream(l.treasuryStreamId());
        assertEq(s.creator, address(l));
        assertEq(s.recipient, treasury);
        assertFalse(s.cancellable);
        assertEq(exile.poolInfo(l.exilePoolId()).admin, dev);
    }

    function test_deployRequiresTransferFirst() public {
        LodestarFactory.DeployParams memory p = _params(token, 4_000, 4_000, 2_000, address(mockSwapper), false);
        vm.prank(dev);
        vm.expectRevert(LodestarFactory.TransferCreatorFirst.selector);
        factory.deploy(p);
    }

    function test_deployOnlyByPoolCreator() public {
        LodestarFactory.DeployParams memory p = _params(token, 4_000, 4_000, 2_000, address(mockSwapper), false);
        (address predicted,) = factory.predict(address(token), address(usdc));
        vm.prank(dev);
        launchpad.transferCreator(poolId, predicted);
        vm.prank(trader);
        vm.expectRevert(LodestarFactory.NotPoolCreator.selector);
        factory.deploy(p);
    }

    function test_deployRejectsSwappedTokenAndQuote() public {
        LodestarFactory.DeployParams memory p = _params(token, 4_000, 4_000, 2_000, address(mockSwapper), false);
        (p.token, p.quote) = (p.quote, p.token);
        (address predicted,) = factory.predict(p.token, p.quote);
        vm.prank(dev);
        launchpad.transferCreator(poolId, predicted);
        vm.prank(dev);
        vm.expectRevert(LodestarFactory.WrongTokenOrder.selector);
        factory.deploy(p);
    }

    function test_newDefaultSwapperWaitsTwelveHours() public {
        LodestarFactory.DeployParams memory p = _params(token, 4_000, 4_000, 2_000, address(0), false);
        (address predicted,) = factory.predict(p.token, p.quote);
        vm.prank(dev);
        launchpad.transferCreator(poolId, predicted);
        factory.setDefaultSwapper(makeAddr("skimmer")); // the owner tries to slip in a new default
        vm.prank(dev);
        vm.expectRevert(LodestarFactory.DefaultSwapperJustChanged.selector);
        factory.deploy(p);
        // naming a swapper explicitly still works
        p.cfg.swapper = address(mockSwapper);
        vm.prank(dev);
        Lodestar l = Lodestar(factory.deploy{gas: 5_000_000}(p));
        assertEq(l.config().swapper, address(mockSwapper));
    }

    function test_cannotDeployTwice() public {
        LodestarFactory.DeployParams memory p = _params(token, 4_000, 4_000, 2_000, address(mockSwapper), false);
        _activate(p);
        vm.prank(dev);
        vm.expectRevert(LodestarFactory.NotPoolCreator.selector);
        factory.deploy(p);
    }

    function test_implementationAndCloneCannotBeReinitialized() public {
        Lodestar l = _activateDefault(false);
        ILodestar.InitParams memory ip;
        vm.expectRevert(Lodestar.AlreadyInitialized.selector);
        impl.initialize(ip);
        vm.expectRevert(Lodestar.AlreadyInitialized.selector);
        l.initialize(ip);
    }

    function test_defaultSwapperFillsIn() public {
        Lodestar l = _activate(_params(token, 4_000, 4_000, 2_000, address(0), false));
        assertEq(l.config().swapper, address(swapper));
    }

    function test_invalidSplitRejected() public {
        LodestarFactory.DeployParams memory p = _params(token, 4_000, 4_000, 1_000, address(mockSwapper), false);
        (address predicted,) = factory.predict(address(token), address(usdc));
        vm.prank(dev);
        launchpad.transferCreator(poolId, predicted);
        vm.prank(dev);
        vm.expectRevert(Lodestar.InvalidConfig.selector);
        factory.deploy(p);
    }

    // ---------------------------------------------------------------- 2. listing

    function test_listingElectionMovesToRouter() public {
        vm.prank(dev);
        desk.enroll(address(token), address(usdc), 1_000e6);
        assertEq(address(uint160(launchpad.listingElection(poolId))), dev);

        Lodestar l = _activateDefault(true);
        uint256 e = launchpad.listingElection(poolId);
        assertEq(address(uint160(e)), address(l), "election now belongs to the router");
        assertEq(e >> 168, 5_000e6, "router's cap");
    }

    function test_noListingWhenDisabled() public {
        _activateDefault(false);
        assertEq(launchpad.listingElection(poolId), 0);
    }

    // ---------------------------------------------------------------- 3. distribute

    function test_distributeWithListing() public {
        Lodestar l = _activateDefault(true);
        launchpad.injectFees(poolId, 1000e18, 1000e6);
        uint256 deadBefore = token.balanceOf(DEAD);

        l.distribute();

        // creator gets 500 of each; 20% of the quote share (100) goes to the listing set-aside
        assertEq(launchpad.listingOwed(poolId), 100e6);
        assertEq(l.totalTokenBurned(), 500e18);
        assertEq(l.totalBuybackQuote(), 160e6);
        assertEq(l.totalHoldersQuote(), 160e6);
        assertEq(l.totalTreasuryQuote(), 80e6);
        assertEq(l.totalBuybackTokensBurned(), 160e6 * TOKENS_PER_QUOTE / 1e18);
        assertEq(token.balanceOf(DEAD) - deadBefore, 500e18 + l.totalBuybackTokensBurned());
        assertEq(usdc.balanceOf(address(exile)), 160e6);
        assertEq(usdc.balanceOf(address(sandfall)), 80e6);
        assertEq(token.balanceOf(address(l)), 0);
        assertEq(usdc.balanceOf(address(l)), 0);
        assertEq(l.buybackReserve(), 0);
    }

    /// @dev Ascend tokens reject the usual 0x…dEaD address (found on Elysium testnet), so Lodestar burns
    /// to a different dead address. Both the direct burn and the buyback must land there.
    function test_burnsDespiteTokenRejectingZeroXDead() public {
        Lodestar l = _activate(_params(token, 4_000, 4_000, 2_000, address(0), false));
        address classicDead = 0x000000000000000000000000000000000000dEaD;
        _buy(poolId, trader, 1_000e6);
        vm.prank(trader);
        vm.expectRevert();
        token.transfer(classicDead, 1);

        launchpad.injectFees(poolId, 1000e18, 1000e6);
        l.distribute();
        assertGe(l.totalTokenBurned(), 500e18, "token fees burned");
        assertGt(l.totalBuybackTokensBurned(), 0, "buyback went through the real swapper");
        assertEq(l.buybackReserve(), 0);
        assertEq(token.balanceOf(address(l)), 0);
    }

    function test_distributeWithoutListing() public {
        Lodestar l = _activateDefault(false);
        launchpad.injectFees(poolId, 1000e18, 1000e6);
        l.distribute();
        assertEq(l.totalBuybackQuote(), 200e6);
        assertEq(l.totalHoldersQuote(), 200e6);
        assertEq(l.totalTreasuryQuote(), 100e6);
        assertEq(usdc.balanceOf(address(l)), 0);
    }

    function test_previewMatchesClaimable() public {
        Lodestar l = _activateDefault(false);
        launchpad.injectFees(poolId, 1000e18, 1000e6);
        launchpad.collect(poolId);
        (uint256 t, uint256 q, uint256 b, uint256 h, uint256 tr) = l.previewDistribute();
        assertEq(t, 500e18);
        assertEq(q, 500e6);
        assertEq(b + h + tr, q);
        assertEq(tr, 100e6);
    }

    // ---------------------------------------------------------------- 4. unannounced funds

    function test_routesFundsClaimedOrSentByOthers() public {
        Lodestar l = _activateDefault(false);
        launchpad.injectFees(poolId, 0, 1000e6);
        // Ascend's keeper collects and claims on its own schedule: funds land in the router
        vm.startPrank(trader);
        launchpad.collect(poolId);
        launchpad.claim(poolId);
        vm.stopPrank();
        assertEq(usdc.balanceOf(address(l)), 500e6);
        // and someone donates
        usdc.mint(address(l), 100e6);

        l.distribute();
        assertEq(l.totalBuybackQuote() + l.totalHoldersQuote() + l.totalTreasuryQuote(), 600e6);
        assertEq(usdc.balanceOf(address(l)), 0);
    }

    // ---------------------------------------------------------------- 5. remainder

    function testFuzz_splitConservesQuote(uint16 burn, uint16 holders, uint96 quoteFees) public {
        burn = uint16(bound(burn, 0, 10_000));
        holders = uint16(bound(holders, 0, 10_000 - burn));
        uint16 treas = 10_000 - burn - holders;
        quoteFees = uint96(bound(quoteFees, 0, 1e15));

        Lodestar l = _activate(_params(token, burn, holders, treas, address(mockSwapper), false));
        launchpad.injectFees(poolId, 0, quoteFees);
        l.distribute();

        uint256 q = uint256(quoteFees) * 5_000 / 10_000;
        uint256 burnQ = q * burn / 10_000;
        uint256 holdQ = q * holders / 10_000;
        uint256 rest = q - burnQ - holdQ;
        if (treas == 0) {
            if (holders > 0) holdQ += rest;
            else burnQ += rest;
        }
        // big buybacks are capped per call; the rest waits in reserve
        assertEq(l.totalBuybackQuote() + l.buybackReserve(), burnQ, "buyback share");
        assertEq(l.totalHoldersQuote(), holdQ, "holder share");
        assertEq(l.totalBuybackQuote() + l.buybackReserve() + l.totalHoldersQuote() + l.totalTreasuryQuote(), q);
        assertEq(usdc.balanceOf(address(l)), l.buybackReserve());
    }

    // ---------------------------------------------------------------- 6. buyback skip

    function test_failedBuybackWaitsInReserve() public {
        Lodestar l = _activateDefault(false);
        mockSwapper.setFail(true);
        launchpad.injectFees(poolId, 0, 1000e6);

        vm.expectEmit(false, false, false, false, address(l));
        emit Lodestar.BuybackSkipped(0, 0);
        l.distribute();
        assertEq(l.buybackReserve(), 200e6);
        assertEq(usdc.balanceOf(address(l)), 200e6);
        assertEq(l.totalHoldersQuote(), 200e6, "holders still paid");
        assertEq(l.totalTreasuryQuote(), 100e6, "treasury still paid");

        mockSwapper.setFail(false);
        launchpad.injectFees(poolId, 0, 1000e6);
        uint256 cap = l.maxBuyback(); // 0.5% of the pool's 50k USDC side
        assertApproxEqRel(cap, 250e6, 1e15);
        l.distribute();
        // after a skip the next attempt is half of the capped size
        assertEq(l.totalBuybackQuote(), cap / 2, "half size after a skip");
        assertEq(l.totalHoldersQuote(), 400e6, "reserve is not split again");

        for (uint256 i; i < 5 && l.buybackReserve() > 0; ++i) {
            l.distribute();
        }
        assertEq(l.totalBuybackQuote(), 400e6, "everything bought back in pieces");
        assertEq(l.buybackReserve(), 0);
        assertEq(usdc.balanceOf(address(l)), 0);
        assertEq(l.buybackShift(), 0);
    }

    function test_reserveTooBigForPoolIsBoughtInPieces() public {
        Lodestar l = _activateDefault(false);
        // a month without a swapper builds a reserve far bigger than the pool can take in one buy
        mockSwapper.setFail(true);
        for (uint256 i; i < 30; ++i) {
            launchpad.injectFees(poolId, 0, 1000e6);
            l.distribute();
        }
        assertEq(l.buybackReserve(), 6_000e6);
        mockSwapper.setFail(false);
        mockSwapper.setMaxIn(500e6);

        for (uint256 i; i < 40 && l.buybackReserve() > 0; ++i) {
            l.distribute();
        }
        assertEq(l.buybackReserve(), 0, "reserve unstuck");
        assertEq(l.totalBuybackQuote(), 6_000e6);
        assertEq(usdc.balanceOf(address(mockSwapper)), 6_000e6);
    }

    function test_eachBuybackIsCappedByPoolDepth() public {
        Lodestar l = _activate(_params(token, 10_000, 0, 0, address(mockSwapper), false));
        launchpad.injectFees(poolId, 0, 4_000e6); // 2,000 USDC to buy back
        uint256 cap = l.maxBuyback();
        l.distribute();
        assertEq(l.totalBuybackQuote(), cap, "one capped piece per distribute");
        assertEq(l.buybackReserve(), 2_000e6 - cap);
    }

    function test_dustDoesNotShrinkTheNextBuyback() public {
        Lodestar l = _activateDefault(false);
        mockSwapper.setMaxIn(1e6); // dust-sized attempts fail, like a pool rounding its fee up
        for (uint256 i; i < 10; ++i) {
            usdc.mint(address(l), 3);
            l.distribute();
        }
        assertEq(l.buybackShift(), 0, "dust failures don't count");
    }

    function test_emaFailureDoesNotBlockDistribute() public {
        Lodestar l = _activateDefault(false);
        launchpad.injectFees(poolId, 0, 1000e6);
        vm.mockCallRevert(address(launchpad), abi.encodeWithSignature("emaSqrtPrice(bytes32)", poolId), "down");
        l.distribute();
        assertEq(l.buybackReserve(), 200e6, "buyback waits");
        assertEq(l.totalHoldersQuote(), 200e6, "holders still paid");
        assertEq(l.totalTreasuryQuote(), 100e6, "treasury still paid");
    }

    function test_failedHolderPayoutIsKeptForThem() public {
        Lodestar l = _activateDefault(false);
        launchpad.injectFees(poolId, 0, 1000e6);
        vm.mockCallRevert(address(exile), abi.encodeWithSignature("notifyReward(uint256,uint256)"), "stuck");
        l.distribute();
        assertEq(l.holdersReserve(), 200e6);
        assertEq(l.totalTreasuryQuote(), 100e6, "treasury still paid");
        vm.clearMockedCalls();
        l.distribute();
        assertEq(l.holdersReserve(), 0);
        assertEq(l.totalHoldersQuote(), 200e6, "holders get all of it, not a re-split");
        assertEq(l.totalTreasuryQuote(), 100e6);
    }

    function test_noTreasuryShareSendsRemainderToHolders() public {
        Lodestar l = _activate(_params(token, 5_000, 5_000, 0, address(mockSwapper), false));
        launchpad.injectFees(poolId, 0, 3); // 1 quote unit to split, all rounding
        usdc.mint(address(l), 2);
        l.distribute();
        assertEq(l.totalTreasuryQuote(), 0, "treasury stream untouched");
    }

    function test_swapperThatBurnsNothingIsRejected() public {
        Lodestar l = _activateDefault(false);
        mockSwapper.setShortChange(true);
        launchpad.injectFees(poolId, 0, 1000e6);
        l.distribute();
        assertEq(l.totalBuybackQuote(), 0, "no credit for a buy that burned nothing");
        assertEq(l.buybackReserve(), 200e6, "quote kept in reserve");
        assertEq(usdc.balanceOf(address(l)), 200e6);
        assertEq(usdc.balanceOf(address(mockSwapper)), 0);
    }

    function test_buybackStepOnlyFromItself() public {
        Lodestar l = _activateDefault(false);
        vm.expectRevert(Lodestar.OnlySelf.selector);
        l.buybackStep(address(mockSwapper), 1e6, 1);
    }

    function test_claimFailureDoesNotBlock() public {
        Lodestar l = _activateDefault(false);
        usdc.mint(address(l), 1000e6); // e.g. a listing refund
        vm.mockCallRevert(address(launchpad), abi.encodeWithSignature("claim(bytes32)", poolId), "paused");
        l.distribute();
        assertEq(l.totalHoldersQuote(), 400e6, "balance still routed");
    }

    function test_noSwapperKeepsReserve() public {
        Lodestar l = _activateDefault(false);
        vm.prank(dev);
        l.proposeConfig(ILodestar.Config(4_000, 4_000, 2_000, address(0), 300));
        vm.warp(block.timestamp + 12 hours);
        l.executeConfig();
        // factory default only applies at deploy; a later config may set no swapper
        assertEq(l.config().swapper, address(0));
        launchpad.injectFees(poolId, 0, 1000e6);
        l.distribute();
        assertEq(l.buybackReserve(), 200e6);
    }

    // ---------------------------------------------------------------- 8. timelock

    function test_configTimelock() public {
        Lodestar l = _activateDefault(false);
        ILodestar.Config memory c = ILodestar.Config(2_000, 6_000, 2_000, address(mockSwapper), 500);

        vm.prank(trader);
        vm.expectRevert(Lodestar.OnlySteward.selector);
        l.proposeConfig(c);

        vm.expectRevert(Lodestar.NoPendingConfig.selector);
        l.executeConfig();

        vm.prank(dev);
        l.proposeConfig(c);
        (, uint64 eta) = l.pendingConfig();
        assertEq(eta, block.timestamp + 12 hours);

        vm.warp(eta - 1);
        vm.expectRevert(Lodestar.TimelockActive.selector);
        l.executeConfig();

        // re-proposing resets the clock
        vm.prank(dev);
        l.proposeConfig(c);
        vm.warp(eta);
        vm.expectRevert(Lodestar.TimelockActive.selector);
        l.executeConfig();

        vm.warp(block.timestamp + 12 hours);
        vm.prank(trader); // anyone can execute once the timelock passes
        l.executeConfig();
        assertEq(l.config().holdersBps, 6_000);
        assertEq(l.config().maxSlippageBps, 500);
    }

    function test_readyConfigExpires() public {
        Lodestar l = _activateDefault(false);
        vm.prank(dev);
        l.proposeConfig(ILodestar.Config(2_000, 6_000, 2_000, address(mockSwapper), 500));
        (, uint64 eta) = l.pendingConfig();
        vm.warp(eta + 7 days + 1);
        vm.expectRevert(Lodestar.ProposalExpired.selector);
        l.executeConfig();
        assertEq(l.config().holdersBps, 4_000);
    }

    function test_cancelConfig() public {
        Lodestar l = _activateDefault(false);
        vm.prank(dev);
        l.proposeConfig(ILodestar.Config(0, 10_000, 0, address(mockSwapper), 300));
        vm.prank(dev);
        l.cancelConfig();
        vm.warp(block.timestamp + 73 hours);
        vm.expectRevert(Lodestar.NoPendingConfig.selector);
        l.executeConfig();
        assertEq(l.config().holdersBps, 4_000);
    }

    function test_configValidation() public {
        Lodestar l = _activateDefault(false);
        vm.startPrank(dev);
        vm.expectRevert(Lodestar.InvalidConfig.selector);
        l.proposeConfig(ILodestar.Config(5_000, 5_000, 1, address(mockSwapper), 300));
        vm.expectRevert(Lodestar.InvalidConfig.selector);
        l.proposeConfig(ILodestar.Config(5_000, 5_000, 0, address(mockSwapper), 2_001));
        vm.expectRevert(Lodestar.InvalidConfig.selector);
        l.proposeConfig(ILodestar.Config(5_000, 5_000, 0, address(mockSwapper), 99)); // would block every buyback
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- 9. creator lock

    function test_creatorLock() public {
        LodestarFactory.DeployParams memory p = _params(token, 4_000, 4_000, 2_000, address(mockSwapper), false);
        p.creatorLockUntil = uint64(block.timestamp + 365 days);
        Lodestar l = _activate(p);
        assertEq(l.creatorLockedUntil(), p.creatorLockUntil);

        vm.startPrank(dev);
        vm.expectRevert(Lodestar.CreatorRoleIsLocked.selector);
        l.transferCreatorOut(dev);
        vm.expectRevert(Lodestar.NotExtending.selector);
        l.lockCreatorRole(uint64(block.timestamp + 30 days));
        vm.stopPrank();

        vm.warp(p.creatorLockUntil);
        vm.prank(dev);
        l.transferCreatorOut(dev);
        assertEq(launchpad.pendingCreator(poolId), dev);
    }

    function test_cannotLockWhileAHandOffIsPending() public {
        Lodestar l = _activateDefault(false);
        address alt = makeAddr("alt");
        vm.startPrank(dev);
        l.transferCreatorOut(alt);
        vm.expectRevert(Lodestar.CreatorTransferPending.selector);
        l.lockCreatorRole(type(uint64).max);
        // cancelling the hand-off, then locking, works
        l.transferCreatorOut(address(0));
        l.lockCreatorRole(type(uint64).max);
        vm.stopPrank();
        vm.prank(alt);
        vm.expectRevert();
        launchpad.acceptCreator(poolId);
        assertTrue(l.isCreator());
    }

    function test_cancelAllowedWhileLocked() public {
        Lodestar l = _activateDefault(false);
        vm.prank(dev);
        l.lockCreatorRole(type(uint64).max);
        vm.prank(dev);
        l.transferCreatorOut(address(0)); // cancelling never hands the role anywhere
        assertEq(launchpad.pendingCreator(poolId), address(0));
    }

    function test_creatorLockForever() public {
        Lodestar l = _activateDefault(false);
        vm.prank(dev);
        l.lockCreatorRole(type(uint64).max);
        vm.warp(block.timestamp + 100 * 365 days);
        vm.prank(dev);
        vm.expectRevert(Lodestar.CreatorRoleIsLocked.selector);
        l.transferCreatorOut(dev);
    }

    function test_onlyStewardControlsRole() public {
        Lodestar l = _activateDefault(false);
        vm.startPrank(trader);
        vm.expectRevert(Lodestar.OnlySteward.selector);
        l.transferCreatorOut(trader);
        vm.expectRevert(Lodestar.OnlySteward.selector);
        l.lockCreatorRole(type(uint64).max);
        vm.expectRevert(Lodestar.OnlySteward.selector);
        l.transferSteward(trader);
        vm.expectRevert(Lodestar.OnlyFactory.selector);
        l.acceptCreator();
        vm.stopPrank();

        vm.prank(dev);
        l.transferSteward(trader);
        assertEq(l.steward(), trader);
    }

    // ---------------------------------------------------------------- 10. reentrancy

    function test_reentrantSwapperFallsBackToReserve() public {
        Lodestar l = _activateDefault(false);
        mockSwapper.setReenter(address(l), abi.encodeCall(Lodestar.distribute, ()));
        launchpad.injectFees(poolId, 0, 1000e6);
        l.distribute();
        assertEq(l.buybackReserve(), 200e6, "re-entry reverted inside the try, buyback waits");
        assertEq(l.totalHoldersQuote(), 200e6);
    }

    // ---------------------------------------------------------------- 11. collect failure

    function test_collectFailureDoesNotBlock() public {
        Lodestar l = _activateDefault(false);
        launchpad.injectFees(poolId, 0, 1000e6);
        launchpad.collect(poolId);
        launchpad.setCollectReverts(poolId, true);

        vm.expectEmit(false, false, false, false, address(l));
        emit Lodestar.CollectFailed();
        l.distribute();
        assertEq(l.totalHoldersQuote(), 200e6, "already-owed fees still claimed and routed");
    }

    // ---------------------------------------------------------------- 12. gas

    function test_gasDistributeWithRealSwapper() public {
        Lodestar l = _activate(_params(token, 4_000, 4_000, 2_000, address(0), true));
        _buy(poolId, trader, 10_000e6);
        uint256 g = gasleft();
        l.distribute(); // first run pays for fresh storage slots everywhere
        uint256 first = g - gasleft();

        vm.warp(block.timestamp + 1 hours);
        _buy(poolId, trader, 10_000e6);
        g = gasleft();
        l.distribute();
        uint256 steady = g - gasleft();

        emit log_named_uint("distribute gas (first)", first);
        emit log_named_uint("distribute gas (steady)", steady);
        // Loose ceilings: measured gas differs between forge versions (about 440k steady locally,
        // 670k on CI's stable forge), and Elysium gas is cheap. This guards against blow-ups only.
        assertLt(first, 1_200_000);
        assertLt(steady, 1_000_000);
        assertGt(l.totalBuybackTokensBurned(), 0);
    }
}
