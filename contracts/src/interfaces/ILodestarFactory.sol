// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice What a Lodestar reads from the factory that made it, and from a successor factory, to move its
/// creator role to a newer version.
interface ILodestarFactory {
    function successor() external view returns (address);
    function predict(address token, address quote) external view returns (address lodestar, bytes32 poolId);
}
