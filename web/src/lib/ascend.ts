import { useChainId, useReadContract } from "wagmi";
import { encodeAbiParameters, keccak256, type Address, type Hex } from "viem";
import { iAscendLaunchpadAbi } from "../abi";
import { elysiumTestnet } from "./chains";
import { useDeployment, ZERO } from "./deployments";

/** Ascend's pool id for a token and quote pair, the same key AscendPoolKey.sol rebuilds on chain: currencies sorted
 * ascending, the launchpad as hook, the dynamic-fee flag, tick spacing 200 and hook bitmap 0x0445. */
export function ascendPoolId(token: Address, quote: Address, launchpad: Address, poolManager: Address): Hex {
  const [c0, c1] = token.toLowerCase() < quote.toLowerCase() ? [token, quote] : [quote, token];
  return keccak256(
    encodeAbiParameters(
      [{ type: "address" }, { type: "address" }, { type: "address" }, { type: "address" }, { type: "uint24" }, { type: "bytes32" }],
      [c0, c1, launchpad, poolManager, 0x800000, "0x0000000000000000000000000000000000000000000000000000000000c80445"],
    ),
  );
}

/** A token's page on Ascend's own app, where Monarchy sends anyone who opens a token. Ascend runs on the testnet for now. */
export function ascendTokenUrl(chainId: number, token: string): string | undefined {
  if (chainId === elysiumTestnet.id) return `https://app.ascendlaunch.xyz/tokens/${token}`;
  return undefined;
}

/** The Ascend page for a token launched on this deployment's launchpad against its quote asset, or undefined for
 * anything else (the quote itself, an LP token, a token paired with another quote), which keeps its explorer link. */
export function useAscendTokenUrl(token?: Address): string | undefined {
  const chainId = useChainId();
  const d = useDeployment();
  const url = token ? ascendTokenUrl(chainId, token) : undefined;
  const check = !!url && !!d && token !== ZERO && token!.toLowerCase() !== d.quote.toLowerCase();
  const creator = useReadContract({
    address: d?.launchpad,
    abi: iAscendLaunchpadAbi,
    functionName: "poolCreator",
    args: check ? [ascendPoolId(token!, d!.quote, d!.launchpad, d!.poolManager)] : undefined,
    // who launched a token never changes whether it was an Ascend launch, so one read is enough
    query: { enabled: check, staleTime: Infinity },
  });
  return check && creator.data && creator.data !== ZERO ? url : undefined;
}
