// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseScript} from "./Base.s.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockAscendPool} from "../src/mocks/MockAscendPool.sol";
import {MockAscendLaunchpad} from "../src/mocks/MockAscendLaunchpad.sol";
import {MockListingDesk} from "../src/mocks/MockListingDesk.sol";

/// @notice Mock Ascend (launchpad, listing desk, Infinity vault/pool manager) and a 6-decimal Mock USDC,
/// for anvil or as a testnet fallback. Run DeployCore with ASCEND_MODE=mock afterwards.
contract DeployMocks is BaseScript {
    function run() external {
        vm.startBroadcast(_deployerKey());
        MockAscendPool pool = new MockAscendPool();
        MockAscendLaunchpad launchpad = new MockAscendLaunchpad(pool);
        MockListingDesk desk = new MockListingDesk(launchpad);
        MockERC20 usdc = new MockERC20("Mock USDC", "USDC", 6);
        vm.stopBroadcast();

        Deployment memory d;
        d.mode = "mock";
        d.launchpad = address(launchpad);
        d.desk = address(desk);
        d.poolManager = address(pool);
        d.vault = address(pool);
        d.quote = address(usdc);
        d.startBlock = block.number;
        _save(d);
    }
}
