// Lengths the UI shows before (or instead of) reading them from the contracts.
// If the contracts change, these are the only lines to update.

/** Exile's reward drip, in days. The live value is read from Exile.DRIP() when the chain answers. */
export const DEFAULT_DRIP_DAYS = 3;

/** The Team Treasury stream window proposed in the Lodestar activation form, in days. Live streams show their own window. */
export const DEFAULT_TREASURY_WINDOW_DAYS = 7;

/** How often the team calls Lodestar.distribute() from team funds. Anyone else can call it at any time. */
export const DISTRIBUTE_EVERY_HOURS = 3;

/** One line on who calls distribute, shown next to the drip stats and the Distribute button. */
export const DISTRIBUTE_NOTE = `Distributed every ${DISTRIBUTE_EVERY_HOURS} hours by the team, and anyone can call it.`;
