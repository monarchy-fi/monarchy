import { createConfig, http } from "wagmi";
import { injected, mock } from "wagmi/connectors";
import type { Chain } from "viem";
import { elysiumTestnet, localChain } from "./chains";
import { deployedChainIds } from "./deployments";

// The first chain is what the app reads before a wallet connects: prefer one that has a deployment.
const deployed = deployedChainIds();
const all: [Chain, ...Chain[]] = [elysiumTestnet, localChain];
const chains = [...all].sort((a, b) => Number(deployed.includes(b.id)) - Number(deployed.includes(a.id))) as [
  Chain,
  ...Chain[],
];

// `?mock` on a dev server connects anvil's first account without a browser wallet (for local testing).
const useMock = import.meta.env.DEV && typeof location !== "undefined" && location.search.includes("mock");

export const config = createConfig({
  chains,
  connectors: useMock
    ? [mock({ accounts: ["0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"], features: { reconnect: true } })]
    : [injected()],
  transports: {
    [elysiumTestnet.id]: http(),
    [localChain.id]: http("http://127.0.0.1:8545"),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof config;
  }
}
