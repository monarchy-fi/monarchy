// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IExile} from "./interfaces/IExile.sol";

/// @title Exile
/// @notice Time locks for ERC-20s (including v2 LP tokens), ERC-721s and ERC-1155s, plus tiered
/// holder rewards for ERC-20 locks.
///
/// Locks can be extended but never shortened, cancelled or transferred. No fees.
///
/// Rewards: a reward pool is attached to one stake token. Each lock earns points =
/// amount x tier multiplier, where the tier is picked by lock length. Deposits from
/// `notifyReward` drip out evenly over 3 days and are shared every second by points, so
/// locking right before a payout only catches a sliver of it. A lock stops earning exactly at
/// its unlock time: unlock times are rounded up to the hour, points expiring in each hour are
/// tracked in a bucket, and the pool removes them as it passes each hour boundary.
contract Exile is IExile, ReentrancyGuard, IERC721Receiver, IERC1155Receiver {
    using SafeERC20 for IERC20;

    enum Kind {
        ERC20,
        ERC721,
        ERC1155
    }

    struct Pool {
        address stakeToken;
        address rewardToken;
        address admin;
        uint64 tiersEta;
        uint64 periodFinish;
        uint64 lastUpdate;
        uint64 cursor; // last processed hour boundary
        uint256 totalPoints;
        uint256 rewardPerPoint; // scaled by ACC_PREC * RATE_PREC
        uint256 rewardRate; // reward units per second, scaled by RATE_PREC
        uint256 unallocated; // dripped while nobody was locked, scaled by RATE_PREC
        uint256 totalDistributed;
        Tier[] tiers;
        Tier[] pendingTiers;
        mapping(uint64 => uint256) pointsExpiring;
        mapping(uint64 => uint256) rppAtBucket;
    }

    struct Lock {
        address owner;
        Kind kind;
        bool withdrawn;
        uint16 multiplierBps;
        uint64 createdAt;
        uint64 unlockAt;
        address asset;
        uint256 tokenId;
        uint256 amount;
        uint256 poolId; // 0 = no rewards
        uint256 points;
        uint256 rewardPerPointPaid;
        uint256 rewardsAccrued;
    }

    struct PoolView {
        address stakeToken;
        address rewardToken;
        address admin;
        uint256 totalPoints;
        uint256 rewardRate;
        uint64 periodFinish;
        uint64 tiersEta;
        uint256 totalDistributed;
        Tier[] tiers;
        Tier[] pendingTiers;
    }

    uint64 public constant BUCKET = 1 hours;
    uint64 public constant DRIP = 3 days;
    uint64 public constant TIMELOCK = 12 hours;
    /// @dev A ready tier change must be executed within this window, or proposed again.
    uint64 public constant EXECUTION_WINDOW = 7 days;
    uint256 public constant MAX_BUCKETS_PER_CALL = 720;
    uint256 public constant MAX_TIERS = 8;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant RATE_PREC = 1e18;
    uint256 internal constant ACC_PREC = 1e18;

    uint256 public poolCount;
    mapping(uint256 => Pool) internal _pools;
    mapping(address => uint256[]) internal _poolsOf;

    uint256 public lockCount;
    mapping(uint256 => Lock) internal _locks;
    mapping(address => uint256[]) internal _lockIdsOf;

    bool internal _pulling;

    event PoolCreated(uint256 indexed poolId, address indexed stakeToken, address rewardToken, address admin);
    event Locked(
        uint256 indexed lockId,
        address indexed owner,
        Kind kind,
        address indexed asset,
        uint256 tokenId,
        uint256 amount,
        uint64 unlockAt,
        uint256 poolId,
        uint16 multiplierBps,
        uint256 points
    );
    event Extended(uint256 indexed lockId, uint64 oldUnlockAt, uint64 newUnlockAt, uint16 multiplierBps, uint256 points);
    event Withdrawn(uint256 indexed lockId, address indexed owner);
    event RewardAdded(uint256 indexed poolId, address indexed from, uint256 amount, uint256 rewardRate, uint64 periodFinish);
    event RewardsClaimed(uint256 indexed lockId, address indexed owner, uint256 amount);
    event TiersProposed(uint256 indexed poolId, uint64 eta);
    event TiersExecuted(uint256 indexed poolId);
    event TiersCancelled(uint256 indexed poolId);

    error UnknownPool();
    error UnknownLock();
    error InvalidTiers();
    error InvalidAmount();
    error InvalidUnlock();
    error WrongStakeToken();
    error NotOwner();
    error NotAdmin();
    error StillLocked();
    error AlreadyWithdrawn();
    error NotExtending();
    error NoPendingTiers();
    error TimelockActive();
    error PoolNeedsPoke();
    error ProposalExpired();
    error UnexpectedNFT();

    // ================================================================ pools

    /// @inheritdoc IExile
    function createPool(address stakeToken, address rewardToken, Tier[] calldata tiers, address admin)
        external
        returns (uint256 poolId)
    {
        if (stakeToken == address(0) || rewardToken == address(0) || admin == address(0)) revert InvalidTiers();
        _validateTiers(tiers);
        poolId = ++poolCount;
        Pool storage p = _pools[poolId];
        p.stakeToken = stakeToken;
        p.rewardToken = rewardToken;
        p.admin = admin;
        p.cursor = _floorBucket(block.timestamp);
        p.lastUpdate = uint64(block.timestamp);
        p.periodFinish = uint64(block.timestamp);
        for (uint256 i; i < tiers.length; ++i) {
            p.tiers.push(tiers[i]);
        }
        _poolsOf[stakeToken].push(poolId);
        emit PoolCreated(poolId, stakeToken, rewardToken, admin);
    }

    /// @inheritdoc IExile
    function notifyReward(uint256 poolId, uint256 amount) external nonReentrant {
        Pool storage p = _pool(poolId);
        if (amount == 0) revert InvalidAmount();
        // Uncapped so a long-idle pool never blocks Lodestar's distribute; the caller pays the catch-up gas.
        _updatePool(p, type(uint256).max, true);

        IERC20 rt = IERC20(p.rewardToken);
        uint256 before = rt.balanceOf(address(this));
        rt.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = rt.balanceOf(address(this)) - before;

        // The new end is weighted by amount: what is still dripping keeps its remaining time, while the
        // payout and anything that dripped with nobody locked get a full 3 days. Dust barely moves the
        // end, splitting a payout changes nothing, and the empty-pool carry can't be squeezed into the
        // last seconds of a drip.
        uint256 left = p.periodFinish > block.timestamp ? p.periodFinish - block.timestamp : 0;
        uint256 leftover = p.rewardRate * left;
        uint256 fresh = received * RATE_PREC + p.unallocated;
        uint256 total = leftover + fresh;
        uint256 duration = total == 0 ? DRIP : (leftover * left + fresh * DRIP) / total;
        if (duration == 0) duration = 1;
        p.rewardRate = total / duration;
        p.periodFinish = uint64(block.timestamp + duration);
        p.unallocated = 0;
        p.totalDistributed += received;
        emit RewardAdded(poolId, msg.sender, received, p.rewardRate, p.periodFinish);
    }

    /// @notice Process up to `maxBuckets` hour boundaries for a pool that has been idle a long time.
    function poke(uint256 poolId, uint256 maxBuckets) external returns (bool caughtUp) {
        return _updatePool(_pool(poolId), maxBuckets, false);
    }

    function proposeTiers(uint256 poolId, Tier[] calldata tiers) external {
        Pool storage p = _pool(poolId);
        if (msg.sender != p.admin) revert NotAdmin();
        _validateTiers(tiers);
        delete p.pendingTiers;
        for (uint256 i; i < tiers.length; ++i) {
            p.pendingTiers.push(tiers[i]);
        }
        p.tiersEta = uint64(block.timestamp + TIMELOCK);
        emit TiersProposed(poolId, p.tiersEta);
    }

    function executeTiers(uint256 poolId) external {
        Pool storage p = _pool(poolId);
        if (p.tiersEta == 0) revert NoPendingTiers();
        if (block.timestamp < p.tiersEta) revert TimelockActive();
        if (block.timestamp > p.tiersEta + EXECUTION_WINDOW) revert ProposalExpired();
        delete p.tiers;
        for (uint256 i; i < p.pendingTiers.length; ++i) {
            p.tiers.push(p.pendingTiers[i]);
        }
        delete p.pendingTiers;
        p.tiersEta = 0;
        emit TiersExecuted(poolId);
    }

    function cancelTiers(uint256 poolId) external {
        Pool storage p = _pool(poolId);
        if (msg.sender != p.admin) revert NotAdmin();
        if (p.tiersEta == 0) revert NoPendingTiers();
        delete p.pendingTiers;
        p.tiersEta = 0;
        emit TiersCancelled(poolId);
    }

    // ================================================================ locks

    /// @notice Lock ERC-20 tokens until `unlockAt` (rounded up to the hour). Pass a reward pool id to earn
    /// that pool's rewards, or 0 for a plain lock.
    function lockERC20(address asset, uint256 amount, uint64 unlockAt, uint256 poolId)
        external
        nonReentrant
        returns (uint256 lockId)
    {
        if (amount == 0) revert InvalidAmount();
        if (unlockAt <= block.timestamp) revert InvalidUnlock();
        if (poolId != 0 && _pool(poolId).stakeToken != asset) revert WrongStakeToken();

        IERC20 token = IERC20(asset);
        uint256 before = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - before;
        if (received == 0) revert InvalidAmount();

        lockId = _newLock(Kind.ERC20, asset, 0, received, unlockAt);
        Lock storage l = _locks[lockId];
        if (poolId != 0) {
            // A lock shorter than the first tier joins the pool with zero points, so extending it
            // later can still earn.
            Pool storage p = _pools[poolId];
            _updatePool(p, MAX_BUCKETS_PER_CALL, true);
            uint16 mult = _tierMultiplier(p.tiers, unlockAt - block.timestamp);
            l.poolId = poolId;
            l.multiplierBps = mult;
            l.points = received * mult / BPS;
            l.rewardPerPointPaid = p.rewardPerPoint;
            p.totalPoints += l.points;
            p.pointsExpiring[l.unlockAt] += l.points;
        }
        emit Locked(lockId, msg.sender, Kind.ERC20, asset, 0, received, l.unlockAt, l.poolId, l.multiplierBps, l.points);
    }

    function lockERC721(address asset, uint256 tokenId, uint64 unlockAt) external nonReentrant returns (uint256 lockId) {
        if (unlockAt <= block.timestamp) revert InvalidUnlock();
        _pulling = true;
        IERC721(asset).safeTransferFrom(msg.sender, address(this), tokenId);
        _pulling = false;
        lockId = _newLock(Kind.ERC721, asset, tokenId, 1, unlockAt);
        emit Locked(lockId, msg.sender, Kind.ERC721, asset, tokenId, 1, _locks[lockId].unlockAt, 0, 0, 0);
    }

    function lockERC1155(address asset, uint256 id, uint256 amount, uint64 unlockAt)
        external
        nonReentrant
        returns (uint256 lockId)
    {
        if (amount == 0) revert InvalidAmount();
        if (unlockAt <= block.timestamp) revert InvalidUnlock();
        _pulling = true;
        IERC1155(asset).safeTransferFrom(msg.sender, address(this), id, amount, "");
        _pulling = false;
        lockId = _newLock(Kind.ERC1155, asset, id, amount, unlockAt);
        emit Locked(lockId, msg.sender, Kind.ERC1155, asset, id, amount, _locks[lockId].unlockAt, 0, 0, 0);
    }

    /// @notice Push the unlock time later. The lock is re-tiered from now to the new unlock time, so the
    /// multiplier always matches what is still committed: keeping Monarch means keeping 30 days ahead,
    /// and a past long lock can't hold 3x through one-hour extensions.
    function extend(uint256 lockId, uint64 newUnlockAt) external nonReentrant {
        Lock storage l = _lock(lockId);
        if (msg.sender != l.owner) revert NotOwner();
        if (l.withdrawn) revert AlreadyWithdrawn();
        uint64 rounded = _ceilBucket(newUnlockAt);
        if (newUnlockAt <= block.timestamp || rounded <= l.unlockAt) revert NotExtending();
        uint64 oldUnlock = l.unlockAt;

        if (l.poolId != 0) {
            Pool storage p = _pools[l.poolId];
            _settle(p, l);
            if (oldUnlock > p.cursor) {
                // points still live: move them out of the old bucket
                p.pointsExpiring[oldUnlock] -= l.points;
                p.totalPoints -= l.points;
            }
            uint16 tierMult = _tierMultiplier(p.tiers, newUnlockAt - block.timestamp);
            l.multiplierBps = tierMult;
            l.points = l.amount * l.multiplierBps / BPS;
            l.unlockAt = rounded;
            l.rewardPerPointPaid = p.rewardPerPoint;
            p.totalPoints += l.points;
            p.pointsExpiring[rounded] += l.points;
        } else {
            l.unlockAt = rounded;
        }
        emit Extended(lockId, oldUnlock, rounded, l.multiplierBps, l.points);
    }

    function withdraw(uint256 lockId) external nonReentrant {
        Lock storage l = _lock(lockId);
        if (msg.sender != l.owner) revert NotOwner();
        if (l.withdrawn) revert AlreadyWithdrawn();
        if (block.timestamp < l.unlockAt) revert StillLocked();
        if (l.poolId != 0) _settle(_pools[l.poolId], l);
        l.withdrawn = true;

        if (l.kind == Kind.ERC20) {
            IERC20(l.asset).safeTransfer(l.owner, l.amount);
        } else if (l.kind == Kind.ERC721) {
            IERC721(l.asset).transferFrom(address(this), l.owner, l.tokenId);
        } else {
            IERC1155(l.asset).safeTransferFrom(address(this), l.owner, l.tokenId, l.amount, "");
        }
        emit Withdrawn(lockId, l.owner);
    }

    function claimRewards(uint256 lockId) public nonReentrant returns (uint256 amount) {
        amount = _claim(lockId);
    }

    function claimRewardsBatch(uint256[] calldata lockIds) external nonReentrant returns (uint256 total) {
        for (uint256 i; i < lockIds.length; ++i) {
            total += _claim(lockIds[i]);
        }
    }

    // ================================================================ views

    /// @notice Rewards a lock could claim right now, including anything not yet checkpointed.
    function pendingRewards(uint256 lockId) external view returns (uint256) {
        Lock storage l = _lock(lockId);
        if (l.poolId == 0) return 0;
        (uint256 rppNow, uint256 rppAtUnlock, bool unlockReached) = _simulate(_pools[l.poolId], l.unlockAt);
        uint256 end = unlockReached ? rppAtUnlock : rppNow;
        return l.rewardsAccrued + _earned(l.points, end, l.rewardPerPointPaid);
    }

    /// @notice Current reward flow to a lock, in reward units per second scaled by 1e18. Used for the
    /// ticking counter in the UI.
    function earningRatePerSecond(uint256 lockId) external view returns (uint256) {
        Lock storage l = _lock(lockId);
        if (l.poolId == 0 || l.withdrawn || block.timestamp >= l.unlockAt) return 0;
        Pool storage p = _pools[l.poolId];
        if (block.timestamp >= p.periodFinish) return 0;
        (,,, uint256 totalPoints) = _simulateFull(p, 0);
        if (totalPoints == 0) return 0;
        return Math.mulDiv(l.points, p.rewardRate, totalPoints);
    }

    function tierFor(uint256 poolId, uint256 duration) external view returns (uint16 multiplierBps, bytes32 label) {
        Tier[] storage tiers = _pool(poolId).tiers;
        for (uint256 i = tiers.length; i > 0; --i) {
            if (tiers[i - 1].minDuration <= duration) return (tiers[i - 1].multiplierBps, tiers[i - 1].label);
        }
        return (0, bytes32(0));
    }

    function poolInfo(uint256 poolId) external view returns (PoolView memory v) {
        Pool storage p = _pool(poolId);
        (,,, uint256 totalPoints) = _simulateFull(p, 0);
        v.stakeToken = p.stakeToken;
        v.rewardToken = p.rewardToken;
        v.admin = p.admin;
        v.totalPoints = totalPoints;
        v.rewardRate = block.timestamp < p.periodFinish ? p.rewardRate : 0;
        v.periodFinish = p.periodFinish;
        v.tiersEta = p.tiersEta;
        v.totalDistributed = p.totalDistributed;
        v.tiers = p.tiers;
        v.pendingTiers = p.pendingTiers;
    }

    function lockInfo(uint256 lockId) external view returns (Lock memory) {
        return _lock(lockId);
    }

    function lockIdsOf(address owner) external view returns (uint256[] memory) {
        return _lockIdsOf[owner];
    }

    function poolsOf(address stakeToken) external view returns (uint256[] memory) {
        return _poolsOf[stakeToken];
    }

    // ================================================================ receivers

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (!_pulling) revert UnexpectedNFT();
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external view returns (bytes4) {
        if (!_pulling) revert UnexpectedNFT();
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert UnexpectedNFT();
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    // ================================================================ internals

    function _newLock(Kind kind, address asset, uint256 tokenId, uint256 amount, uint64 unlockAt)
        internal
        returns (uint256 lockId)
    {
        lockId = ++lockCount;
        Lock storage l = _locks[lockId];
        l.owner = msg.sender;
        l.kind = kind;
        l.asset = asset;
        l.tokenId = tokenId;
        l.amount = amount;
        l.createdAt = uint64(block.timestamp);
        l.unlockAt = _ceilBucket(unlockAt);
        _lockIdsOf[msg.sender].push(lockId);
    }

    function _claim(uint256 lockId) internal returns (uint256 amount) {
        Lock storage l = _lock(lockId);
        if (msg.sender != l.owner) revert NotOwner();
        if (l.poolId == 0) return 0;
        Pool storage p = _pools[l.poolId];
        _settle(p, l);
        amount = l.rewardsAccrued;
        if (amount == 0) return 0;
        l.rewardsAccrued = 0;
        IERC20(p.rewardToken).safeTransfer(l.owner, amount);
        emit RewardsClaimed(lockId, l.owner, amount);
    }

    function _settle(Pool storage p, Lock storage l) internal {
        _updatePool(p, MAX_BUCKETS_PER_CALL, true);
        uint256 end = l.unlockAt <= p.cursor ? p.rppAtBucket[l.unlockAt] : p.rewardPerPoint;
        if (end > l.rewardPerPointPaid) {
            l.rewardsAccrued += _earned(l.points, end, l.rewardPerPointPaid);
            l.rewardPerPointPaid = end;
        }
    }

    function _earned(uint256 points, uint256 rppEnd, uint256 rppPaid) internal pure returns (uint256) {
        if (rppEnd <= rppPaid) return 0;
        return Math.mulDiv(points, rppEnd - rppPaid, ACC_PREC * RATE_PREC);
    }

    /// @dev Walk every hour boundary since the last update, accruing rewards up to each boundary and then
    /// removing the points that expire there. Returns false if it stopped early at `maxBuckets`.
    function _updatePool(Pool storage p, uint256 maxBuckets, bool revertIfBehind) internal returns (bool) {
        uint64 b = p.cursor + BUCKET;
        uint256 n;
        while (b <= block.timestamp) {
            if (n == maxBuckets) {
                if (revertIfBehind) revert PoolNeedsPoke();
                return false;
            }
            _accrue(p, p.lastUpdate, b);
            p.lastUpdate = b;
            uint256 expiring = p.pointsExpiring[b];
            if (expiring != 0) {
                p.rppAtBucket[b] = p.rewardPerPoint;
                p.totalPoints -= expiring;
                delete p.pointsExpiring[b];
            }
            p.cursor = b;
            b += BUCKET;
            ++n;
        }
        _accrue(p, p.lastUpdate, uint64(block.timestamp));
        p.lastUpdate = uint64(block.timestamp);
        return true;
    }

    function _accrue(Pool storage p, uint64 from, uint64 to) internal {
        uint256 amt = _dripped(p.rewardRate, p.periodFinish, from, to);
        if (amt == 0) return;
        if (p.totalPoints == 0) {
            p.unallocated += amt;
        } else {
            p.rewardPerPoint += Math.mulDiv(amt, ACC_PREC, p.totalPoints);
        }
    }

    function _dripped(uint256 rate, uint64 periodFinish, uint64 from, uint64 to) internal pure returns (uint256) {
        uint64 a = from < periodFinish ? from : periodFinish;
        uint64 z = to < periodFinish ? to : periodFinish;
        return z > a ? rate * (z - a) : 0;
    }

    /// @dev Read-only replay of `_updatePool`. Also reports the reward-per-point at `unlockAt` if that
    /// boundary is passed during the replay or was already processed.
    function _simulate(Pool storage p, uint64 unlockAt)
        internal
        view
        returns (uint256 rppNow, uint256 rppAtUnlock, bool unlockReached)
    {
        if (unlockAt <= p.cursor) {
            (rppNow,,,) = _simulateFull(p, 0);
            return (rppNow, p.rppAtBucket[unlockAt], true);
        }
        uint256 totalPoints;
        (rppNow, rppAtUnlock, unlockReached, totalPoints) = _simulateFull(p, unlockAt);
    }

    function _simulateFull(Pool storage p, uint64 watch)
        internal
        view
        returns (uint256 rpp, uint256 rppAtWatch, bool watchReached, uint256 totalPoints)
    {
        rpp = p.rewardPerPoint;
        totalPoints = p.totalPoints;
        uint64 last = p.lastUpdate;
        uint64 b = p.cursor + BUCKET;
        while (b <= block.timestamp) {
            uint256 amt = _dripped(p.rewardRate, p.periodFinish, last, b);
            if (amt != 0 && totalPoints != 0) rpp += Math.mulDiv(amt, ACC_PREC, totalPoints);
            last = b;
            if (b == watch) {
                rppAtWatch = rpp;
                watchReached = true;
            }
            totalPoints -= p.pointsExpiring[b];
            b += BUCKET;
        }
        uint256 tail = _dripped(p.rewardRate, p.periodFinish, last, uint64(block.timestamp));
        if (tail != 0 && totalPoints != 0) rpp += Math.mulDiv(tail, ACC_PREC, totalPoints);
    }

    function _tierMultiplier(Tier[] storage tiers, uint256 duration) internal view returns (uint16) {
        for (uint256 i = tiers.length; i > 0; --i) {
            if (tiers[i - 1].minDuration <= duration) return tiers[i - 1].multiplierBps;
        }
        return 0;
    }

    function _validateTiers(Tier[] calldata tiers) internal pure {
        if (tiers.length == 0 || tiers.length > MAX_TIERS) revert InvalidTiers();
        for (uint256 i; i < tiers.length; ++i) {
            if (tiers[i].multiplierBps == 0 || tiers[i].minDuration == 0) revert InvalidTiers();
            // longer locks never earn a lower multiplier than shorter ones
            if (
                i > 0
                    && (tiers[i].minDuration <= tiers[i - 1].minDuration
                        || tiers[i].multiplierBps < tiers[i - 1].multiplierBps)
            ) revert InvalidTiers();
        }
    }

    function _pool(uint256 poolId) internal view returns (Pool storage p) {
        if (poolId == 0 || poolId > poolCount) revert UnknownPool();
        p = _pools[poolId];
    }

    function _lock(uint256 lockId) internal view returns (Lock storage l) {
        if (lockId == 0 || lockId > lockCount) revert UnknownLock();
        l = _locks[lockId];
    }

    function _floorBucket(uint256 t) internal pure returns (uint64) {
        return uint64(t - (t % BUCKET));
    }

    /// @dev Reverts instead of wrapping: an unlock time near uint64 max must not round into the past.
    function _ceilBucket(uint256 t) internal pure returns (uint64) {
        uint256 r = t % BUCKET;
        uint256 c = r == 0 ? t : t + BUCKET - r;
        if (c > type(uint64).max) revert InvalidUnlock();
        return uint64(c);
    }
}
