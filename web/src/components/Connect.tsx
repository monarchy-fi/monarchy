import { useConnect, useConnection, useConnectors, useDisconnect, useSwitchChain } from "wagmi";
import { chainName } from "../lib/chains";
import { short } from "../lib/format";
import { useNetwork } from "../lib/network";
import { shortError } from "./Tx";
import { Spinner } from "./Ui";

export function Connect({ className }: { className?: string }) {
  const { address, isConnected } = useConnection();
  const connectors = useConnectors();
  const connect = useConnect();
  const { mutate: disconnect } = useDisconnect();
  const { wrongNetwork } = useNetwork();

  if (!isConnected) {
    const c = connectors[0];
    // without a browser wallet the injected connector throws ProviderNotFoundError; say so on the button
    const noWallet = (connect.error as Error | null)?.name === "ProviderNotFoundError";
    return (
      <button
        className={`btn ${className ?? ""}`}
        disabled={!c || connect.isPending}
        onClick={() => c && connect.mutate({ connector: c })}
        title={noWallet ? "Install a browser wallet such as MetaMask or Rabby, then try again" : connect.error ? shortError(connect.error) : undefined}
        aria-live="polite"
      >
        {connect.isPending ? (
          <>
            <Spinner /> Connecting
          </>
        ) : noWallet ? (
          "No wallet found"
        ) : (
          "Connect wallet"
        )}
      </button>
    );
  }
  return (
    <button className={`btn btn-ghost wallet ${className ?? ""}`} onClick={() => disconnect()} title="Disconnect" aria-label={`Disconnect ${address}`}>
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
