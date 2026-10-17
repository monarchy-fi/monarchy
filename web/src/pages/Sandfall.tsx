import { useMemo, useState } from "react";
import { useConnection, useReadContract, useReadContracts } from "wagmi";
import { isAddress, type Address } from "viem";
import { mockERC20Abi, sandfallAbi } from "../abi";
import { TxButton, WithApproval } from "../components/Tx";
import { Addr, Badge, Card, Empty, Row } from "../components/Ui";
import { useDeployment, ZERO } from "../lib/deployments";
import { date, duration, fmt } from "../lib/format";
import { POLL, useNow } from "../lib/hooks";
import { useLodestarCore } from "../lib/monarchy";
import { NoDeployment, safeParse } from "./Exile";

const KINDS = ["Linear", "Monthly steps", "Rolling"];

export function SandfallPage() {
  const d = useDeployment();
  const core = useLodestarCore();
  const { address } = useConnection();
  const sf = { address: d?.sandfall, abi: sandfallAbi } as const;
  const lists = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...sf, functionName: "streamsOf", args: [address ?? ZERO] },
      { ...sf, functionName: "createdBy", args: [address ?? ZERO] },
    ],
    query: { enabled: !!d && !!address, ...POLL.query },
  });
  const [toMe, byMe] = lists.data ?? [[], []];
  const mine = useMemo(() => [...toMe].reverse().filter((id) => id !== core.treasuryStreamId), [toMe, core.treasuryStreamId]);
  const created = useMemo(() => [...byMe].reverse().filter((id) => !toMe.includes(id)), [byMe, toMe]);

  if (!d) return <NoDeployment />;
  return (
    <div className="page">
      <header className="page-head">
        <h1>Sandfall</h1>
        <p className="muted">
          Vesting streams in any token or native HYPE. The creator decides at creation whether a stream can be
          cancelled, and every stream shows it. Streams can't be transferred.
        </p>
      </header>

      {core.treasuryStreamId !== undefined && (
        <Card title={`${core.tokenMeta?.symbol ?? "MONARCH"} Team Treasury`} right={<span className="muted">fed by Lodestar on every distribute</span>}>
          <StreamCard sandfall={d.sandfall} id={core.treasuryStreamId} title="Rolling 30-day stream" />
        </Card>
      )}

      <CreateStream sandfall={d.sandfall} quote={core.quote} token={core.token} quoteSymbol={core.quoteMeta?.symbol} tokenSymbol={core.tokenMeta?.symbol} />

      <Card title="Streams to me">
        {!address && <Empty>Connect a wallet to see your streams.</Empty>}
        {address && mine.length === 0 && <Empty>Nothing vesting to this wallet yet.</Empty>}
        <div className="locks">
          {mine.map((id) => (
            <StreamCard key={id.toString()} sandfall={d.sandfall} id={id} />
          ))}
        </div>
      </Card>

      {created.length > 0 && (
        <Card title="Streams I created">
          <div className="locks">
            {created.map((id) => (
              <StreamCard key={id.toString()} sandfall={d.sandfall} id={id} />
            ))}
          </div>
        </Card>
      )}
    </div>
  );
}

function CreateStream({ sandfall, quote, token, quoteSymbol, tokenSymbol }: { sandfall: Address; quote?: Address; token?: Address; quoteSymbol?: string; tokenSymbol?: string }) {
  const [assetChoice, setAssetChoice] = useState<"quote" | "token" | "native" | "other">("quote");
  const [other, setOther] = useState("");
  const [recipient, setRecipient] = useState("");
  const [amount, setAmount] = useState("");
  const [cliffDays, setCliffDays] = useState(0);
  const [lengthDays, setLengthDays] = useState(90);
  const [monthly, setMonthly] = useState(false);
  const [cancellable, setCancellable] = useState(false);

  const asset: Address | undefined =
    assetChoice === "quote" ? quote : assetChoice === "token" ? token : assetChoice === "native" ? ZERO : isAddress(other) ? other : undefined;
  const isNative = assetChoice === "native";
  const dec = useReadContract({ address: asset, abi: mockERC20Abi, functionName: "decimals", query: { enabled: !!asset && !isNative } });
  const decimals = isNative ? 18 : Number(dec.data ?? 18);
  const value = safeParse(amount, decimals);
  const start = Math.floor(Date.now() / 1000) + 60;
  const cliff = start + cliffDays * 86400;
  const end = start + lengthDays * 86400;
  const reason = !asset ? "Pick an asset" : !isAddress(recipient) ? "Enter a recipient" : value === 0n ? "Enter an amount" : cliff >= end ? "Cliff must end before the stream" : undefined;

  const send = (
    <TxButton
      disabledReason={reason}
      request={() =>
        asset && {
          address: sandfall,
          abi: sandfallAbi,
          functionName: "createFixed",
          args: [asset, recipient as Address, value, BigInt(start), BigInt(cliff), BigInt(end), monthly ? 30 * 86400 : 0, cancellable],
          value: isNative ? value : undefined,
        }
      }
      onDone={() => setAmount("")}
    >
      Create stream
    </TxButton>
  );

  return (
    <Card title="New vesting stream">
      <div className="form">
        <label>
          Asset
          <select className="input" value={assetChoice} onChange={(e) => setAssetChoice(e.target.value as typeof assetChoice)}>
            <option value="quote">{quoteSymbol ?? "Quote"}</option>
            <option value="token">{tokenSymbol ?? "Token"}</option>
            <option value="native">HYPE (native)</option>
            <option value="other">Other token</option>
          </select>
        </label>
        {assetChoice === "other" && (
          <label>
            Token address
            <input className="input" placeholder="0x…" value={other} onChange={(e) => setOther(e.target.value.trim())} />
          </label>
        )}
        <label>
          Recipient
          <input className="input" placeholder="0x…" value={recipient} onChange={(e) => setRecipient(e.target.value.trim())} />
        </label>
        <label>
          Amount
          <input className="input" inputMode="decimal" placeholder="0.0" value={amount} onChange={(e) => setAmount(e.target.value)} />
        </label>
        <label>
          Cliff (days)
          <input className="input" type="number" min={0} value={cliffDays} onChange={(e) => setCliffDays(Number(e.target.value))} />
        </label>
        <label>
          Total length (days)
          <input className="input" type="number" min={1} value={lengthDays} onChange={(e) => setLengthDays(Number(e.target.value))} />
        </label>
        <label>
          Schedule
          <select className="input" value={monthly ? "monthly" : "linear"} onChange={(e) => setMonthly(e.target.value === "monthly")}>
            <option value="linear">Linear (every second)</option>
            <option value="monthly">Monthly steps</option>
          </select>
        </label>
      </div>
      <label className="check">
        <input type="checkbox" checked={cancellable} onChange={(e) => setCancellable(e.target.checked)} />
        Cancellable by me
      </label>
      <p className={cancellable ? "warn small" : "muted small"}>
        {cancellable
          ? "Cancellable: you can stop this stream later. What has vested stays claimable by the recipient and the rest comes back to you. The recipient will see an amber Cancellable badge."
          : "Not cancellable: once created, nobody can stop or change this stream. This can't be changed later."}
      </p>
      {isNative ? send : <WithApproval token={asset} spender={sandfall} amount={value}>{send}</WithApproval>}
    </Card>
  );
}

