// Lengths the UI shows before (or instead of) reading them from the contracts.
// If the contracts change, these are the only lines to update.

/** Exile's reward drip, in days. The live value is read from Exile.DRIP() when the chain answers. */
export const DEFAULT_DRIP_DAYS = 7;

/** The Team Treasury stream window proposed in the Lodestar activation form, in days. Live streams show their own window. */
export const DEFAULT_TREASURY_WINDOW_DAYS = 30;
