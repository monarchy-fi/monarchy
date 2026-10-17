// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseScript} from "./Base.s.sol";
import {console2} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockAscendLaunchpad} from "../src/mocks/MockAscendLaunchpad.sol";
import {AscendPoolKey} from "../src/libraries/AscendPoolKey.sol";

/// @notice Launch a token (default MONARCH) and record it in deployments/<chainId>.json.
/// Real mode calls Ascend's launch((name, symbol, quote, devBuyQuote, minDevOut, salt, creator)) with
/// both uints 0 because their order is not confirmed; run without --broadcast first to simulate.
/// Launching on Ascend's own site and setting TOKEN=<address> works too: the script then just records it.
contract LaunchOnAscend is BaseScript {
    function run() external {
        Deployment memory d = _load();
        require(d.launchpad != address(0), "run DeployCore first");
        uint256 pk = _deployerKey();
        address me = vm.addr(pk);
        string memory name = vm.envOr("TOKEN_NAME", string("Monarchy"));
        string memory symbol = vm.envOr("TOKEN_SYMBOL", string("MONARCH"));
        address existing = vm.envOr("TOKEN", address(0));

        if (existing != address(0)) {
            d.token = existing;
            d.poolId = AscendPoolKey.id(existing, d.quote, d.launchpad, d.poolManager);
        } else if (keccak256(bytes(d.mode)) == keccak256("mock")) {
            uint256 seed = 50_000e6;
            vm.startBroadcast(pk);
            MockERC20(d.quote).mint(me, seed);
            MockERC20(d.quote).approve(d.launchpad, seed);
            (d.token, d.poolId) =
                MockAscendLaunchpad(d.launchpad).launch(name, symbol, d.quote, me, 800_000_000e18, seed);
            vm.stopBroadcast();
        } else {
            bytes32 salt = keccak256(abi.encode(me, block.timestamp));
            vm.startBroadcast(pk);
            (bool ok, bytes memory ret) = d.launchpad.call(
                abi.encodeWithSignature(
                    "launch((string,string,address,uint256,uint256,bytes32,address))",
                    name,
                    symbol,
                    d.quote,
                    uint256(0),
                    uint256(0),
                    salt,
                    me
                )
            );
            vm.stopBroadcast();
            require(ok, "Ascend launch reverted; launch on Ascend's site and rerun with TOKEN=<address>");
            (d.token, d.poolId) = abi.decode(ret, (address, bytes32));
            require(d.poolId == AscendPoolKey.id(d.token, d.quote, d.launchpad, d.poolManager), "pool id mismatch");
        }
        _save(d);
        console2.log("token", d.token);
        console2.logBytes32(d.poolId);
    }
}