function StreamCard({ sandfall, id, title }: { sandfall: Address; id: bigint; title?: string }) {
  const { address } = useConnection();
  const sf = { address: sandfall, abi: sandfallAbi } as const;
  const r = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...sf, functionName: "stream", args: [id] },
      { ...sf, functionName: "claimable", args: [id] },
      { ...sf, functionName: "vestedAmount", args: [id] },
    ],
    query: POLL.query,
  });
  const [s, claimable, vested] = r.data ?? [];
  const isNative = s?.asset === ZERO;
  const meta = useReadContracts({
    allowFailure: false,
    contracts: [
      { address: s?.asset, abi: mockERC20Abi, functionName: "decimals" },
      { address: s?.asset, abi: mockERC20Abi, functionName: "symbol" },
    ],
    query: { enabled: !!s && !isNative, staleTime: Infinity },
  });
  const now = useNow();
  if (!s) return <div className="lock skeleton" />;
  const [dec, sym] = isNative ? [18, "HYPE"] : (meta.data ?? [18, ""]);
  const decimals = Number(dec);
  const total = s.total;
  const progress = total > 0n ? Number(((vested ?? 0n) * 10_000n) / total) / 100 : 0;
  const rolling = s.kind === 2;
  const finish = rolling ? Number(s.periodFinish) : Number(s.end);

  return (
    <div className="lock">
      <div className="lock-top">
        <div className="lock-badges">
          <Badge tone="silver">{title ?? KINDS[s.kind]}</Badge>
          {s.cancelled ? <Badge tone="red">Cancelled</Badge> : s.cancellable ? <Badge tone="amber">Cancellable</Badge> : <Badge tone="green">Not cancellable</Badge>}
        </div>
        <span className="muted mono">#{id.toString()}</span>
      </div>
      <div className="progress">
        <div className="progress-bar" style={{ width: `${progress}%` }} />
      </div>
      <div className="lock-body">
        <Row k="Vested" v={`${fmt(vested, decimals, 4)} / ${fmt(total, decimals)} ${sym}`} />
        <Row k="Claimed" v={`${fmt(s.claimed, decimals, 4)} ${sym}`} />
        <Row k="From" v={<Addr address={s.creator} />} />
        <Row k="To" v={<Addr address={s.recipient} />} />
        {!rolling && Number(s.cliff) > Number(s.start) && <Row k="Cliff" v={date(Number(s.cliff))} />}
        {rolling ? (
          <Row k="Window" v={`${Number(s.window) / 86400} days, refilled by each top-up`} />
        ) : (
          <Row k="Fully vested" v={finish > now ? `in ${duration(finish - now)}` : date(finish)} />
        )}
        {rolling && finish > now && <Row k="Current window ends" v={`in ${duration(finish - now)}`} />}
      </div>
      <div className="lock-actions">
        {address === s.recipient && (
          <TxButton className="btn btn-sm" disabledReason={!claimable ? "Nothing to claim yet" : undefined} request={() => ({ ...sf, functionName: "claim", args: [id] })}>
            Claim {fmt(claimable, decimals, 4)} {sym}
          </TxButton>
        )}
        {address === s.creator && s.cancellable && !s.cancelled && (
          <TxButton className="btn btn-sm btn-danger" request={() => ({ ...sf, functionName: "cancel", args: [id] })}>
            Cancel stream
          </TxButton>
        )}
        {address === s.creator && !s.cancellable && (
          <button className="btn btn-sm btn-ghost" disabled title="This stream was created as not cancellable">
            Cancel (locked)
          </button>
        )}
      </div>
    </div>
  );
}
