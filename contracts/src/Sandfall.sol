// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Sandfall
/// @notice Vesting streams for ERC-20 tokens or native HYPE. No fees.
/// - FIXED_LINEAR: optional cliff, then a straight line to `end`.
/// - FIXED_STEPS: optional cliff, then equal steps every `stepSeconds` (e.g. monthly).
/// - ROLLING: starts empty and can be topped up by anyone; each top-up re-streams the unvested
///   balance over `window`. Lodestar uses this for a project's Team Treasury.
/// Whether a stream can be cancelled is chosen at creation and can never change.
/// Streams are not transferable.
contract Sandfall is ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Kind {
        FIXED_LINEAR,
        FIXED_STEPS,
        ROLLING
    }

    struct Stream {
        address creator;
        address recipient;
        address asset; // address(0) = native HYPE
        Kind kind;
        bool cancellable;
        bool cancelled;
        uint64 start;
        uint64 cliff;
        uint64 end;
        uint32 stepSeconds;
        uint32 window;
        uint128 total;
        uint128 claimed;
        // rolling only
        uint128 accrued;
        uint64 lastUpdate;
        uint64 periodFinish;
        uint256 rate; // 1e18-scaled units per second
    }

    uint256 internal constant RATE_PREC = 1e18;
    uint32 public constant MIN_WINDOW = 1 days;
    uint32 public constant MAX_WINDOW = 365 days;

    Stream[] internal _streams;
    mapping(address => uint256[]) internal _streamsOf;
    mapping(address => uint256[]) internal _createdBy;

    event StreamCreated(
        uint256 indexed id,
        Kind kind,
        address indexed creator,
        address indexed recipient,
        address asset,
        uint256 amount,
        uint64 start,
        uint64 cliff,
        uint64 end,
        uint32 stepSeconds,
        uint32 window,
        bool cancellable
    );
    event ToppedUp(uint256 indexed id, address indexed from, uint256 amount, uint256 rate, uint64 periodFinish);
    event Claimed(uint256 indexed id, address indexed recipient, uint256 amount);
    event Cancelled(uint256 indexed id, uint256 toRecipient, uint256 toCreator);

    error InvalidSchedule();
    error InvalidAmount();
    error InvalidRecipient();
    error InvalidWindow();
    error WrongValue();
    error NotRecipient();
    error NotCreator();
    error NotCancellable();
    error AlreadyCancelled();
    error NotRolling();
    error UnknownStream();
    error NativeTransferFailed();

    constructor() {
        _streams.push(); // index 0 unused so 0 can mean "no stream"
    }

    // ---------------------------------------------------------------- create

    /// @param stepSeconds 0 for linear, otherwise the length of each step (30 days for monthly).
    function createFixed(
        address asset,
        address recipient,
        uint128 amount,
        uint64 start,
        uint64 cliff,
        uint64 end,
        uint32 stepSeconds,
        bool cancellable
    ) external payable nonReentrant returns (uint256 id) {
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        if (!(start <= cliff && cliff < end)) revert InvalidSchedule();

        uint128 received = _pull(asset, amount);

        id = _streams.length;
        Stream storage s = _streams.push();
        s.creator = msg.sender;
        s.recipient = recipient;
        s.asset = asset;
        s.kind = stepSeconds == 0 ? Kind.FIXED_LINEAR : Kind.FIXED_STEPS;
        s.cancellable = cancellable;
        s.start = start;
        s.cliff = cliff;
        s.end = end;
        s.stepSeconds = stepSeconds;
        s.total = received;

        _streamsOf[recipient].push(id);
        _createdBy[msg.sender].push(id);
        emit StreamCreated(
            id, s.kind, msg.sender, recipient, asset, received, start, cliff, end, stepSeconds, 0, cancellable
        );
    }

    /// @notice Create an empty rolling stream. `creator` is who may cancel it (if cancellable);
    /// the Lodestar factory sets it to the Lodestar router.
    function createRolling(address asset, address recipient, uint32 window, address creator, bool cancellable)
        external
        returns (uint256 id)
    {
        if (recipient == address(0) || creator == address(0)) revert InvalidRecipient();
        if (window < MIN_WINDOW || window > MAX_WINDOW) revert InvalidWindow();

        id = _streams.length;
        Stream storage s = _streams.push();
        s.creator = creator;
        s.recipient = recipient;
        s.asset = asset;
        s.kind = Kind.ROLLING;
        s.cancellable = cancellable;
        s.start = uint64(block.timestamp);
        s.window = window;
        s.lastUpdate = uint64(block.timestamp);
        s.periodFinish = uint64(block.timestamp);

        _streamsOf[recipient].push(id);
        _createdBy[creator].push(id);
        emit StreamCreated(id, Kind.ROLLING, creator, recipient, asset, 0, s.start, s.start, 0, 0, window, cancellable);
    }

    /// @notice Add funds to a rolling stream. The unvested balance plus `amount` streams over a fresh window.
    function topUp(uint256 id, uint128 amount) external payable nonReentrant {
        Stream storage s = _get(id);
        if (s.kind != Kind.ROLLING) revert NotRolling();
        if (s.cancelled) revert AlreadyCancelled();
        if (amount == 0) revert InvalidAmount();

        uint128 received = _pull(s.asset, amount);
        _accrueRolling(s);
        uint256 unvested = uint256(s.total) - s.accrued + received;
        s.total += received;
        s.rate = unvested * RATE_PREC / s.window;
        s.periodFinish = uint64(block.timestamp) + s.window;
        emit ToppedUp(id, msg.sender, received, s.rate, s.periodFinish);
    }

    // ---------------------------------------------------------------- claim / cancel

    function claim(uint256 id) external nonReentrant returns (uint256 due) {
        Stream storage s = _get(id);
        if (msg.sender != s.recipient) revert NotRecipient();
        due = _vested(s) - s.claimed;
        if (due == 0) return 0;
        s.claimed += uint128(due);
        _send(s.asset, s.recipient, due);
        emit Claimed(id, s.recipient, due);
    }

    /// @notice Stop a cancellable stream. What has vested goes to the recipient now; the rest returns to the creator.
    function cancel(uint256 id) external nonReentrant {
        Stream storage s = _get(id);
        if (msg.sender != s.creator) revert NotCreator();
        if (!s.cancellable) revert NotCancellable();
        if (s.cancelled) revert AlreadyCancelled();

        uint256 vested = _vested(s);
        uint256 toRecipient = vested - s.claimed;
        uint256 toCreator = uint256(s.total) - vested;

        s.cancelled = true;
        s.total = uint128(vested);
        s.claimed = uint128(vested);
        if (s.kind == Kind.ROLLING) {
            s.accrued = uint128(vested);
            s.rate = 0;
            s.periodFinish = uint64(block.timestamp);
            s.lastUpdate = uint64(block.timestamp);
        }

        if (toRecipient > 0) _send(s.asset, s.recipient, toRecipient);
        if (toCreator > 0) _send(s.asset, s.creator, toCreator);
        emit Cancelled(id, toRecipient, toCreator);
    }

    // ---------------------------------------------------------------- views

    function stream(uint256 id) external view returns (Stream memory) {
        return _get(id);
    }

    function vestedAmount(uint256 id) external view returns (uint256) {
        return _vested(_get(id));
    }

    function claimable(uint256 id) external view returns (uint256) {
        Stream storage s = _get(id);
        return _vested(s) - s.claimed;
    }

    function streamsOf(address recipient) external view returns (uint256[] memory) {
        return _streamsOf[recipient];
    }

    function createdBy(address creator) external view returns (uint256[] memory) {
        return _createdBy[creator];
    }

    function streamCount() external view returns (uint256) {
        return _streams.length - 1;
    }

    // ---------------------------------------------------------------- internals

    function _get(uint256 id) internal view returns (Stream storage s) {
        if (id == 0 || id >= _streams.length) revert UnknownStream();
        s = _streams[id];
    }

    function _vested(Stream storage s) internal view returns (uint256) {
        if (s.cancelled) return s.total;
        uint256 t = block.timestamp;
        if (s.kind == Kind.ROLLING) {
            if (t >= s.periodFinish) return s.total;
            uint256 v = uint256(s.accrued) + s.rate * (t - s.lastUpdate) / RATE_PREC;
            return v > s.total ? s.total : v;
        }
        if (t < s.cliff) return 0;
        if (t >= s.end) return s.total;
        uint256 duration = s.end - s.start;
        if (s.kind == Kind.FIXED_LINEAR) {
            return uint256(s.total) * (t - s.start) / duration;
        }
        uint256 totalPeriods = (duration + s.stepSeconds - 1) / s.stepSeconds;
        uint256 periods = (t - s.start) / s.stepSeconds;
        if (periods > totalPeriods) periods = totalPeriods;
        return uint256(s.total) * periods / totalPeriods;
    }

    function _accrueRolling(Stream storage s) internal {
        s.accrued = uint128(_vested(s));
        s.lastUpdate = uint64(block.timestamp);
    }

    function _pull(address asset, uint128 amount) internal returns (uint128) {
        if (asset == address(0)) {
            if (msg.value != amount) revert WrongValue();
            return amount;
        }
        if (msg.value != 0) revert WrongValue();
        IERC20 token = IERC20(asset);
        uint256 before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - before;
        if (received == 0) revert InvalidAmount();
        return uint128(received);
    }

    function _send(address asset, address to, uint256 amount) internal {
        if (asset == address(0)) {
            (bool ok,) = to.call{value: amount}("");
            if (!ok) revert NativeTransferFailed();
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }
    }
}
