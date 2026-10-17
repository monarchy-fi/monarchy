import { useEffect, useState, type ReactNode } from "react";
import { useChainId, useConnect, useConnection, useConnectors, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import type { Abi, Address } from "viem";
import { useReadContract } from "wagmi";
import { mockERC20Abi } from "../abi";
import { chainName, explorerTx } from "../lib/chains";
import { short } from "../lib/format";
import { useNetwork } from "../lib/network";
import { Spinner } from "./Ui";

// Loose on purpose: each call site passes a typed abi + functionName; wagmi checks args there.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type WriteRequest = { address: Address; abi: Abi; functionName: string; args?: readonly unknown[]; value?: bigint; gas?: bigint } & Record<string, any>;

type Props = {
  request: () => WriteRequest | undefined;
  children: ReactNode;
  disabledReason?: string;
  onDone?: () => void;
  className?: string;
};

/** Sends one transaction and shows pending / confirmed / error, with an explorer link when there is one. */
export function TxButton({ request, children, disabledReason, onDone, className }: Props) {
  const chainId = useChainId();
  const { isConnected } = useConnection();
  const { wrongNetwork, target } = useNetwork();
  const qc = useQueryClient();
  const write = useWriteContract();
  const [hash, setHash] = useState<`0x${string}`>();
  const receipt = useWaitForTransactionReceipt({ hash });
  const [error, setError] = useState<string>();

  useEffect(() => {
    if (receipt.isSuccess) {
      qc.invalidateQueries();
      onDone?.();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [receipt.isSuccess]);

  const busy = write.isPending || (!!hash && receipt.isLoading);
  // Nothing is sent while the wallet sits on another chain; the notice under the nav offers the switch.
  const reason = !isConnected ? "Connect a wallet" : wrongNetwork ? `Switch your wallet to ${chainName(target.id)} first` : disabledReason;

  async function send() {
    setError(undefined);
    setHash(undefined);
    const req = request();
    if (!req) return;
    try {
      // Pinned to the chain the page reads from: if the wallet moved in the meantime, wagmi refuses to send
      // instead of sending the transaction somewhere else.
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const h = await write.mutateAsync({ chainId, ...req } as any);
      setHash(h);
    } catch (e) {
      setError(shortError(e));
    }
  }

  const link = hash ? explorerTx(chainId, hash) : undefined;
  const txRef = hash && (
    link ? (
      <a className="tx-link" href={link} target="_blank" rel="noreferrer">
        View transaction <span aria-hidden="true">↗</span>
      </a>
    ) : (
      <span className="mono muted" title={hash}>
        {short(hash)}
      </span>
    )
  );
  const done = !!hash && receipt.isSuccess;
  return (
    <div className="tx">
      <button
        className={`${className ?? "btn"} ${busy ? "is-busy" : ""} ${done && !busy ? "is-done" : ""}`}
        disabled={!!reason || busy}
        onClick={send}
        title={reason}
        aria-busy={busy}
      >
        {write.isPending ? (
          <>
            <Spinner /> Confirm in wallet
          </>
        ) : busy ? (
          <>
            <Spinner /> Confirming
          </>
        ) : (
          children
        )}
      </button>
      {!isConnected ? <ConnectFirst /> : reason && !busy && <span className="tx-note">{reason}</span>}
      {busy && !write.isPending && hash && <span className="tx-pending">Waiting for the block. {txRef}</span>}
      {done && (
        <span className="tx-ok" role="status">
          <span aria-hidden="true">✓</span> Confirmed. {txRef}
        </span>
      )}
      {receipt.isError && (
        <span className="tx-err" role="alert">
          Transaction failed. {txRef}
        </span>
      )}
      {error && (
        <span className="tx-err" role="alert">
          {error}
        </span>
      )}
    </div>
  );
}

/** Beside a button that can't work yet because no wallet is connected: types itself out, and connects on click. */
function ConnectFirst() {
  const connectors = useConnectors();
  const connect = useConnect();
  const c = connectors[0];
  return (
    <button type="button" className="connect-first" disabled={!c || connect.isPending} onClick={() => c && connect.mutate({ connector: c })}>
      <span className="cf-arrow" aria-hidden="true">◂</span>
      <span className="cf-text">{connect.isPending ? "Connecting" : "Connect first"}</span>
    </button>
  );
}

/**
 * Shows an Approve button until `spender` may move `amount` of `token`, then the action button.
 * The approval is for exactly `amount`, never an unlimited allowance.
 */
export function WithApproval({
  token,
  spender,
  amount,
  children,
}: {
  token?: Address;
  spender?: Address;
  amount: bigint;
  children: ReactNode;
}) {
  const { address } = useConnection();
  const allowance = useReadContract({
    address: token,
    abi: mockERC20Abi,
    functionName: "allowance",
    args: address && spender ? [address, spender] : undefined,
    query: { enabled: !!token && !!address && !!spender, refetchInterval: 2000 },
  });
  if (!token || !spender) return <>{children}</>;
  if (allowance.data !== undefined && allowance.data >= amount) return <>{children}</>;
  return (
    <TxButton
      request={() => ({ address: token, abi: mockERC20Abi, functionName: "approve", args: [spender, amount] })}
      disabledReason={amount === 0n ? "Enter an amount" : undefined}
    >
      Approve
    </TxButton>
  );
}

export function shortError(e: unknown): string {
  const err = e as { shortMessage?: string; message?: string; cause?: { reason?: string; data?: { errorName?: string } } };
  const name = err.cause?.data?.errorName;
  if (name) return name;
  const msg = err.shortMessage ?? err.message?.split("\n")[0] ?? "Something went wrong.";
  if (/user (rejected|denied)/i.test(msg)) return "You cancelled it in your wallet.";
  return msg;
}
