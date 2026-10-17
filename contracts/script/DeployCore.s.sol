// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseScript} from "./Base.s.sol";
import {console2} from "forge-std/Script.sol";
import {Exile} from "../src/Exile.sol";
import {Sandfall} from "../src/Sandfall.sol";
import {Lodestar} from "../src/Lodestar.sol";
import {LodestarFactory} from "../src/LodestarFactory.sol";
import {AscendSwapper} from "../src/AscendSwapper.sol";
import {IAscendLaunchpad} from "../src/interfaces/IAscendLaunchpad.sol";
import {IListingDesk} from "../src/interfaces/IListingDesk.sol";
import {ICLPoolManager, IVault} from "../src/interfaces/IInfinity.sol";
import {IExile} from "../src/interfaces/IExile.sol";
import {ISandfall} from "../src/interfaces/ISandfall.sol";

/// @notice Deploys Exile, Sandfall, the Lodestar implementation, AscendSwapper and LodestarFactory.
/// ASCEND_MODE=real (default) points at Ascend on Elysium testnet from env; ASCEND_MODE=mock points at
/// the contracts DeployMocks wrote to deployments/<chainId>.json.
contract DeployCore is BaseScript {
    function run() external {
        string memory mode = vm.envOr("ASCEND_MODE", string("real"));
        Deployment memory d = _load();

        if (keccak256(bytes(mode)) == keccak256("real")) {
            d.mode = "real";
            d.launchpad = vm.envAddress("ASCEND_LAUNCHPAD");
            d.desk = vm.envAddress("ASCEND_DESK");
            d.poolManager = vm.envAddress("CL_POOL_MANAGER");
            d.vault = vm.envAddress("INFINITY_VAULT");
            d.quote = vm.envAddress("QUOTE");
            d.startBlock = block.number;
        } else {
            require(d.launchpad != address(0), "run DeployMocks first");
        }
        require(d.launchpad.code.length > 0 && d.desk.code.length > 0, "launchpad/desk not deployed here");
        require(d.poolManager.code.length > 0 && d.vault.code.length > 0, "Infinity not deployed here");
        require(IAscendLaunchpad(d.launchpad).listingDesk() == d.desk, "desk is not the launchpad's");

        vm.startBroadcast(_deployerKey());
        Exile exile = new Exile();
        Sandfall sandfall = new Sandfall();
        Lodestar impl = new Lodestar();
        AscendSwapper swapper =
            new AscendSwapper(IVault(d.vault), ICLPoolManager(d.poolManager), IAscendLaunchpad(d.launchpad));
        LodestarFactory factory = new LodestarFactory(
            address(impl),
            IAscendLaunchpad(d.launchpad),
            IListingDesk(d.desk),
            ICLPoolManager(d.poolManager),
            IExile(address(exile)),
            ISandfall(address(sandfall)),
            address(swapper)
        );
        vm.stopBroadcast();

        d.exile = address(exile);
        d.sandfall = address(sandfall);
        d.lodestarImpl = address(impl);
        d.swapper = address(swapper);
        d.factory = address(factory);
        _save(d);
        console2.log("factory", address(factory));
    }
}
