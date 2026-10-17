// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IExile {
    /// @param minDuration shortest lock length (seconds) that qualifies for this tier
    /// @param multiplierBps reward multiplier, 10_000 = 1x
    /// @param label display name, e.g. "Monarch"
    struct Tier {
        uint32 minDuration;
        uint16 multiplierBps;
        bytes32 label;
    }

    /// @notice Start a reward pool for lockers of `stakeToken`, paid in `rewardToken`. Tiers must be
    /// sorted by minDuration ascending. `admin` may change tiers behind a 12 hour timelock.
    function createPool(address stakeToken, address rewardToken, Tier[] calldata tiers, address admin)
        external
        returns (uint256 poolId);

    /// @notice Add rewards to a pool. They drip out over 3 days. Anyone may call.
    function notifyReward(uint256 poolId, uint256 amount) external;

    /// @notice Add rewards paid in the pool's stake token. They drip out over 3 days on the same points,
    /// next to the reward-token stream. Anyone may call.
    function notifyStakeReward(uint256 poolId, uint256 amount) external;

    /// @notice Queue a new tier table (admin only); anyone can execute it after the timelock.
    function proposeTiers(uint256 poolId, Tier[] calldata tiers) external;

    /// @notice Drop a queued tier table (admin only).
    function cancelTiers(uint256 poolId) external;
}
