// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAscendLaunchpad} from "./interfaces/IAscendLaunchpad.sol";
import {IListingDesk} from "./interfaces/IListingDesk.sol";
import {ICLPoolManager} from "./interfaces/IInfinity.sol";
import {IBuybackSwapper} from "./interfaces/IBuybackSwapper.sol";
import {IExile} from "./interfaces/IExile.sol";
import {ISandfall} from "./interfaces/ISandfall.sol";
import {ILodestar} from "./interfaces/ILodestar.sol";

/// @title Lodestar
/// @notice Fee router for one Ascend token. Once it holds the token's creator role on Ascend, every
/// creator fee lands here, and anyone can call `distribute()` to route it:
///   - project-token fees are burned;
///   - quote fees are split by the creator's chosen percentages between buyback and burn,
///     Exile holder rewards and the Team Treasury (a Sandfall stream).
/// Split changes wait behind a 12 hour timelock. The creator role can be locked here so the router
/// can't be swapped out. No protocol fee. Deployed as one minimal clone per token by LodestarFactory.
contract Lodestar is ILodestar, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant SWAP_FEE_BPS = 100; // Ascend's 1% pool fee
    uint256 public constant MIN_SLIPPAGE_BPS = 100;
    uint256 public constant MAX_SLIPPAGE_BPS = 2_000;
    uint64 public constant TIMELOCK = 12 hours;
    /// @dev A ready config change must be executed within this window, or proposed again.
    uint64 public constant EXECUTION_WINDOW = 7 days;
    /// @dev After a skipped buyback the next attempt halves, down to 1/256 of the amount due.
    uint8 public constant MAX_BUYBACK_SHIFT = 8;
    /// @dev Each buyback spends at most this share of the quote side of the pool's active liquidity
    /// (valued at the EMA price, or at spot when that gives a smaller depth). A buy that small moves
    /// the price about 1%, which is less than the 1% fee a sandwich pays each way, so sandwiching it
    /// doesn't pay.
    uint256 public constant MAX_BUY_DEPTH_BPS = 50;
    /// @dev At most one buyback every 30 minutes. The depth cap bounds one buy; without a gap between buys a
    /// caller could push several capped pieces through in one transaction, between their own buy and
    /// sell, and collect about 1% per piece for one 2% round trip in fees. The keeper runs every 3 hours,
    /// so the gap costs nothing in the normal flow.
    uint64 public constant BUYBACK_INTERVAL = 30 minutes;
    /// @dev Burn sink. Ascend's launch tokens reject transfers to address(0) and to 0x…dEaD, so burns go
    /// to this widely used dead address instead. Nobody holds its key.
    address public constant DEAD = 0xdEAD000000000000000042069420694206942069;

    address public factory;
    IAscendLaunchpad public launchpad;
    IListingDesk public desk;
    ICLPoolManager public poolManager;
    IExile public exile;
    ISandfall public sandfall;
    bytes32 public poolId;
    IERC20 public token;
    IERC20 public quote;
    bool public tokenIs0;
    uint256 public exilePoolId;
    uint256 public treasuryStreamId;

    address public steward;
    Config internal _cfg;
    Config internal _pendingCfg;
    uint64 public pendingEta;
    uint64 public creatorLockedUntil;
    uint256 public buybackReserve;
    bool internal _initialized;

    uint256 public totalTokenBurned; // token-side fees burned directly
    uint256 public totalBuybackQuote;
    uint256 public totalBuybackTokensBurned;
    uint256 public totalHoldersQuote;
    uint256 public totalTreasuryQuote;
    uint64 public lastDistributeAt;
    /// @notice Each attempt buys `due >> buybackShift`. Rises by one after a skipped buyback and falls by
    /// one after a successful one, so a reserve too big for the pool is bought back in smaller pieces.
    uint8 public buybackShift;
    /// @notice When the last buyback went through; the next one waits `BUYBACK_INTERVAL`.
    uint64 public lastBuybackAt;
    /// @notice When the attempt size was last halved. It halves at most once per `BUYBACK_INTERVAL`, the
    /// same rate at which successes double it back, so a burst of failed calls can't shrink it for hours.
    uint64 public lastHalvingAt;
    /// @notice Holder rewards or treasury top-ups that couldn't be paid out yet; retried on the next distribute.
    uint256 public holdersReserve;
    uint256 public treasuryReserve;

    event Initialized(bytes32 indexed poolId, address indexed token, address quote, address steward, Config config);
    event Distributed(
        uint256 tokenBurned,
        uint256 quoteRouted,
        uint256 buybackQuote,
        uint256 buybackTokensBurned,
        uint256 holdersQuote,
        uint256 treasuryQuote
    );
    event BuybackSkipped(uint256 amount, uint256 minOut);
    event TokenBurnFailed(uint256 amount);
    event CollectFailed();
    event ClaimFailed();
    event HoldersPayoutFailed(uint256 amount);
    event TreasuryPayoutFailed(uint256 amount);
    event ConfigProposed(Config config, uint64 eta);
    event ConfigExecuted(Config config);
    event ConfigCancelled();
    event CreatorRoleLocked(uint64 until);
    event CreatorAccepted();
    event CreatorTransferOutStarted(address next);
    event ListingEnrolled(uint256 cap);
    event ListingClosed();
    event StewardTransferred(address indexed previous, address indexed next);

    error AlreadyInitialized();
    error OnlySteward();
    error InvalidConfig();
    error NoPendingConfig();
    error TimelockActive();
    error CreatorNotPending();
    error CreatorRoleIsLocked();
    error NotExtending();
    error ZeroAddress();
    error ProposalExpired();
    error OnlySelf();
    error BuybackShort();
    error CreatorTransferPending();
    error SelfTransfer();

    constructor() {
        _initialized = true; // the implementation itself can never be initialized
    }

    modifier onlySteward() {
        if (msg.sender != steward) revert OnlySteward();
        _;
    }

    modifier onlyStewardOrFactory() {
        if (msg.sender != steward && msg.sender != factory) revert OnlySteward();
        _;
    }

    // ================================================================ setup (factory)

    function initialize(InitParams calldata p) external {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;
        _validate(p.config);
        if (p.steward == address(0)) revert ZeroAddress();
        factory = msg.sender;
        launchpad = IAscendLaunchpad(p.launchpad);
        desk = IListingDesk(p.desk);
        poolManager = ICLPoolManager(p.poolManager);
        exile = IExile(p.exile);
        sandfall = ISandfall(p.sandfall);
        poolId = p.poolId;
        token = IERC20(p.token);
        quote = IERC20(p.quote);
        tokenIs0 = p.tokenIs0;
        exilePoolId = p.exilePoolId;
        treasuryStreamId = p.treasuryStreamId;
        steward = p.steward;
        _cfg = p.config;
        emit Initialized(p.poolId, p.token, p.quote, p.steward, p.config);
    }

    /// @notice Second half of Ascend's two-step creator handover. The current creator must have called
    /// `transferCreator(poolId, thisLodestar)` on Ascend first; that call is the consent, so anyone may
    /// finish the hand-off. The factory calls this at deploy, and it works again later if the role ever
    /// left (an expired lock, a hand-out the steward reverses), so a token can come back to Monarchy.
    /// A creator handing the role back should claim their own fees first: whatever is still owed when the
    /// hand-off completes is paid to the new creator, this router, and routed. Accepting also clears the
    /// listing election on Ascend, so the steward enrols again afterwards if wanted.
    function acceptCreator() external {
        if (launchpad.pendingCreator(poolId) != address(this)) revert CreatorNotPending();
        launchpad.acceptCreator(poolId);
        emit CreatorAccepted();
    }

    // ================================================================ routing (anyone)

    /// @notice Collect and claim this token's creator fees from Ascend and route everything this
    /// router holds. Permissionless. The buyback's minimum output comes from Ascend's EMA price (or
    /// spot, whichever asks for more), each buy is capped at a small share of the pool's depth, and
    /// buys are at least 30 minutes apart, so sandwiching them doesn't pay. Any step that fails keeps its
    /// amount here and retries next time; the other steps still run.
    function distribute() external nonReentrant {
        // low-level calls, so even a changed return shape can't block routing
        (bool ok,) = address(launchpad).call(abi.encodeCall(IAscendLaunchpad.collect, (poolId)));
        if (!ok) emit CollectFailed(); // Ascend's keeper may have collected already
        (ok,) = address(launchpad).call(abi.encodeCall(IAscendLaunchpad.claim, (poolId)));
        if (!ok) emit ClaimFailed();

        // project-token side: burn all of it
        uint256 t = token.balanceOf(address(this));
        if (t > 0) {
            if (_tryTransfer(token, DEAD, t)) {
                totalTokenBurned += t;
            } else {
                emit TokenBurnFailed(t);
                t = 0;
            }
        }

        // quote side: balance based, so fees claimed by anyone else and listing refunds are routed too
        Config memory c = _cfg;
        uint256 q = quote.balanceOf(address(this)) - buybackReserve - holdersReserve - treasuryReserve;
        uint256 burnQ = q * c.burnBps / BPS;
        uint256 holdQ = q * c.holdersBps / BPS;
        uint256 rest = q - burnQ - holdQ;
        // the rounding remainder goes to a share that is switched on
        if (c.treasuryBps == 0) {
            if (c.holdersBps > 0) holdQ += rest;
            else burnQ += rest;
            rest = 0;
        }
        uint256 treasQ = rest + treasuryReserve;
        holdQ += holdersReserve;

        (uint256 spent, uint256 bought) = _buyback(c, burnQ + buybackReserve);

        if (holdQ > 0) {
            quote.forceApprove(address(exile), holdQ);
            try exile.notifyReward(exilePoolId, holdQ) {
                totalHoldersQuote += holdQ;
                holdersReserve = 0;
            } catch {
                quote.forceApprove(address(exile), 0);
                holdersReserve = holdQ;
                emit HoldersPayoutFailed(holdQ);
                holdQ = 0;
            }
        }
        if (treasQ > 0) {
            bool paid;
            if (treasQ <= type(uint128).max) {
                quote.forceApprove(address(sandfall), treasQ);
                try sandfall.topUp(treasuryStreamId, uint128(treasQ)) {
                    paid = true;
                } catch {
                    quote.forceApprove(address(sandfall), 0);
                }
            }
            if (paid) {
                totalTreasuryQuote += treasQ;
                treasuryReserve = 0;
            } else {
                treasuryReserve = treasQ;
                emit TreasuryPayoutFailed(treasQ);
                treasQ = 0;
            }
        }

        lastDistributeAt = uint64(block.timestamp);
        emit Distributed(t, q, spent, bought, holdQ, treasQ);
    }

    function _buyback(Config memory c, uint256 buyAmt) internal returns (uint256 spent, uint256 bought) {
        if (buyAmt > 0 && c.swapper != address(0) && block.timestamp >= lastBuybackAt + BUYBACK_INTERVAL) {
            uint256 ema = _ema();
            uint256 spot = _spot();
            uint256 cap = _maxBuyback(ema, spot);
            uint256 full = cap != 0 && buyAmt > cap ? cap : buyAmt;
            uint256 attempt = full >> buybackShift;
            if (attempt == 0) attempt = full;
            uint256 minOut = _minOut(ema, spot, attempt, c.maxSlippageBps);
            bool ok;
            if (minOut > 0) {
                try this.buybackStep(c.swapper, attempt, minOut) returns (uint256 s_, uint256 b_) {
                    (spent, bought, ok) = (s_, b_, true);
                } catch {}
            }
            if (ok) {
                lastBuybackAt = uint64(block.timestamp);
                totalBuybackQuote += spent;
                totalBuybackTokensBurned += bought;
                if (buybackShift > 0) --buybackShift;
            } else {
                // only a real attempt counts: with no EMA nothing was tried, and dust attempts are exempt,
                // so neither an EMA-less first day nor a few wei can shrink the next real buyback; and it
                // halves at most once per interval, so repeated calls during one pump can't run it to 1/256
                if (
                    ema != 0 && buybackShift < MAX_BUYBACK_SHIFT && (cap == 0 || attempt * 256 >= cap)
                        && block.timestamp >= lastHalvingAt + BUYBACK_INTERVAL
                ) {
                    ++buybackShift;
                    lastHalvingAt = uint64(block.timestamp);
                }
                emit BuybackSkipped(attempt, minOut);
            }
        }
        buybackReserve = buyAmt - spent;
    }

    /// @notice One buyback, checked by what actually happened: at most `amountIn` quote left this router
    /// and at least `minOut` tokens reached the burn address. Only callable by this router, from
    /// `distribute`, so a bad swap reverts here and the quote stays in reserve.
    function buybackStep(address swapper, uint256 amountIn, uint256 minOut)
        external
        returns (uint256 spent, uint256 burned)
    {
        if (msg.sender != address(this)) revert OnlySelf();
        uint256 quoteBefore = quote.balanceOf(address(this));
        uint256 deadBefore = token.balanceOf(DEAD);
        quote.forceApprove(swapper, amountIn);
        IBuybackSwapper(swapper).buyExactIn(poolId, amountIn, minOut, DEAD);
        quote.forceApprove(swapper, 0);
        spent = quoteBefore - quote.balanceOf(address(this));
        burned = token.balanceOf(DEAD) - deadBefore;
        if (burned < minOut || spent > amountIn) revert BuybackShort();
    }

    /// @notice Minimum tokens to accept when buying with `quoteIn`: the stricter of the floors at Ascend's
    /// EMA price and at the pool's spot price, minus the pool fee and the slippage allowance. Returns 0
    /// (no buyback) when there is no EMA: spot alone is never trusted, since a sandwich can move it in
    /// the same transaction. Spot can only tighten the floor, so a dump (which leaves the EMA stale and
    /// high) can't loosen it either.
    function quoteMinOut(uint256 quoteIn, uint256 slippageBps) public view returns (uint256) {
        return _minOut(_ema(), _spot(), quoteIn, slippageBps);
    }

    /// @notice Largest single buyback right now (0 = the pool doesn't report its liquidity, no cap).
    function maxBuyback() external view returns (uint256) {
        return _maxBuyback(_ema(), _spot());
    }

    /// @notice Earliest time the next buyback can go through (0 = nothing bought yet, no wait).
    function nextBuybackAt() external view returns (uint64) {
        return lastBuybackAt == 0 ? 0 : lastBuybackAt + BUYBACK_INTERVAL;
    }

    function _ema() internal view returns (uint256 sp) {
        try launchpad.emaSqrtPrice(poolId) returns (uint160 e) {
            sp = e;
        } catch {}
    }

    function _spot() internal view returns (uint256 sp) {
        try poolManager.getSlot0(poolId) returns (uint160 s, int24, uint24, uint24) {
            sp = s;
        } catch {}
    }

    /// @dev Quote side of the active liquidity: L * sqrtP for currency1, L / sqrtP for currency0. Valued
    /// at whichever of the EMA and spot prices gives the smaller depth: a pump raises spot and the EMA
    /// stays in charge, a dump lowers spot and the cap shrinks with it instead of trusting a stale EMA.
    function _maxBuyback(uint256 ema, uint256 spot) internal view returns (uint256) {
        if (ema == 0) return 0;
        uint256 liq;
        try poolManager.getLiquidity(poolId) returns (uint128 l_) {
            liq = l_;
        } catch {
            return 0;
        }
        if (liq == 0) return 0;
        uint256 sp = ema;
        if (spot != 0) sp = tokenIs0 ? Math.min(ema, spot) : Math.max(ema, spot);
        uint256 depth = tokenIs0 ? Math.mulDiv(liq, sp, 1 << 96) : Math.mulDiv(liq, 1 << 96, sp);
        uint256 cap = depth * MAX_BUY_DEPTH_BPS / BPS;
        return cap == 0 ? 1 : cap;
    }

    function _minOut(uint256 ema, uint256 spot, uint256 quoteIn, uint256 slippageBps)
        internal
        view
        returns (uint256)
    {
        if (ema == 0) return 0;
        return Math.max(_floor(ema, quoteIn, slippageBps), _floor(spot, quoteIn, slippageBps));
    }

    function _floor(uint256 sp, uint256 quoteIn, uint256 slippageBps) internal view returns (uint256) {
        if (sp == 0) return 0;
        // price = (sp / 2^96)^2 = currency1 per currency0
        uint256 expected = tokenIs0
            ? Math.mulDiv(Math.mulDiv(quoteIn, 1 << 96, sp), 1 << 96, sp)
            : Math.mulDiv(Math.mulDiv(quoteIn, sp, 1 << 96), sp, 1 << 96);
        return expected * (BPS - SWAP_FEE_BPS - slippageBps) / BPS;
    }

    function executeConfig() external {
        if (pendingEta == 0) revert NoPendingConfig();
        if (block.timestamp < pendingEta) revert TimelockActive();
        if (block.timestamp > pendingEta + EXECUTION_WINDOW) revert ProposalExpired();
        _cfg = _pendingCfg;
        delete _pendingCfg;
        pendingEta = 0;
        emit ConfigExecuted(_cfg);
    }

    // ================================================================ steward

    function proposeConfig(Config calldata c) external onlySteward {
        _validate(c);
        _pendingCfg = c;
        pendingEta = uint64(block.timestamp) + TIMELOCK;
        emit ConfigProposed(c, pendingEta);
    }

    function cancelConfig() external onlySteward {
        if (pendingEta == 0) revert NoPendingConfig();
        delete _pendingCfg;
        pendingEta = 0;
        emit ConfigCancelled();
    }

    /// @notice Promise the creator role stays with this router until `until` (type(uint64).max = forever).
    /// Can only be extended, and not while a hand-off is pending (it could be accepted after locking).
    function lockCreatorRole(uint64 until) external onlyStewardOrFactory {
        if (until <= creatorLockedUntil || until <= block.timestamp) revert NotExtending();
        if (launchpad.pendingCreator(poolId) != address(0)) revert CreatorTransferPending();
        creatorLockedUntil = until;
        emit CreatorRoleLocked(until);
    }

    /// @notice Start handing the Ascend creator role to `next`. Blocked while locked; `next = 0` cancels a
    /// pending hand-off and is always allowed.
    function transferCreatorOut(address next) external onlySteward {
        if (next != address(0) && block.timestamp < creatorLockedUntil) revert CreatorRoleIsLocked();
        // a hand-off to itself would let anyone "accept" and clear the listing election for nothing
        if (next == address(this)) revert SelfTransfer();
        launchpad.transferCreator(poolId, next);
        emit CreatorTransferOutStarted(next);
    }

    /// @notice Enrol in Ascend's listing set-aside: 20% of the creator's quote fees are held toward a
    /// HyperCore listing until `cap` is reached.
    function enrollListing(uint256 cap) external onlyStewardOrFactory {
        desk.enroll(address(token), address(quote), cap);
        emit ListingEnrolled(cap);
    }

    function closeListing() external onlySteward {
        desk.close(poolId);
        emit ListingClosed();
    }

    function transferSteward(address next) external onlySteward {
        if (next == address(0)) revert ZeroAddress();
        emit StewardTransferred(steward, next);
        steward = next;
    }

    /// @notice Queue a new tier table for this token's Exile pool. This router is the pool's admin, so
    /// tier changes follow the steward (and move with `transferSteward`) and wait out Exile's 12 hour
    /// timelock; anyone can execute them on Exile once ready.
    function proposeTiers(IExile.Tier[] calldata tiers) external onlySteward {
        exile.proposeTiers(exilePoolId, tiers);
    }

    function cancelTiers() external onlySteward {
        exile.cancelTiers(exilePoolId);
    }

    // ================================================================ views

    function config() external view returns (Config memory) {
        return _cfg;
    }

    function pendingConfig() external view returns (Config memory cfg, uint64 eta) {
        return (_pendingCfg, pendingEta);
    }

    /// @notice What a distribute would route from fees already claimable on Ascend plus this router's balance.
    /// Fees still sitting in the pool (not yet collected) are not included.
    function previewDistribute()
        external
        view
        returns (uint256 tokenToBurn, uint256 quoteTotal, uint256 burnQ, uint256 holdQ, uint256 treasQ)
    {
        tokenToBurn = token.balanceOf(address(this)) + launchpad.creatorOwedToken(poolId);
        quoteTotal = quote.balanceOf(address(this)) - buybackReserve - holdersReserve - treasuryReserve
            + launchpad.creatorOwedQuote(poolId);
        burnQ = quoteTotal * _cfg.burnBps / BPS;
        holdQ = quoteTotal * _cfg.holdersBps / BPS;
        treasQ = quoteTotal - burnQ - holdQ;
    }

    function isCreator() external view returns (bool) {
        return launchpad.poolCreator(poolId) == address(this);
    }

    // ================================================================ internals

    function _validate(Config memory c) internal pure {
        if (uint256(c.burnBps) + c.holdersBps + c.treasuryBps != BPS) revert InvalidConfig();
        if (c.maxSlippageBps < MIN_SLIPPAGE_BPS || c.maxSlippageBps > MAX_SLIPPAGE_BPS) revert InvalidConfig();
    }

    function _tryTransfer(IERC20 asset, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory ret) = address(asset).call(abi.encodeCall(IERC20.transfer, (to, amount)));
        return ok && (ret.length == 0 || abi.decode(ret, (bool)));
    }
}
