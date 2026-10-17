// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AscendPoolKey} from "../src/libraries/AscendPoolKey.sol";
import {PoolKey} from "../src/interfaces/IInfinity.sol";

contract AscendPoolKeyTest is Test {
    address internal constant LAUNCHPAD = 0xE2f6254508DEB93Da081837F545e0bAF7b00d8E9;
    address internal constant POOL_MANAGER = 0x12E84206cB53aE0df055482ebc4658635096E1aA;
    address internal constant USDC = 0x4b4fb5C5794F0c821464956374cC5872D5F0f140;
    address internal constant TOKEN = 0x409FEE45BCf411A8c09275084bA5564F77366106;

    /// @dev A real launch on Elysium testnet: this token + Mock USDC produced this pool id.
    function test_knownTestnetPoolId() public pure {
        bytes32 id = AscendPoolKey.id(TOKEN, USDC, LAUNCHPAD, POOL_MANAGER);
        assertEq(id, 0xc7a1ccedf8829a89ab4443149cf022074586f93a49ff6729c3d06951ed181b58);
    }

    function test_sortsCurrencies() public pure {
        PoolKey memory a = AscendPoolKey.key(TOKEN, USDC, LAUNCHPAD, POOL_MANAGER);
        PoolKey memory b = AscendPoolKey.key(USDC, TOKEN, LAUNCHPAD, POOL_MANAGER);
        assertEq(a.currency0, TOKEN); // 0x409F.. sorts below 0x4b4f..
        assertEq(a.currency1, USDC);
        assertEq(AscendPoolKey.toId(a), AscendPoolKey.toId(b));
    }

    function test_keyFields() public pure {
        PoolKey memory k = AscendPoolKey.key(TOKEN, USDC, LAUNCHPAD, POOL_MANAGER);
        assertEq(k.hooks, LAUNCHPAD);
        assertEq(k.poolManager, POOL_MANAGER);
        assertEq(uint256(k.fee), 0x800000);
        assertEq(k.parameters, bytes32(uint256(0xC80445)));
    }
}
