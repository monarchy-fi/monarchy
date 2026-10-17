import { useMemo, useState } from "react";
import { useConnection, useReadContract, useReadContracts } from "wagmi";
import { erc721Abi, isAddress, parseUnits, type Address } from "viem";
import { exileAbi, mockERC20Abi } from "../abi";
import { TAGLINES, TierBadge } from "../components/Tiers";
import { TxButton, WithApproval } from "../components/Tx";
import { Addr, Badge, Card, Empty, Row, Stat } from "../components/Ui";
import { useDeployment } from "../lib/deployments";
import { date, duration, fmt, label, mult } from "../lib/format";
import { POLL, useNow, useTicking } from "../lib/hooks";
import { useLodestarCore, type TokenMeta } from "../lib/monarchy";
import { days } from "./Home";

type Tier = { minDuration: number; multiplierBps: number; label: `0x${string}` };
// a tx can sit in the mempool for a bit; pad so the chosen tier still qualifies when it lands
const BUFFER = 10 * 60;

export function ExilePage() {
  const d = useDeployment();
  const core = useLodestarCore();
  const [tab, setTab] = useState<"tokens" | "nfts">("tokens");
  const poolId = core.exilePoolId;
  const pool = useReadContract({
    address: d?.exile,
    abi: exileAbi,
    functionName: "poolInfo",
    args: [poolId ?? 0n],
    query: { enabled: !!d && poolId !== undefined, ...POLL.query },
  });
  const tiers = (pool.data?.tiers ?? []) as readonly Tier[];
  const now = useNow();
  const rewardMeta = core.quoteMeta;
  const dripPerDay =
    pool.data && Number(pool.data.periodFinish) > now ? (pool.data.rewardRate * 86400n) / 10n ** 18n : 0n;

  if (!d) return <NoDeployment />;
  return (
    <div className="page">
      <header className="page-head">
        <h1>Exile</h1>
        <p className="muted">
          Lock tokens, LP or NFTs. A lock can be extended but never shortened, cancelled or transferred. Longer
          locks earn a bigger share of holder rewards.
        </p>
      </header>

      <Card title={`${core.tokenMeta?.symbol ?? "MONARCH"} holder rewards`}>
        <div className="stats">
          <Stat label="Dripping now" value={`${fmt(dripPerDay, rewardMeta?.decimals ?? 6)} ${rewardMeta?.symbol ?? ""}/day`} hint="each deposit drips out over 7 days" />
          <Stat label="Paid in so far" value={`${fmt(pool.data?.totalDistributed, rewardMeta?.decimals ?? 6)} ${rewardMeta?.symbol ?? ""}`} />
          <Stat label="Locked points" value={fmt(pool.data?.totalPoints, core.tokenMeta?.decimals ?? 18, 0)} hint="amount × multiplier" />
          <Stat label="Drip ends" value={pool.data ? (Number(pool.data.periodFinish) > now ? duration(Number(pool.data.periodFinish) - now) : "idle") : "…"} hint="refills on every Lodestar distribute" />
        </div>
      </Card>

      <div className="tabs">
        <button className={tab === "tokens" ? "tab active" : "tab"} onClick={() => setTab("tokens")}>
          Lock tokens
        </button>
        <button className={tab === "nfts" ? "tab active" : "tab"} onClick={() => setTab("nfts")}>
          Lock NFTs
        </button>
      </div>

      {tab === "tokens" ? (
        <LockTokens exile={d.exile} token={core.token} tokenMeta={core.tokenMeta} poolId={poolId} tiers={tiers} />
      ) : (
        <LockNfts exile={d.exile} />
      )}

      <MyLocks exile={d.exile} tiers={tiers} rewardMeta={rewardMeta} />
    </div>
  );
}

