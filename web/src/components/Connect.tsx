import { useChainId, useConnect, useConnection, useConnectors, useDisconnect, useSwitchChain } from "wagmi";
import { elysiumTestnet } from "../lib/chains";
import { deployedChainIds } from "../lib/deployments";
import { short } from "../lib/format";

export function Connect() {
  const { address, isConnected, chainId: walletChain } = useConnection();
  const connectors = useConnectors();
  const connect = useConnect();
  const { mutate: disconnect } = useDisconnect();
  const switchChain = useSwitchChain();
  const appChain = useChainId();
  const deployed = deployedChainIds();

  if (!isConnected) {
    const c = connectors[0];
    return (
      <button className="btn" disabled={!c || connect.isPending} onClick={() => c && connect.mutate({ connector: c })}>
        {connect.isPending ? "Connecting…" : "Connect wallet"}
      </button>
    );
  }
  const wrongChain = walletChain !== undefined && !deployed.includes(walletChain);
  return (
    <div className="connect">
      {wrongChain && (
        <button
          className="btn btn-warn"
          onClick={() => switchChain.mutate({ chainId: deployed.includes(elysiumTestnet.id) ? elysiumTestnet.id : (deployed[0] ?? appChain) })}
        >
          Switch network
        </button>
      )}
      <button className="btn btn-ghost" onClick={() => disconnect()} title="Disconnect">
        {short(address)}
      </button>
    </div>
  );
}
