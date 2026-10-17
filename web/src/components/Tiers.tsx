import { Badge } from "./Ui";
import { Crown } from "./Crown";

// Tier names come from the chain (the creator picks them at activation), so they are looked up in Maps:
// a plain object would answer for names like "__proto__" or "constructor" with something React can't render.
const TAGLINES = new Map<string, string>([
  ["Peasant", "Everyone starts somewhere."],
  ["Knight", "Sworn to the kingdom."],
  ["Duke", "Next in line."],
  ["Monarch", "Steal the crown."],
]);

const TONES = new Map<string, "grey" | "silver" | "purple" | "gold">([
  ["Peasant", "grey"],
  ["Knight", "silver"],
  ["Duke", "purple"],
  ["Monarch", "gold"],
]);

/** The tagline of one of the four default tiers, or nothing for a custom name. */
export function tagline(name: string): string | undefined {
  return TAGLINES.get(name);
}

export function TierBadge({ name }: { name: string }) {
  if (!name) return <Badge tone="red">No rewards</Badge>;
  return (
    <Badge tone={TONES.get(name) ?? "silver"}>
      {name === "Monarch" && <Crown size={12} />} {name}
    </Badge>
  );
}
