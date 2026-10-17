import { useConnect, useConnection, useConnectors, useDisconnect, useSwitchChain } from "wagmi";
import { chainName } from "../lib/chains";
import { short } from "../lib/format";
import { useNetwork } from "../lib/network";
import { Spinner } from "./Ui";

export function Connect({ className }: { className?: string }) {
  const { address, isConnected } = useConnection();
  const connectors = useConnectors();
  const connect = useConnect();
  const { mutate: disconnect } = useDisconnect();
  const { wrongNetwork } = useNetwork();

  if (!isConnected) {
    const c = connectors[0];
    return (
      <button className={`btn ${className ?? ""}`} disabled={!c || connect.isPending} onClick={() => c && connect.mutate({ connector: c })}>
        {connect.isPending ? (
          <>
            <Spinner /> Connecting
          </>
        ) : (
          "Connect wallet"
        )}
      </button>
    );
  }
  return (
    <button className={`btn btn-ghost wallet ${className ?? ""}`} onClick={() => disconnect()} title="Disconnect">
      <i className={`wallet-dot ${wrongNetwork ? "wallet-dot-warn" : ""}`} />
      <span className="mono">{short(address)}</span>
    </button>
  );
}

/** Asks the wallet to move to the network Monarchy reads from. */
export function SwitchButton({ className }: { className?: string }) {
  const switchChain = useSwitchChain();
  const { target } = useNetwork();
  return (
    <button className={`btn ${className ?? ""}`} disabled={switchChain.isPending} onClick={() => switchChain.mutate({ chainId: target.id })}>
      {switchChain.isPending ? (
        <>
          <Spinner /> Check your wallet
        </>
      ) : (
        `Switch to ${chainName(target.id)}`
      )}
    </button>
  );
}
