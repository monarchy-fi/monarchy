// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAscendLaunchpad} from "../interfaces/IAscendLaunchpad.sol";
import {AscendPoolKey} from "../libraries/AscendPoolKey.sol";
import {PoolKey} from "../interfaces/IInfinity.sol";
import {MockERC20} from "./MockERC20.sol";
import {MockAscendPool} from "./MockAscendPool.sol";

/// @notice Stand-in for Ascend's launchpad with the same creator-fee semantics, for tests and anvil:
/// 50% of fees to the creator in both assets, pull-based claim paid to the current creator,
/// two-step creator handover that clears the listing election, and the 20% listing set-aside
/// (with carry and cap) on the creator's quote share.
contract MockAscendLaunchpad is IAscendLaunchpad {
    using SafeERC20 for IERC20;

    struct P {
        address token;
        address quote;
        address creator;
        address pending;
        bool tokenIs0;
        uint256 owedToken;
        uint256 owedQuote;
        uint256 election;
        uint256 listingOwed;
        uint160 emaOverride;
        bool collectReverts;
    }

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;
    uint256 public constant CREATOR_BPS = 5_000;
    address public constant PROTOCOL_SINK = address(0xA5CE9D);

    MockAscendPool public immutable pool;
    address public listingDesk;
    mapping(bytes32 => P) internal _p;

    event Launched(bytes32 indexed poolId, address indexed token, address indexed creator, address quote);
    event Collected(bytes32 indexed poolId, uint256 tokenFees, uint256 quoteFees);
    event CreatorClaimed(bytes32 indexed poolId, address indexed recipient, uint256 token, uint256 quote);
    event CreatorTransferStarted(bytes32 indexed poolId, address next);
    event CreatorTransferred(bytes32 indexed poolId, address newCreator);
    event ListingSetAside(bytes32 indexed poolId, uint256 amount);

    error UnknownPool();
    error Unauthorized();
    error ZeroCreator();
    error CollectFailedMock();

    constructor(MockAscendPool pool_) {
        pool = pool_;
        pool_.setLaunchpad(address(this));
    }

    function setListingDesk(address desk) external {
        require(listingDesk == address(0), "set");
        listingDesk = desk;
    }

    /// @notice Launch a mock token paired with `quote`, seeding the pool with `tokenSeed` tokens and
    /// `quoteSeed` quote (pulled from the caller).
    function launch(string calldata name, string calldata symbol, address quote, address creator, uint256 tokenSeed, uint256 quoteSeed)
        external
        returns (address token, bytes32 poolId)
    {
        if (creator == address(0)) revert ZeroCreator();
        MockERC20 t = new MockERC20(name, symbol, 18);
        token = address(t);
        t.mint(address(this), TOTAL_SUPPLY);
        PoolKey memory key = AscendPoolKey.key(token, quote, address(this), address(pool));
        poolId = AscendPoolKey.toId(key);

        IERC20(token).safeTransfer(address(pool), tokenSeed);
        IERC20(quote).safeTransferFrom(msg.sender, address(pool), quoteSeed);
        bool tokenIs0 = token < quote;
        (uint256 r0, uint256 r1) = tokenIs0 ? (tokenSeed, quoteSeed) : (quoteSeed, tokenSeed);
        pool.initPool(key, r0, r1);

        P storage p = _p[poolId];
        p.token = token;
        p.quote = quote;
        p.creator = creator;
        p.tokenIs0 = tokenIs0;
        emit Launched(poolId, token, creator, quote);
    }

    function collect(bytes32 poolId) external returns (uint256) {
        P storage p = _get(poolId);
        if (p.collectReverts) revert CollectFailedMock();
        (uint256 f0, uint256 f1) = pool.withdrawFees(poolId, address(this));
        (uint256 tf, uint256 qf) = p.tokenIs0 ? (f0, f1) : (f1, f0);
        _book(poolId, p, tf, qf);
        return 0;
    }

    function claim(bytes32 poolId) external {
        _claim(poolId, true, true);
    }

    function claimToken(bytes32 poolId) external {
        _claim(poolId, true, false);
    }

    function claimQuote(bytes32 poolId) external {
        _claim(poolId, false, true);
    }

    function transferCreator(bytes32 poolId, address next) external {
        P storage p = _get(poolId);
        if (msg.sender != p.creator) revert Unauthorized();
        p.pending = next;
        emit CreatorTransferStarted(poolId, next);
    }

    function acceptCreator(bytes32 poolId) external {
        P storage p = _get(poolId);
        if (msg.sender != p.pending || msg.sender == address(0)) revert Unauthorized();
        p.creator = msg.sender;
        delete p.pending;
        delete p.election;
        emit CreatorTransferred(poolId, msg.sender);
    }

    // ------------------------------------------------------------ desk-only

    function setListing(bytes32 poolId, address creator, uint256 cap) external {
        if (msg.sender != listingDesk) revert Unauthorized();
        _get(poolId).election = creator == address(0) ? 0 : (cap << 168) | uint160(creator);
    }

    function takeListing(bytes32 poolId, address to, uint256 amount) external {
        if (msg.sender != listingDesk) revert Unauthorized();
        P storage p = _get(poolId);
        p.listingOwed -= amount;
        IERC20(p.quote).safeTransfer(to, amount);
    }

    // ------------------------------------------------------------ views

    function poolCreator(bytes32 poolId) external view returns (address) {
        return _p[poolId].creator;
    }

    function pendingCreator(bytes32 poolId) external view returns (address) {
        return _p[poolId].pending;
    }

    function poolTokenIs0(bytes32 poolId) external view returns (bool) {
        return _p[poolId].tokenIs0;
    }

    function emaSqrtPrice(bytes32 poolId) external view returns (uint160) {
        P storage p = _get(poolId);
        if (p.emaOverride != 0) return p.emaOverride;
        (uint160 sp,,,) = pool.getSlot0(poolId);
        return sp;
    }

    function creatorOwedToken(bytes32 poolId) external view returns (uint256) {
        return _p[poolId].owedToken;
    }

    function creatorOwedQuote(bytes32 poolId) external view returns (uint256) {
        return _p[poolId].owedQuote;
    }

    function listingElection(bytes32 poolId) external view returns (uint256) {
        return _p[poolId].election;
    }

    function listingOwed(bytes32 poolId) external view returns (uint256) {
        return _p[poolId].listingOwed;
    }

    function tokenOf(bytes32 poolId) external view returns (address) {
        return _p[poolId].token;
    }

    // ------------------------------------------------------------ test cheats

    function setEma(bytes32 poolId, uint160 sqrtPriceX96) external {
        _get(poolId).emaOverride = sqrtPriceX96;
    }

    function setCollectReverts(bytes32 poolId, bool reverts) external {
        _get(poolId).collectReverts = reverts;
    }

    /// @notice Pretend trading produced these fees (both MockERC20s, minted here).
    function injectFees(bytes32 poolId, uint256 tokenFees, uint256 quoteFees) external {
        P storage p = _get(poolId);
        if (tokenFees > 0) MockERC20(p.token).mint(address(pool), tokenFees);
        if (quoteFees > 0) MockERC20(p.quote).mint(address(pool), quoteFees);
        (uint256 f0, uint256 f1) = p.tokenIs0 ? (tokenFees, quoteFees) : (quoteFees, tokenFees);
        pool.addFees(poolId, f0, f1);
    }

    // ------------------------------------------------------------ internals

    function _book(bytes32 poolId, P storage p, uint256 tokenFees, uint256 quoteFees) internal {
        uint256 creatorT = tokenFees * CREATOR_BPS / 10_000;
        uint256 creatorQ = quoteFees * CREATOR_BPS / 10_000;
        uint256 aside = _setAside(poolId, p, creatorQ);
        p.owedToken += creatorT;
        p.owedQuote += creatorQ - aside;
        p.listingOwed += aside;
        if (tokenFees > creatorT) IERC20(p.token).safeTransfer(PROTOCOL_SINK, tokenFees - creatorT);
        if (quoteFees > creatorQ) IERC20(p.quote).safeTransfer(PROTOCOL_SINK, quoteFees - creatorQ);
        emit Collected(poolId, tokenFees, quoteFees);
    }

    /// @dev Mirrors AscendLaunchpad._setAside: floor(gross / 5) with a running carry, clamped to the cap,
    /// only while the enrolled wallet still holds the creator role.
    function _setAside(bytes32 poolId, P storage p, uint256 gross) internal returns (uint256 amount) {
        uint256 e = p.election;
        if (gross == 0 || e == 0 || address(uint160(e)) != p.creator) return 0;
        uint256 remaining = e >> 168;
        if (remaining == 0) return 0;
        uint256 carry = gross % 5 + ((e >> 160) & 0xff);
        amount = gross / 5 + carry / 5;
        carry = carry % 5;
        if (amount >= remaining) {
            amount = remaining;
            carry = 0;
        }
        p.election = ((remaining - amount) << 168) | (carry << 160) | uint160(p.creator);
        emit ListingSetAside(poolId, amount);
    }

    function _claim(bytes32 poolId, bool tokenSide, bool quoteSide) internal {
        P storage p = _get(poolId);
        uint256 t = tokenSide ? p.owedToken : 0;
        uint256 q = quoteSide ? p.owedQuote : 0;
        if (tokenSide) p.owedToken = 0;
        if (quoteSide) p.owedQuote = 0;
        if (t > 0) IERC20(p.token).safeTransfer(p.creator, t);
        if (q > 0) IERC20(p.quote).safeTransfer(p.creator, q);
        emit CreatorClaimed(poolId, p.creator, t, q);
    }

    function _get(bytes32 poolId) internal view returns (P storage p) {
        p = _p[poolId];
        if (p.token == address(0)) revert UnknownPool();
    }
}