function LockTokens({
  exile,
  token: defaultToken,
  tokenMeta,
  poolId,
  tiers,
}: {
  exile: Address;
  token?: Address;
  tokenMeta?: TokenMeta;
  poolId?: bigint;
  tiers: readonly Tier[];
}) {
  const { address } = useConnection();
  const [custom, setCustom] = useState("");
  const [amount, setAmount] = useState("");
  const [lockDays, setLockDays] = useState(30);
  const [plain, setPlain] = useState(false);
  const token = plain && isAddress(custom) ? custom : defaultToken;
  const meta = useReadContracts({
    allowFailure: false,
    contracts: [
      { address: token, abi: mockERC20Abi, functionName: "decimals" },
      { address: token, abi: mockERC20Abi, functionName: "symbol" },
      { address: token, abi: mockERC20Abi, functionName: "balanceOf", args: [address ?? "0x0000000000000000000000000000000000000000"] },
    ],
    query: { enabled: !!token, ...POLL.query },
  });
  const [decimals, symbol, balance] = meta.data ?? [tokenMeta?.decimals ?? 18, tokenMeta?.symbol ?? "", undefined];
  const value = safeParse(amount, Number(decimals));
  const seconds = lockDays * 86400;
  const tier = plain ? undefined : pickTier(tiers, seconds);
  const unlockAt = Math.floor(Date.now() / 1000) + seconds + BUFFER;

  return (
    <Card title="New lock">
      <label className="check">
        <input type="checkbox" checked={plain} onChange={(e) => setPlain(e.target.checked)} />
        Lock a different token or LP (no rewards)
      </label>
      {plain && (
        <input className="input" placeholder="Token or LP address 0x…" value={custom} onChange={(e) => setCustom(e.target.value.trim())} />
      )}
      {!plain && (
        <div className="tiers pick">
          {tiers.map((t) => {
            const name = label(t.label);
            const active = tier?.label === t.label;
            return (
              <button key={name} className={`tier tier-${name.toLowerCase()} ${active ? "active" : ""}`} onClick={() => setLockDays(t.minDuration / 86400)}>
                <TierBadge name={name} />
                <div className="tier-mult">{mult(t.multiplierBps)}</div>
                <div className="tier-len">{days(t.minDuration)}</div>
                <div className="tier-tag">{TAGLINES[name] ?? ""}</div>
              </button>
            );
          })}
        </div>
      )}
      <div className="form">
        <label>
          Amount {symbol && <span className="muted">({symbol})</span>}
          <div className="input-row">
            <input className="input" inputMode="decimal" placeholder="0.0" value={amount} onChange={(e) => setAmount(e.target.value)} />
            {balance !== undefined && (
              <button className="btn btn-ghost btn-sm" onClick={() => setAmount(fmtPlain(balance as bigint, Number(decimals)))}>
                Max {fmt(balance as bigint, Number(decimals))}
              </button>
            )}
          </div>
        </label>
        <label>
          Lock for (days)
          <input className="input" type="number" min={1} value={lockDays} onChange={(e) => setLockDays(Math.max(0, Number(e.target.value)))} />
        </label>
      </div>
      <div className="summary">
        <Row k="Unlocks" v={date(unlockAt)} />
        {!plain && <Row k="Tier" v={tier ? <><TierBadge name={label(tier.label)} /> {mult(tier.multiplierBps)}</> : <Badge tone="red">Below the first tier: no rewards</Badge>} />}
        {!plain && value > 0n && tier && <Row k="Points" v={fmt((value * BigInt(tier.multiplierBps)) / 10_000n, Number(decimals))} />}
        <Row k="Cancellable" v={<Badge tone="green">Not cancellable</Badge>} />
      </div>
      <WithApproval token={token} spender={exile} amount={value}>
        <TxButton
          disabledReason={!token ? "Pick a token" : value === 0n ? "Enter an amount" : lockDays <= 0 ? "Pick a lock length" : undefined}
          request={() =>
            token && {
              address: exile,
              abi: exileAbi,
              functionName: "lockERC20",
              args: [token, value, BigInt(unlockAt), plain ? 0n : (poolId ?? 0n)],
            }
          }
          onDone={() => setAmount("")}
        >
          Lock {symbol}
        </TxButton>
      </WithApproval>
      <p className="muted small">Unlock times round up to the next hour. Rewards drip in over 7 days and stop the second a lock ends.</p>
    </Card>
  );
}

