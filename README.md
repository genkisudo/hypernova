# Hypernova — Dashboard Query Reference

Production DuneSQL queries powering the live Hypernova dashboard. **Chain:** Arbitrum. **Schema:** `hypernova_arbitrum`. Every query here is wired to a dashboard widget — this is not the exploratory/scratch layer (see `../` for analysis drafts and validation notes).

For contract architecture and the full decoded-table reference, see `../CLAUDE.md` and `../hypernova_arbitrum_tables.md`.

---

## 1. Query Catalog

### Acquisition & Eval Funnel

| File | Widget | Purpose | Key Output Columns |
|---|---|---|---|
| `headline_counter.sql` | Counters | Unique traders + paid/free/total eval account split | `unique_traders`, `paid_eval_accounts`, `free_eval_accounts`, `total_eval_accounts` |
| `eval_accs.sql` | Counter + line chart | Daily new eval accounts and traders, with running cumulative totals | `day`, `new_eval_accounts`, `cumulative_eval_accounts`, `new_traders`, `cumulative_unique_traders` |
| `eval_passing_rate.sql` | Counter | Eval → pass conversion rate | `eval_accounts`, `funded_accounts`, `pass_rate_pct` |
| `onchain_rules.sql` | Table | Current eval risk/profit parameters, as written on-chain | `daily_drawdown_pct`, `max_drawdown_pct`, `profit_target_pct` |
| `query_paid_vs_free_users.sql` | Counters | Trader-level payment segmentation (paid / free / mixed) | `total_users`, `paid_users`, `free_users`, `mixed_users`, `fully_paid_users` |

### Revenue

| File | Widget | Purpose | Key Output Columns |
|---|---|---|---|
| `revenue.sql` | Table | All-time assessment revenue, grouped by fee tier | `amount_usdc`, `purchased_accounts`, `tier_revenue_usdc`, `grand_total_revenue_usdc` |
| `revenue_24h.sql` | Counter | Assessment revenue, trailing 24 hours | `revenue_usdc_24h` |
| `revenue_7d.sql` | Counter | Assessment revenue, trailing 7 days | `revenue_usdc_last_week` |
| `revenue_30d.sql` | Counter | Assessment revenue, trailing 30 days | `revenue_usdc_last_week` |

### Payouts & Treasury

| File | Widget | Purpose | Key Output Columns |
|---|---|---|---|
| `payouts_latency.sql` | Counter | Sign-to-payout latency (EIP-712 deadline derived) | `payouts`, `min_sec`, `max_sec`, `avg_sec` |
| `profit-split.sql` | Counters | Platform-wide payout totals and trader/protocol split | `total_trader_usdc`, `total_protocol_usdc`, `trader_pct`, `protocol_pct` |
| `proof_of_payouts.sql` | Table | Recent payout activity feed (public-facing) | `payout_time`, `tx_hash`, `trader_wallet`, `usdc_payout` |
| `proof_of_funds.sql` | Table | Reconstructed Vault & Treasury USDC balances | `wallet`, `symbol`, `balance` |

---

## 2. On-Chain Data Sources

| Table | Description | Used By |
|---|---|---|
| `hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated` | Eval account creation events — `trader`, `evalAccountId`, `assessmentFee`, drawdown/profit-target params | `headline_counter`, `eval_accs`, `eval_passing_rate`, `onchain_rules`, `query_paid_vs_free_users`, `revenue*` (trader universe) |
| `hypernova_arbitrum.tradingaccounts_evt_evalpassed` | Eval-passed events | `eval_passing_rate` |
| `hypernova_arbitrum.tradingaccounts_call_requestpayout` | Decoded `requestPayout` calls — includes the signed `_deadline` parameter | `payouts_latency` |
| `hypernova_arbitrum.vault_evt_payoutprocessed` | Payout settlement events — `trader`, `traderAmount`, `protocolAmount` | `profit-split`, `proof_of_payouts` |
| `erc20_arbitrum.evt_transfer` | Generic ERC-20 `Transfer` events (USDC inflows/outflows) | `headline_counter`, `query_paid_vs_free_users`, `revenue*`, `proof_of_funds` |
| `tokens.erc20` | Dune spellbook token metadata (symbol lookup) | `proof_of_funds` |

---

## 3. Core Methodology

### 3.1 Paid vs. Free Verification

The contract writes `assessmentFee` (the list price) onto **every** eval account, including ones granted for free during closed beta/alpha. There is no on-chain "paid" flag, so payment must be reconstructed by matching USDC transfers.

**Method** (`headline_counter.sql`, `query_paid_vs_free_users.sql`):

1. Group USDC transfers to the Hypernova payment address by `(sender, amount)` → `n_payments`
2. Group eval accounts by `(trader, assessmentFee)` → `n_accounts`
3. Left-join on `(trader = sender, assessmentFee = amount)`
4. `paid = LEAST(n_payments, n_accounts)` — one payment backs at most one account, one account needs exactly one payment

