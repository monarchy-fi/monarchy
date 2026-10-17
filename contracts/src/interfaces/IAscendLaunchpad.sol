// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice The subset of Ascend's launchpad (Elysium testnet 0xE2f6...d8E9) that Monarchy uses.
/// Ascend declares `PoolId` as a bytes32 user-defined type, so plain bytes32 is ABI compatible.
interface IAscendLaunchpad {
    function collect(bytes32 poolId) external returns (uint256 flywheelQuote);
    function claim(bytes32 poolId) external;
    function claimToken(bytes32 poolId) external;
    function claimQuote(bytes32 poolId) external;
    function transferCreator(bytes32 poolId, address next) external;
    function acceptCreator(bytes32 poolId) external;

    function poolCreator(bytes32 poolId) external view returns (address);
    function pendingCreator(bytes32 poolId) external view returns (address);
    function poolTokenIs0(bytes32 poolId) external view returns (bool);
    function emaSqrtPrice(bytes32 poolId) external view returns (uint160);
    function creatorOwedToken(bytes32 poolId) external view returns (uint256);
    function creatorOwedQuote(bytes32 poolId) external view returns (uint256);
    function listingElection(bytes32 poolId) external view returns (uint256);
    function listingOwed(bytes32 poolId) external view returns (uint256);
    function listingDesk() external view returns (address);
}
