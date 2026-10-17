// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "../interfaces/IInfinity.sol";

/// @notice Rebuilds the pool key and id Ascend uses for every launch.
/// Matches Ascend's LaunchpadKey library: currencies sorted ascending, the launchpad as hook,
/// the dynamic-fee flag, tick spacing 200 and hook bitmap 0x0445.
library AscendPoolKey {
    uint24 internal constant DYNAMIC_FEE_FLAG = 0x800000;
    bytes32 internal constant POOL_PARAMETERS = bytes32(uint256(0xC80445));

    function key(address token, address quote, address launchpad, address poolManager)
        internal
        pure
        returns (PoolKey memory k)
    {
        (address c0, address c1) = token < quote ? (token, quote) : (quote, token);
        k = PoolKey({
            currency0: c0,
            currency1: c1,
            hooks: launchpad,
            poolManager: poolManager,
            fee: DYNAMIC_FEE_FLAG,
            parameters: POOL_PARAMETERS
        });
    }

    function toId(PoolKey memory k) internal pure returns (bytes32) {
        return keccak256(abi.encode(k));
    }

    function id(address token, address quote, address launchpad, address poolManager)
        internal
        pure
        returns (bytes32)
    {
        return toId(key(token, quote, launchpad, poolManager));
    }
}
