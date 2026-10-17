// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IExile} from "../interfaces/IExile.sol";

/// @notice MONARCH's default Exile tiers. Other creators pick their own.
///   Peasant  1 day    0.5x  "Everyone starts somewhere."
///   Knight   3 days   1x    "Sworn to the kingdom."
///   Duke     7 days   1.5x  "Next in line."
///   Monarch  30 days  3x    "Steal the crown."
library MonarchTiers {
    function defaults() internal pure returns (IExile.Tier[] memory t) {
        t = new IExile.Tier[](4);
        t[0] = IExile.Tier({minDuration: 1 days, multiplierBps: 5_000, label: "Peasant"});
        t[1] = IExile.Tier({minDuration: 3 days, multiplierBps: 10_000, label: "Knight"});
        t[2] = IExile.Tier({minDuration: 7 days, multiplierBps: 15_000, label: "Duke"});
        t[3] = IExile.Tier({minDuration: 30 days, multiplierBps: 30_000, label: "Monarch"});
    }
}
