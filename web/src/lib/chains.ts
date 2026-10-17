import { defineChain } from "viem";
import { anvil } from "viem/chains";

export const elysiumTestnet = defineChain({
  id: 99801,
  name: "Elysium Testnet",
  nativeCurrency: { name: "HYPE", symbol: "HYPE", decimals: 18 },
  rpcUrls: { default: { http: ["https://testnet-rpc.elysium.kinetiq.xyz"] } },
  blockExplorers: {
    default: { name: "Elysium Explorer", url: "https://elysium.kinetiq.xyz/testnet-explorer" },
  },
  contracts: { multicall3: { address: "0xcA11bde05977b3631167028862bE2a173976CA11" } },
  testnet: true,
});

export const localChain = anvil;

export function explorerTx(chainId: number, hash: string): string | undefined {
  if (chainId === elysiumTestnet.id) return `${elysiumTestnet.blockExplorers.default.url}/tx/${hash}`;
  return undefined;
}

export function explorerAddress(chainId: number, address: string): string | undefined {
  if (chainId === elysiumTestnet.id) return `${elysiumTestnet.blockExplorers.default.url}/address/${address}`;
  return undefined;
}

/** A short, human name for a chain id. */
export function chainName(chainId: number | undefined): string {
  if (chainId === elysiumTestnet.id) return "Elysium testnet";
  if (chainId === localChain.id) return "Local demo chain";
  if (chainId === 1) return "Ethereum";
  if (chainId === 999) return "HyperEVM";
  return chainId ? `Chain ${chainId}` : "an unknown network";
}
