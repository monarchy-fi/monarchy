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
/// a 7-day rolling treasury stream, no listing set-aside, creator role locked forever.
/// Override with BURN_BPS, HOLDERS_BPS, TREASURY_BPS, TREASURY, SWAPPER, MAX_SLIPPAGE_BPS, ENROL_LISTING with
/// LISTING_CAP (in the quote's units), LOCK_FOREVER (false = no lock). The buyback route is the AscendSwapper recorded in
/// deployments/<chainId>.json unless SWAPPER names another one. It is never left to the factory's default
/// silently: the factory owner can change that default (12 hours after setDefaultSwapper), and a re-run of
/// this script would otherwise pick the new one up without warning. To keep buybacks in reserve instead,
/// the factory owner runs setDefaultSwapper(0x0) at least 12 hours before activating and this script runs
/// with SWAPPER set to the zero address, which asks for that default.
/// TREASURY (the Team Treasury recipient) must be set explicitly; it can never be changed afterwards.
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

        bool swapperGiven = bytes(vm.envOr("SWAPPER", string(""))).length != 0;
        address swapper = swapperGiven ? vm.envAddress("SWAPPER") : d.swapper;
        require(swapperGiven || swapper != address(0), "no swapper in deployments/<chainId>.json; set SWAPPER");
        console2.log("swapper", swapper);

        LodestarFactory.DeployParams memory p;
        p.token = d.token;
        p.quote = d.quote;
        p.cfg = ILodestar.Config({
            burnBps: uint16(vm.envOr("BURN_BPS", uint256(4_000))),
            holdersBps: uint16(vm.envOr("HOLDERS_BPS", uint256(4_000))),
            treasuryBps: uint16(vm.envOr("TREASURY_BPS", uint256(2_000))),
            swapper: swapper,
            maxSlippageBps: uint16(vm.envOr("MAX_SLIPPAGE_BPS", uint256(1_000))),
            // token-side fees: burn them (default) or send them all to Exile lockers
            tokenToHolders: vm.envOr("TOKEN_TO_HOLDERS", false)
        });
        p.treasuryRecipient = vm.envAddress("TREASURY");
        p.treasuryWindow = 7 days;
        p.tiers = MonarchTiers.defaults();
        // off by default, so the creator's whole quote share reaches the router. Opting in needs LISTING_CAP,
        // in the quote asset's own units.
        p.enrolListing = vm.envOr("ENROL_LISTING", false);
        require(!p.enrolListing || vm.envExists("LISTING_CAP"), "set LISTING_CAP in the quote's units");
        p.listingCap = p.enrolListing ? vm.envUint("LISTING_CAP") : 0;
        // locked to the router for good unless LOCK_FOREVER=false, like the checkbox on the site
        p.creatorLockUntil = vm.envOr("LOCK_FOREVER", true) ? type(uint64).max : 0;

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
