import { useConnection } from "wagmi";
import { deployedChainIds } from "./deployments";
import { targetChain } from "./wagmi";

/** Whether the connected wallet sits on a network Monarchy isn't deployed on. */
export function useNetwork() {
  const { isConnected, chainId: walletChainId } = useConnection();
  const supported = deployedChainIds();
  const wrongNetwork = isConnected && walletChainId !== undefined && !supported.includes(walletChainId);
  return { isConnected, walletChainId, wrongNetwork, target: targetChain };
}