This is a conservative 1:1 cap, not a precise per-account match (it doesn't determine *which* specific account a payment funded — see `../metrics_reference/metrics_definitions.md` for the rank-pairing variant used when per-account attribution matters).

### 3.2 Revenue: Verified vs. Raw

**This folder uses two different revenue methodologies that disagree by design:**

| | Method | Files |
|---|---|---|
| **Verified** | Caps paid accounts via §3.1's `LEAST()` logic — excludes free grants | `headline_counter.sql`, `query_paid_vs_free_users.sql` |
| **Raw** | Sums *every* USDC transfer from a known eval trader to the payment address — no dedup, no orphan exclusion | `revenue.sql`, `revenue_24h.sql`, `revenue_7d.sql`, `revenue_30d.sql` |

The raw method will overstate revenue whenever an orphan or duplicate payment exists (a trader paid twice for one account, or paid but the account creation tx failed). See §5 for current impact.

### 3.3 Payout Latency

`requestPayout` (TradingAccounts) and `processPayout` (Vault) execute in the same transaction — payout settlement itself is atomic. The only measurable latency is **off-chain**: time from the trader's EIP-712 signature to the relayer landing `requestPayout` on-chain.

There is no on-chain signing timestamp, so `payouts_latency.sql` derives one from the signed `_deadline` parameter, which the frontend sets to `signing_time + 600s`:

```
latency_sec = 600 − (_deadline − call_block_time)
```

The 600-second offset is treated as constant; see `../payout_flow_analysis.md` for the full derivation and engineering confirmation.

### 3.4 Treasury Reconstruction

`proof_of_funds.sql` has no direct balance table to query, so it nets every inbound/outbound USDC transfer to the Vault and Treasury wallets since a fixed cutoff date and sums to a running balance. This is a flow-based reconstruction, not a balance snapshot — see §5 for the cutoff-date caveat.

---

## 4. Metric Glossary

| Metric | Definition | Formula / Source |
|---|---|---|
| `unique_traders` | Distinct wallets that created ≥1 eval account | `COUNT(DISTINCT trader)` on `evalaccountcreated` |
| `paid_eval_accounts` / `free_eval_accounts` | Eval accounts with / without a verified matching payment | §3.1 |
| `pass_rate_pct` | Share of eval accounts that progressed to `EvalPassed` | `evalpassed events / evalaccountcreated events × 100` |
| `daily_drawdown_pct` / `max_drawdown_pct` / `profit_target_pct` | Current eval risk/profit rules | Raw on-chain value (basis points) ÷ 100 |
| `paid_users` / `free_users` / `mixed_users` / `fully_paid_users` | Trader-level payment segments | §3.1, rolled up per trader — `mixed` = has both a paid and a free account, order not considered |
| `revenue_usdc_24h` / `_7d` / `_30d` | Raw USDC inflow from eval traders over the trailing window | §3.2 (raw method) |
| `tier_revenue_usdc` / `grand_total_revenue_usdc` | Raw revenue grouped by fee tier | §3.2 (raw method) |
| `min_sec` / `max_sec` / `avg_sec` (payout latency) | Sign-to-payout latency distribution | §3.3 |
| `total_trader_usdc` / `total_protocol_usdc` | Gross USDC split between trader payouts and protocol take | `SUM(traderAmount)`, `SUM(protocolAmount)` on `payoutprocessed` |
| `trader_pct` / `protocol_pct` | Each side's share of gross payout volume | `side_usdc / (trader_usdc + protocol_usdc) × 100` |
| `balance` (proof of funds) | Net USDC held by Vault / Treasury since the tracking cutoff | §3.4 |

---

## 5. Known Limitations

- **Revenue methodology mismatch:** the headline counters and user-segmentation queries report *verified* revenue/paid-account counts; the four `revenue*.sql` queries report *raw* transfer sums. They will not reconcile exactly. Do not present both on the same dashboard view without labeling the difference.
- **`revenue_7d.sql` and `revenue_30d.sql` share the output alias `revenue_usdc_last_week`** despite covering different windows (7d vs 30d) — a naming artifact to be aware of when wiring widgets, not a logic error.
- **`eval_passing_rate.sql`'s `funded_accounts` column counts `EvalPassed` events**, not `FundedAccountCreated` events. Numerically equivalent today (1:1 in current data) but the alias is a misnomer if that 1:1 relationship ever changes.
- **`proof_of_funds.sql` nets flows from 2026-04-01**, while the platform launched 2026-03-25. Any Vault/Treasury balance accrued in that 7-day gap is not captured — the reported balance is a lower bound, not an exact reserve figure.
- **`onchain_rules.sql` references the table as `TradingAccounts_evt_EvalAccountCreated`** (mixed case) rather than the canonical lowercase form used elsewhere in this folder. DuneSQL resolves it correctly, but it's an inconsistency if this query is used as a template.
- **`mixed_users` (query_paid_vs_free_users.sql) is order-agnostic** — it flags a trader as mixed regardless of whether the free or the paid account came first. See `../users/08_free_to_paid_upgraders.sql` for the order-aware "upgrader" variant (free first, paid later).

---

## 6. Reference Constants

| Constant | Value |
|---|---|
| Hypernova payment address | `0x924e3Ed4fc2130b103470270B403b2A4ac808240` |
| USDC (Arbitrum native) | `0xaf88d065e77c8cc2239327c5edb3a432268e5831` (6 decimals) |
| Vault contract/wallet | `0x920973eEBffd3bF7da14dd9fB52Bd3BeA1664c67` |
| Treasury wallet | `0x43C5F0a81d538a527DbF35D27faa583AC7FADA07` |
| Platform launch | 2026-03-25 |
| EIP-712 payout deadline TTL | 600 seconds (constant) |

---

## 7. Conventions for New Queries

- Header comment block in the `payouts_latency.sql` style: a `====` banner, one-line title (`Hypernova: <Name>`), then a short description of what's computed and how, including any non-obvious methodology or caveats.
- Filter on partition columns (`evt_block_date`, `evt_block_time`) wherever a table supports it — prunes the scan and reduces query cost.
- State explicitly whether a revenue/account metric is **verified** (§3.1) or **raw** (§3.2) — the two are not interchangeable on this dashboard.
- Cross-reference the broader analysis docs in the parent directory (`../payout_flow_analysis.md`, `../hypernova_arbitrum_tables.md`, `../users/README.md`) rather than re-deriving methodology inline.
