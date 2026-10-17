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
/// Split changes wait behind a 72 hour timelock. The creator role can be locked here so the router
/// can't be swapped out. No protocol fee. Deployed as one minimal clone per token by LodestarFactory.
contract Lodestar is ILodestar, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant SWAP_FEE_BPS = 100; // Ascend's 1% pool fee
    uint256 public constant MAX_SLIPPAGE_BPS = 2_000;
    uint64 public constant TIMELOCK = 72 hours;
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
    event ConfigProposed(Config config, uint64 eta);
    event ConfigExecuted(Config config);
    event ConfigCancelled();
    event CreatorRoleLocked(uint64 until);
    event CreatorTransferOutStarted(address next);
    event ListingEnrolled(uint256 cap);
    event ListingClosed();
    event StewardTransferred(address indexed previous, address indexed next);

    error AlreadyInitialized();
    error OnlyFactory();
    error OnlySteward();
    error InvalidConfig();
    error NoPendingConfig();
    error TimelockActive();
    error CreatorNotPending();
    error CreatorRoleIsLocked();
    error NotExtending();
    error ZeroAddress();

    constructor() {
        _initialized = true; // the implementation itself can never be initialized
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert OnlyFactory();
        _;
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

    /// @notice Second half of Ascend's two-step creator handover. The dev must have called
    /// `transferCreator(poolId, thisLodestar)` on Ascend first.
    function acceptCreator() external onlyFactory {
        if (launchpad.pendingCreator(poolId) != address(this)) revert CreatorNotPending();
        launchpad.acceptCreator(poolId);
    }

    // ================================================================ routing (anyone)

    /// @notice Collect and claim this token's creator fees from Ascend and route everything this
    /// router holds. Permissionless: the buyback is priced against Ascend's on-chain EMA, so a
    /// manipulated spot price only makes the buyback wait in reserve.
    function distribute() external nonReentrant {
        try launchpad.collect(poolId) {} catch {
            emit CollectFailed(); // Ascend's keeper may have collected already
        }
        launchpad.claim(poolId);

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
        uint256 q = quote.balanceOf(address(this)) - buybackReserve;
        uint256 burnQ = q * c.burnBps / BPS;
        uint256 holdQ = q * c.holdersBps / BPS;
        uint256 treasQ = q - burnQ - holdQ;

        uint256 buyAmt = burnQ + buybackReserve;
        uint256 bought;
        uint256 spent;
        if (buyAmt > 0) {
            if (c.swapper == address(0)) {
                buybackReserve = buyAmt;
            } else {
                uint256 minOut = quoteMinOut(buyAmt, c.maxSlippageBps);
                quote.forceApprove(c.swapper, buyAmt);
                try IBuybackSwapper(c.swapper).buyExactIn(poolId, buyAmt, minOut, DEAD) returns (uint256 out) {
                    bought = out;
                    spent = buyAmt;
                    buybackReserve = 0;
                    totalBuybackQuote += buyAmt;
                    totalBuybackTokensBurned += out;
                } catch {
                    buybackReserve = buyAmt;
                    emit BuybackSkipped(buyAmt, minOut);
                }
                quote.forceApprove(c.swapper, 0);
            }
        }

        if (holdQ > 0) {
            quote.forceApprove(address(exile), holdQ);
            exile.notifyReward(exilePoolId, holdQ);
            totalHoldersQuote += holdQ;
        }
        if (treasQ > 0) {
            quote.forceApprove(address(sandfall), treasQ);
            sandfall.topUp(treasuryStreamId, uint128(treasQ));
            totalTreasuryQuote += treasQ;
        }

        lastDistributeAt = uint64(block.timestamp);
        emit Distributed(t, q, spent, bought, holdQ, treasQ);
    }

    /// @notice Minimum tokens to accept when buying with `quoteIn`, from Ascend's EMA price minus the
    /// pool fee and the slippage allowance.
    function quoteMinOut(uint256 quoteIn, uint256 slippageBps) public view returns (uint256) {
        uint256 sp = launchpad.emaSqrtPrice(poolId);
        if (sp == 0) (sp,,,) = poolManager.getSlot0(poolId);
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
    /// Can only be extended.
    function lockCreatorRole(uint64 until) external onlyStewardOrFactory {
        if (until <= creatorLockedUntil || until <= block.timestamp) revert NotExtending();
        creatorLockedUntil = until;
        emit CreatorRoleLocked(until);
    }

    /// @notice Start handing the Ascend creator role to `next` (0 cancels). Blocked while locked.
    function transferCreatorOut(address next) external onlySteward {
        if (block.timestamp < creatorLockedUntil) revert CreatorRoleIsLocked();
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
        quoteTotal = quote.balanceOf(address(this)) - buybackReserve + launchpad.creatorOwedQuote(poolId);
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
        if (c.maxSlippageBps > MAX_SLIPPAGE_BPS) revert InvalidConfig();
    }

    function _tryTransfer(IERC20 asset, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory ret) = address(asset).call(abi.encodeCall(IERC20.transfer, (to, amount)));
        return ok && (ret.length == 0 || abi.decode(ret, (bool)));
    }
}
