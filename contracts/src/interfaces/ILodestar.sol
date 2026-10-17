// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILodestar {
    /// @notice How a Lodestar splits the quote side of its creator fees. Basis points sum to 10_000.
    struct Config {
        uint16 burnBps; // buy back the token and burn it
        uint16 holdersBps; // Exile holder rewards
        uint16 treasuryBps; // Team Treasury, streamed through Sandfall
        address swapper; // buyback route; 0 = keep the buyback share in reserve
        uint16 maxSlippageBps; // vs Ascend's on-chain EMA price, on top of the 1% pool fee
    }

    struct InitParams {
        address launchpad;
        address desk;
        address poolManager;
        address exile;
        address sandfall;
        bytes32 poolId;
        address token;
        address quote;
        bool tokenIs0;
        uint256 exilePoolId;
        uint256 treasuryStreamId;
        address steward;
        Config config;
    }

    function initialize(InitParams calldata p) external;
    function acceptCreator() external;
    function enrollListing(uint256 cap) external;
    function lockCreatorRole(uint64 until) external;
    function distribute() external;
}