function LockNfts({ exile }: { exile: Address }) {
  const { address } = useConnection();
  const [kind, setKind] = useState<"721" | "1155">("721");
  const [collection, setCollection] = useState("");
  const [id, setId] = useState("");
  const [amount, setAmount] = useState("1");
  const [lockDays, setLockDays] = useState(30);
  const ok = isAddress(collection);
  const approved = useReadContract({
    address: ok ? collection : undefined,
    abi: erc721Abi,
    functionName: "isApprovedForAll",
    args: [address ?? "0x0000000000000000000000000000000000000000", exile],
    query: { enabled: ok && !!address, ...POLL.query },
  });
  const unlockAt = BigInt(Math.floor(Date.now() / 1000) + lockDays * 86400 + BUFFER);
  const tokenId = /^\d+$/.test(id) ? BigInt(id) : undefined;
  return (
    <Card title="Lock an NFT">
      <p className="muted small">ERC-721 or ERC-1155. NFT locks hold the item until the unlock date and don't earn rewards.</p>
      <div className="form">
        <label>
          Standard
          <select className="input" value={kind} onChange={(e) => setKind(e.target.value as "721" | "1155")}>
            <option value="721">ERC-721</option>
            <option value="1155">ERC-1155</option>
          </select>
        </label>
        <label>
          Collection
          <input className="input" placeholder="0x…" value={collection} onChange={(e) => setCollection(e.target.value.trim())} />
        </label>
        <label>
          Token id
          <input className="input" value={id} onChange={(e) => setId(e.target.value.trim())} />
        </label>
        {kind === "1155" && (
          <label>
            Amount
            <input className="input" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </label>
        )}
        <label>
          Lock for (days)
          <input className="input" type="number" min={1} value={lockDays} onChange={(e) => setLockDays(Number(e.target.value))} />
        </label>
      </div>
      {ok && approved.data === false ? (
        <TxButton request={() => ({ address: collection as Address, abi: erc721Abi, functionName: "setApprovalForAll", args: [exile, true] })}>
          Approve collection
        </TxButton>
      ) : (
        <TxButton
          disabledReason={!ok ? "Enter a collection" : tokenId === undefined ? "Enter a token id" : undefined}
          request={() =>
            kind === "721"
              ? { address: exile, abi: exileAbi, functionName: "lockERC721", args: [collection as Address, tokenId!, unlockAt] }
              : { address: exile, abi: exileAbi, functionName: "lockERC1155", args: [collection as Address, tokenId!, BigInt(amount || "0"), unlockAt] }
          }
        >
          Lock NFT
        </TxButton>
      )}
    </Card>
  );
}

function MyLocks({ exile, tiers, rewardMeta }: { exile: Address; tiers: readonly Tier[]; rewardMeta?: TokenMeta }) {
  const { address } = useConnection();
  const ids = useReadContract({
    address: exile,
    abi: exileAbi,
    functionName: "lockIdsOf",
    args: [address ?? "0x0000000000000000000000000000000000000000"],
    query: { enabled: !!address, ...POLL.query },
  });
  const list = useMemo(() => [...(ids.data ?? [])].reverse(), [ids.data]);
  return (
    <Card title="My locks">
      {!address && <Empty>Connect a wallet to see your locks.</Empty>}
      {address && list.length === 0 && <Empty>No locks yet. Everyone starts somewhere.</Empty>}
      <div className="locks">
        {list.map((id) => (
          <LockCard key={id.toString()} exile={exile} id={id} tiers={tiers} rewardMeta={rewardMeta} />
        ))}
      </div>
    </Card>
  );
}

