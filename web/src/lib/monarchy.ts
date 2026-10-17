import { useReadContract, useReadContracts } from "wagmi";
import type { Address } from "viem";
import { exileAbi, lodestarAbi, mockERC20Abi } from "../abi";
import { DEFAULT_DRIP_DAYS } from "./constants";
import { isSet, useDeployment } from "./deployments";

/** The router and assets for the deployment's token, or any Lodestar passed in. */
export function useLodestarCore(lodestar?: Address) {
  const d = useDeployment();
  const address = lodestar ?? (isSet(d?.lodestar) ? d!.lodestar : undefined);
  const base = { address, abi: lodestarAbi } as const;
  const r = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...base, functionName: "token" },
      { ...base, functionName: "quote" },
      { ...base, functionName: "exilePoolId" },
      { ...base, functionName: "treasuryStreamId" },
      { ...base, functionName: "poolId" },
      { ...base, functionName: "steward" },
    ],
    query: { enabled: !!address },
  });
  const [token, quote, exilePoolId, treasuryStreamId, poolId, steward] = r.data ?? [];
  const meta = useTokenMeta([token, quote]);
  return {
    lodestar: address,
    token,
    quote,
    exilePoolId,
    treasuryStreamId,
    poolId,
    steward,
    tokenMeta: meta[0],
    quoteMeta: meta[1],
    isLoading: r.isLoading,
  };
}

export type TokenMeta = { symbol: string; decimals: number };

export function useTokenMeta(tokens: (Address | undefined)[]): (TokenMeta | undefined)[] {
  const r = useReadContracts({
    allowFailure: true,
    contracts: tokens.flatMap((t) => [
      { address: t, abi: mockERC20Abi, functionName: "symbol" } as const,
      { address: t, abi: mockERC20Abi, functionName: "decimals" } as const,
    ]),
    query: { enabled: tokens.every((t) => !!t), staleTime: Infinity },
  });
  return tokens.map((_, i) => {
    const s = r.data?.[2 * i];
    const dec = r.data?.[2 * i + 1];
    if (!s || !dec || s.status !== "success" || dec.status !== "success") return undefined;
    return { symbol: s.result as string, decimals: Number(dec.result) };
  });
}

/** Exile's reward drip length in days, read from the contract (falls back to the default while loading). */
export function useDripDays(): number {
  const d = useDeployment();
  const r = useReadContract({ address: d?.exile, abi: exileAbi, functionName: "DRIP", query: { enabled: !!d, staleTime: Infinity } });
  return r.data !== undefined ? Number(r.data) / 86400 : DEFAULT_DRIP_DAYS;
}

/** "7 day" style label for a number of days. */
export function dayLabel(days: number): string {
  return `${Number.isInteger(days) ? days : days.toFixed(1)} day`;
}
