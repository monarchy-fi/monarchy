import { useChainId } from "wagmi";
import type { Address, Hex } from "viem";

export type Deployment = {
  chainId: number;
  mode: "real" | "mock";
  launchpad: Address;
  desk: Address;
  poolManager: Address;
  vault: Address;
  quote: Address;
  exile: Address;
  sandfall: Address;
  lodestarImpl: Address;
  factory: Address;
  swapper: Address;
  token: Address;
  poolId: Hex;
  lodestar: Address;
  startBlock: number;
};

// deployments/<chainId>.json is written by the forge scripts; missing chains just aren't listed.
const files = import.meta.glob<Deployment>("../../../deployments/*.json", { eager: true, import: "default" });
const byChain: Record<number, Deployment> = {};
for (const d of Object.values(files)) byChain[d.chainId] = d;

export const ZERO = "0x0000000000000000000000000000000000000000" as Address;

export function useDeployment(): Deployment | undefined {
  const chainId = useChainId();
  return byChain[chainId];
}

export function deployedChainIds(): number[] {
  return Object.keys(byChain).map(Number);
}

export function isSet(a?: string): a is Address {
  return !!a && a !== ZERO;
}