function LockCard({ exile, id, tiers, rewardMeta }: { exile: Address; id: bigint; tiers: readonly Tier[]; rewardMeta?: TokenMeta }) {
  const base = { address: exile, abi: exileAbi } as const;
  const r = useReadContracts({
    allowFailure: false,
    contracts: [
      { ...base, functionName: "lockInfo", args: [id] },
      { ...base, functionName: "pendingRewards", args: [id] },
      { ...base, functionName: "earningRatePerSecond", args: [id] },
    ],
    query: POLL.query,
  });
  const [lock, pending, rate] = r.data ?? [];
  const live = useTicking(pending, rate);
  const now = useNow();
  const [extendDays, setExtendDays] = useState(30);
  const dec = useReadContract({
    address: lock?.asset,
    abi: mockERC20Abi,
    functionName: "decimals",
    query: { enabled: !!lock && lock.kind === 0, staleTime: Infinity },
  });
  if (!lock) return <div className="lock skeleton" />;

  const unlockAt = Number(lock.unlockAt);
  const ended = now >= unlockAt;
  const kind = ["Token", "ERC-721", "ERC-1155"][lock.kind];
  const tier = tiers.find((t) => t.multiplierBps === lock.multiplierBps);
  const name = lock.poolId === 0n ? "" : tier ? label(tier.label) : "";
  const newUnlock = Math.max(unlockAt, now) + extendDays * 86400;
  const newTier = pickTier(tiers, newUnlock - now);
  const rd = rewardMeta?.decimals ?? 6;
  const amountDec = lock.kind === 0 ? Number(dec.data ?? 18) : 0;

  return (
    <div className={`lock ${ended ? "lock-ended" : ""}`}>
      <div className="lock-top">
        <div className="lock-badges">
          {lock.poolId !== 0n ? <TierBadge name={name} /> : <Badge tone="grey">{kind} lock</Badge>}
          <Badge tone="green">Not cancellable</Badge>
          {lock.withdrawn ? <Badge tone="grey">Withdrawn</Badge> : ended ? <Badge tone="amber">Unlocked</Badge> : <Badge tone="silver">Locked</Badge>}
        </div>
        <span className="muted mono">#{id.toString()}</span>
      </div>
      <div className="lock-body">
        <Row k="Asset" v={<Addr address={lock.asset} />} />
        {lock.kind !== 0 && <Row k="Token id" v={lock.tokenId.toString()} />}
        <Row k="Amount" v={lock.kind === 1 ? "1" : fmt(lock.amount, amountDec)} />
        <Row k={ended ? "Unlocked" : "Unlocks in"} v={ended ? date(unlockAt) : `${duration(unlockAt - now)} (${date(unlockAt)})`} />
        {lock.poolId !== 0n && (
          <>
            <Row k="Multiplier" v={mult(lock.multiplierBps)} />
            <Row
              k="Rewards"
              v={
                <span className={rate && rate > 0n ? "ticking gold" : ""}>
                  {fmt(live, rd, 6)} {rewardMeta?.symbol}
                </span>
              }
            />
            <Row k="Earning" v={rate && rate > 0n ? `${fmt((rate * 86400n) / 10n ** 18n, rd, 4)} ${rewardMeta?.symbol}/day` : ended ? "stopped at unlock" : "waiting for the next drip"} />
          </>
        )}
      </div>
      <div className="lock-actions">
        {lock.poolId !== 0n && (
          <TxButton className="btn btn-sm" disabledReason={!pending ? "Nothing to claim" : undefined} request={() => ({ ...base, functionName: "claimRewards", args: [id] })}>
            Claim
          </TxButton>
        )}
        {!lock.withdrawn && (
          <div className="extend">
            <input className="input input-sm" type="number" min={1} value={extendDays} onChange={(e) => setExtendDays(Number(e.target.value))} />
            <span className="muted small">days</span>
            <TxButton className="btn btn-sm btn-ghost" request={() => ({ ...base, functionName: "extend", args: [id, BigInt(newUnlock + BUFFER)] })}>
              Extend{lock.poolId !== 0n && newTier && newTier.multiplierBps > lock.multiplierBps ? ` to ${label(newTier.label)}` : ""}
            </TxButton>
          </div>
        )}
        {!lock.withdrawn && (
          <TxButton className="btn btn-sm btn-ghost" disabledReason={!ended ? "Still locked" : undefined} request={() => ({ ...base, functionName: "withdraw", args: [id] })}>
            Withdraw
          </TxButton>
        )}
      </div>
    </div>
  );
}

function pickTier(tiers: readonly Tier[], seconds: number): Tier | undefined {
  let best: Tier | undefined;
  for (const t of tiers) if (seconds >= t.minDuration) best = t;
  return best;
}

function safeParse(v: string, decimals: number): bigint {
  try {
    return v ? parseUnits(v as `${number}`, decimals) : 0n;
  } catch {
    return 0n;
  }
}

function fmtPlain(v: bigint, decimals: number): string {
  const s = v.toString().padStart(decimals + 1, "0");
  const whole = s.slice(0, s.length - decimals);
  const frac = s.slice(s.length - decimals).replace(/0+$/, "");
  return frac ? `${whole}.${frac}` : whole;
}

export function NoDeployment() {
  return (
    <div className="page">
      <Card>
        <Empty>No Monarchy deployment on this network. Switch to Elysium Testnet, or run the local demo and switch to Localhost 8545.</Empty>
      </Card>
    </div>
  );
}

export { safeParse, fmtPlain };
