// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

/// @notice Reads and writes `deployments/<chainId>.json`, the one file the website reads.
abstract contract BaseScript is Script {
    struct Deployment {
        string mode; // "real" (Ascend on Elysium) or "mock"
        address launchpad;
        address desk;
        address poolManager;
        address vault;
        address quote;
        address exile;
        address sandfall;
        address lodestarImpl;
        address factory;
        address swapper;
        address token;
        bytes32 poolId;
        address lodestar;
        uint256 startBlock;
    }

    function _path() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", vm.toString(block.chainid), ".json");
    }

    function _load() internal view returns (Deployment memory d) {
        string memory path = _path();
        if (!vm.exists(path)) return d;
        string memory j = vm.readFile(path);
        d.mode = _str(j, ".mode");
        d.launchpad = _addr(j, ".launchpad");
        d.desk = _addr(j, ".desk");
        d.poolManager = _addr(j, ".poolManager");
        d.vault = _addr(j, ".vault");
        d.quote = _addr(j, ".quote");
        d.exile = _addr(j, ".exile");
        d.sandfall = _addr(j, ".sandfall");
        d.lodestarImpl = _addr(j, ".lodestarImpl");
        d.factory = _addr(j, ".factory");
        d.swapper = _addr(j, ".swapper");
        d.token = _addr(j, ".token");
        d.lodestar = _addr(j, ".lodestar");
        if (vm.keyExistsJson(j, ".poolId")) d.poolId = vm.parseJsonBytes32(j, ".poolId");
        if (vm.keyExistsJson(j, ".startBlock")) d.startBlock = vm.parseJsonUint(j, ".startBlock");
    }

    function _save(Deployment memory d) internal {
        string memory k = "deployment";
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeString(k, "mode", d.mode);
        vm.serializeAddress(k, "launchpad", d.launchpad);
        vm.serializeAddress(k, "desk", d.desk);
        vm.serializeAddress(k, "poolManager", d.poolManager);
        vm.serializeAddress(k, "vault", d.vault);
        vm.serializeAddress(k, "quote", d.quote);
        vm.serializeAddress(k, "exile", d.exile);
        vm.serializeAddress(k, "sandfall", d.sandfall);
        vm.serializeAddress(k, "lodestarImpl", d.lodestarImpl);
        vm.serializeAddress(k, "factory", d.factory);
        vm.serializeAddress(k, "swapper", d.swapper);
        vm.serializeAddress(k, "token", d.token);
        vm.serializeBytes32(k, "poolId", d.poolId);
        vm.serializeUint(k, "startBlock", d.startBlock);
        string memory out = vm.serializeAddress(k, "lodestar", d.lodestar);
        vm.writeJson(out, _path());
        console2.log("wrote", _path());
    }

    function _addr(string memory j, string memory key) private view returns (address) {
        return vm.keyExistsJson(j, key) ? vm.parseJsonAddress(j, key) : address(0);
    }

    function _str(string memory j, string memory key) private view returns (string memory) {
        return vm.keyExistsJson(j, key) ? vm.parseJsonString(j, key) : "";
    }

    function _deployerKey() internal view returns (uint256) {
        return vm.envUint("PRIVATE_KEY");
    }
}
