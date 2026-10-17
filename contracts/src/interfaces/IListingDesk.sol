// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice The subset of Ascend's ListingDesk (the HyperCore listing set-aside) that Monarchy uses.
interface IListingDesk {
    function register(address token, address quote) external returns (bytes32 poolId);
    function enroll(address token, address quote, uint256 cap) external;
    function close(bytes32 poolId) external;
    function withdraw(bytes32 poolId, uint256 amount) external;
    function splitCoreFees(address token) external;
    function poolOf(address token) external view returns (bytes32);
}
