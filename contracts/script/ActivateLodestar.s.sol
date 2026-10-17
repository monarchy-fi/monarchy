// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseScript} from "./Base.s.sol";
import {console2} from "forge-std/Script.sol";
import {LodestarFactory} from "../src/LodestarFactory.sol";
import {ILodestar} from "../src/interfaces/ILodestar.sol";
import {IAscendLaunchpad} from "../src/interfaces/IAscendLaunchpad.sol";
import {MonarchTiers} from "../src/libraries/MonarchTiers.sol";

/// @notice Hand the token's Ascend creator role to its Lodestar and activate it with MONARCH's defaults:
/// 40% buyback and burn / 40% holders / 20% Team Treasury, Peasant-Knight-Duke-Monarch tiers,
/// a 30-day rolling treasury stream, listing set-aside on (5,000 USDC cap), creator role locked a year.
/// Override with BURN_BPS, HOLDERS_BPS, TREASURY_BPS, TREASURY, SWAPPER (unset = the factory default),
/// MAX_SLIPPAGE_BPS, ENROL_LISTING, LISTING_CAP, LOCK_DAYS (0 = no lock). To keep buybacks in reserve
/// instead, the factory owner first runs setDefaultSwapper(0x0).
contract ActivateLodestar is BaseScript {
    function run() external {
        Deployment memory d = _load();
        require(d.factory != address(0) && d.token != address(0), "run DeployCore and LaunchOnAscend first");
        uint256 pk = _deployerKey();
        address me = vm.addr(pk);
        LodestarFactory factory = LodestarFactory(d.factory);
        (address predicted, bytes32 poolId) = factory.predict(d.token, d.quote);
        console2.log("predicted Lodestar", predicted);
        require(IAscendLaunchpad(d.launchpad).poolCreator(poolId) == me, "PRIVATE_KEY is not the pool creator");

        LodestarFactory.DeployParams memory p;
        p.token = d.token;
        p.quote = d.quote;
        p.cfg = ILodestar.Config({
            burnBps: uint16(vm.envOr("BURN_BPS", uint256(4_000))),
            holdersBps: uint16(vm.envOr("HOLDERS_BPS", uint256(4_000))),
            treasuryBps: uint16(vm.envOr("TREASURY_BPS", uint256(2_000))),
            swapper: vm.envOr("SWAPPER", address(0)),
            maxSlippageBps: uint16(vm.envOr("MAX_SLIPPAGE_BPS", uint256(1_000)))
        });
        p.treasuryRecipient = vm.envOr("TREASURY", me);
        p.treasuryWindow = 30 days;
        p.tiers = MonarchTiers.defaults();
        p.enrolListing = vm.envOr("ENROL_LISTING", true);
        p.listingCap = vm.envOr("LISTING_CAP", uint256(5_000e6));
        uint256 lockDays = vm.envOr("LOCK_DAYS", uint256(365));
        p.creatorLockUntil = lockDays == 0 ? 0 : uint64(block.timestamp + lockDays * 1 days);

        vm.startBroadcast(pk);
        if (IAscendLaunchpad(d.launchpad).pendingCreator(poolId) != predicted) {
            IAscendLaunchpad(d.launchpad).transferCreator(poolId, predicted);
        }
        address lodestar = factory.deploy{gas: 6_000_000}(p);
        vm.stopBroadcast();

        d.lodestar = lodestar;
        _save(d);
        console2.log("Lodestar", lodestar);
    }
}
