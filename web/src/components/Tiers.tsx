import { Badge } from "./Ui";
import { Crown } from "./Crown";

export const TAGLINES: Record<string, string> = {
  Peasant: "Everyone starts somewhere.",
  Knight: "Sworn to the kingdom.",
  Duke: "Next in line.",
  Monarch: "Steal the crown.",
};

const TONES: Record<string, "grey" | "silver" | "purple" | "gold"> = {
  Peasant: "grey",
  Knight: "silver",
  Duke: "purple",
  Monarch: "gold",
};

export function TierBadge({ name }: { name: string }) {
  if (!name) return <Badge tone="red">No rewards</Badge>;
  return (
    <Badge tone={TONES[name] ?? "silver"}>
      {name === "Monarch" && <Crown size={12} />} {name}
    </Badge>
  );
}
