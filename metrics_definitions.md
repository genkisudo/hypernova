# Hypernova Final Dashboard — Metrics Definitions

How every metric in `final_dune_queries/` is defined, calculated, and sourced on-chain. All data lives on **Arbitrum** in the `hypernova_arbitrum` schema.

This covers only the 13 production queries in this folder. For the full project-wide reference — including queries not wired to this dashboard — see `../metrics_reference/metrics_definitions.md`.

**Revenue consistency:** All revenue and paid-account metrics in this folder use verified payment matching (aggregate cap or rank-pairing). No query in this folder uses raw transfer sums — orphan and duplicate payments are excluded everywhere.

---

## 1. Unique Traders

| | |
|---|---|
| **Definition** | Distinct wallet addresses that created at least one eval account |
| **On-chain source** | `COUNT(DISTINCT trader)` from `tradingaccounts_evt_evalaccountcreated` |
| **Scope** | All-time, all account types (paid and free) |
| **Query file** | `headline_counter.sql` |
| **Notes** | A wallet that only sent a USDC payment but never created an account is NOT counted. |

---

## 2. Paid / Free / Total Eval Accounts

| | |
|---|---|
| **Definition** | Eval accounts split into paid (backed by a verified USDC payment) vs. free (granted, no matching payment), plus the all-time total |
| **On-chain source** | `erc20_arbitrum.evt_Transfer` joined to `tradingaccounts_evt_evalaccountcreated` |
| **Payment address** | `0x924e3Ed4fc2130b103470270B403b2A4ac808240` |
| **USDC contract** | `0xaf88d065e77c8cc2239327c5edb3a432268e5831` (native USDC, 6 decimals) |
| **Query file** | `headline_counter.sql` |

### Why this metric exists

The contract writes a list price (`assessmentFee`) on every eval account at creation — **including free grants**. Counting `assessmentFee > 0` would overcount. The only proof of payment is a matching USDC transfer.

### Calculation (aggregate cap method)

1. Group USDC transfers to the payment address by `(sender, amount)` → `n_payments`
2. Group eval accounts by `(trader, assessmentFee)` → `n_accounts`
3. Left-join on `(trader = sender, assessmentFee = amount)`
4. `paid = LEAST(n_payments, n_accounts)`, `free = n_accounts − paid`, `total = n_accounts`

This is a conservative 1:1 cap — one payment can back at most one account, one account needs exactly one payment. It does **not** identify *which specific* account a payment funded; it's used in `headline_counter.sql` and `query_paid_vs_free_users.sql` where only totals are needed.

The revenue queries (`revenue.sql`, `revenue_24h.sql`, `revenue_7d.sql`, `revenue_30d.sql`) use the **rank-pairing** variant instead — see metric #7 below.

### Validation

Per the query's own header comment, validated 2026-06-12: **246 paid + 161 free = 407 total accounts, 247 unique traders.**

---

## 3. Daily & Cumulative Eval Signups / Traders

| | |
|---|---|
| **Definition** | Per-day new eval account creations and new traders (first-eval-day attribution), each with a running cumulative total |
| **On-chain source** | `tradingaccounts_evt_evalaccountcreated` |
| **Query file** | `eval_accs.sql` |

### Output columns

| Column | Description |
|---|---|
| `day` | Calendar date of account creation (`evt_block_date`) |
| `new_eval_accounts` | Distinct eval accounts created that day |
| `cumulative_eval_accounts` | Running sum of `new_eval_accounts`, ordered by day |
| `new_traders` | Wallets whose *first ever* eval account falls on this day |
| `cumulative_unique_traders` | Running sum of `new_traders`, ordered by day — a true distinct trader count, not a re-count of repeat visitors |

### Notes

One query, two widgets: a counter reads row 1 (`ORDER BY day DESC`, i.e. the latest day's totals); a line chart plots the full day-by-day series. This version does not split by paid/free, and does not expose an `avg_evals_per_trader` ratio (present in the project-wide `query_7698969_eval_accounts.sql` but not in this trimmed dashboard query).

---

## 4. Eval Pass Rate

| | |
|---|---|
| **Definition** | Share of eval accounts that went on to pass (an `EvalPassed` event), as a percentage |
| **Formula** | `pass_rate_pct = passed_evals / eval_accounts × 100` |
| **On-chain source** | `eval_accounts` = `COUNT(*)` from `tradingaccounts_evt_evalaccountcreated`; `passed_evals` = `COUNT(*)` from `tradingaccounts_evt_evalpassed` |
| **Query file** | `eval_passing_rate.sql` |
| **Notes** | Counts **events**, not traders or accounts — a trader who took multiple eval attempts is counted once per attempt. (Prior to 2026-06-16 this column was named `funded_accounts`, which incorrectly implied it counted `FundedAccountCreated` events; renamed to `passed_evals` to match what it actually counts.) |

---

## 5. On-Chain Eval Rules

| | |
|---|---|
| **Definition** | Current daily drawdown limit, max drawdown limit, and profit target, as written on-chain — converted from basis points to a percentage |
| **On-chain source** | `dailyDrawdownLimit`, `maxDrawdownLimit`, `profitTarget` from `tradingaccounts_evt_evalaccountcreated` |
| **Query file** | `onchain_rules.sql` |

### Calculation

`pct = bps / 100`, formatted as a string with a trailing `%` (1 BPS = 0.01%).

### Notes

Returns the most recent occurrence of each **distinct** `(dailyDrawdownLimit, maxDrawdownLimit, profitTarget)` combination (`ROW_NUMBER() ... ORDER BY evt_block_time DESC`, keep `rn <= 1`). If multiple rule tiers are active simultaneously, each tier appears as its own row.

---

## 6. Paid vs Free Users (Trader-Level)

| | |
|---|---|
| **Definition** | Trader-level classification based on payment history, rolled up from the account-level paid/free split (metric #2) |
| **Query file** | `query_paid_vs_free_users.sql` |

### Segments

| Segment | Definition |
|---|---|
| `total_users` | Every trader in the eval-account universe |
| `paid_users` | Has at least one paid eval account |
| `free_users` | All eval accounts are grants (zero paid) |
| `mixed_users` | Has both paid AND free accounts (subset of `paid_users`) |
| `fully_paid_users` | All accounts are paid (= `paid_users` − `mixed_users`) |

### Notes

- A mixed trader counts as a **paid user** in the headline split.
- Wallets that paid but never created an account are excluded from the universe by construction (4 × $60 as of 2026-06-12, per the query's own comment).
- **"Mixed" has no notion of order** — it only means the trader owns at least one of each, regardless of whether the free or the paid account came first.
- The query returns exactly these 5 columns. (Prior to 2026-06-16 it also exposed `paid_accounts_check` and `total_accounts_check` — dev-time reconciliation sums never referenced by any doc — which have since been removed.)

---

## 7. Assessment Revenue (Verified)

| | |
|---|---|
| **Definition** | USDC received from eval account purchases — only payments that match 1:1 with an eval account creation, with orphan and duplicate payments excluded |
| **On-chain source** | `erc20_arbitrum.evt_transfer` rank-paired against `tradingaccounts_evt_evalaccountcreated` |
| **Payment address** | `0x924e3Ed4fc2130b103470270B403b2A4ac808240` |
| **USDC contract** | `0xaf88d065e77c8cc2239327c5edb3a432268e5831` (native USDC, 6 decimals) |

### Calculation (rank-pairing method)

1. Number each USDC transfer to the payment address per `(sender, amount)` chronologically: `ROW_NUMBER() OVER (PARTITION BY "from", value ORDER BY evt_block_time) AS k`
2. Number each eval account per `(trader, assessmentFee)` chronologically: `ROW_NUMBER() OVER (PARTITION BY trader, assessmentFee ORDER BY evt_block_time) AS k`
3. `INNER JOIN` on `(trader = sender, assessmentFee = amount, payments.k = accounts.k)` — only matched rows survive; orphan and duplicate payments are excluded
4. Sum matched payment amounts for revenue; count matched rows for purchased-account counts

This produces **identical totals** to the aggregate-cap method in metric #2: `SUM(purchased_accounts)` from `revenue.sql` = `paid_eval_accounts` from `headline_counter.sql`. The rank-pairing additionally identifies *which* payment backs *which* account, allowing correct time-windowed revenue (the k-th payment's timestamp determines which window it falls in).

### Why rank-pairing requires a full-history scan

For windowed queries (24h/7d/30d), the full payment history since platform launch is scanned to build correct rank assignments — then the final output is filtered to payments within the trailing window. Windowing the *input* would shift rank values (e.g., the 5th payment becomes k=1 if the first 4 fall outside the window), breaking the 1:1 match.

### Query files

| File | Window | Output columns |
|---|---|---|
| `revenue.sql` | All-time, grouped by fee tier | `amount_usdc`, `purchased_accounts`, `tier_revenue_usdc`, `grand_total_revenue_usdc` |
| `revenue_24h.sql` | Trailing 24 hours | `revenue_usdc_24h` |
| `revenue_7d.sql` | Trailing 7 days | `revenue_usdc_7d` |
| `revenue_30d.sql` | Trailing 30 days | `revenue_usdc_30d` |

---

## 8. Payout Latency (Sign-to-Payout)

| | |
|---|---|
| **Definition** | Time elapsed between a trader signing the EIP-712 payout request and that `requestPayout` call landing on-chain |
| **Formula** | `latency_sec = 600 − (_deadline − call_block_time)` |
| **On-chain source** | `tradingaccounts_call_requestpayout` (`_deadline` parameter), filtered to `call_success = true` |
| **Query file** | `payouts_latency.sql` |

### Why only this window is measurable

`requestPayout` (TradingAccounts) and `processPayout` (Vault) execute atomically in the same transaction, so on-chain settlement itself has zero measurable latency. The only latency worth measuring is off-chain: EIP-712 signing → relayer submission. There's no on-chain signing timestamp, so it's derived from the signed `_deadline`, which the frontend sets to `signing_time + 600s`.

### Output columns

| Column | Description |
|---|---|
| `payouts` | Count of successful `requestPayout` calls |
| `min_sec` / `max_sec` / `avg_sec` | Distribution of derived sign-to-payout latency |

### Notes

The query's own comment flags the 600-second offset as "inferred ... pending eng confirmation," with an observed TTL drift of 592–599 seconds. This has since been independently confirmed by Hypernova engineering (2026-06-11) — see `../payout_flow_analysis.md` for the full derivation and worked example.

---

## 9. Payout Profit Split

| | |
|---|---|
| **Definition** | Platform-wide split of gross payout USDC between traders and the protocol |
| **On-chain source** | `vault_evt_payoutprocessed` (`traderAmount + protocolAmount = gross payout`) |
| **Query file** | `profit-split.sql` |

### Output columns

| Column | Calculation |
|---|---|
| `unique_traders` | `COUNT(DISTINCT trader)` |
| `total_payouts` | `COUNT(*)` of payout events |
| `total_trader_usdc` / `total_protocol_usdc` | `SUM(traderAmount)` / `SUM(protocolAmount)`, ÷ `1e6` |
| `total_gross_usdc` | `total_trader_usdc + total_protocol_usdc` |
| `trader_pct` / `protocol_pct` | Each side's USDC ÷ `total_gross_usdc` × 100 |

---

## 10. Proof of Payouts (Activity Feed)

| | |
|---|---|
| **Definition** | The 20 most recent processed payouts, formatted for a public-facing activity table |
| **On-chain source** | `vault_evt_payoutprocessed`, `ORDER BY evt_block_time DESC LIMIT 20` |
| **Query file** | `proof_of_payouts.sql` |

### Output columns

| Column | Description |
|---|---|
| `source_vault` | Truncated Vault contract address |
| `payout_time` | `evt_block_time`, native timestamp |
| `tx_hash` | Truncated transaction hash |
| `trader_wallet` | Truncated recipient address |
| `status` | Hardcoded `✅ Settled` badge — not derived from any on-chain status field |
| `usdc_payout` | `traderAmount / 1e6`, rounded to 2 decimals |

### Notes

Display-only. Truncated addresses/hashes are for readability, not unique keys — do not use them for joins or deduplication.

---

## 11. Proof of Funds (Treasury Reconstruction)

| | |
|---|---|
| **Definition** | Reconstructed USDC balance held by the Vault and Treasury wallets, derived by netting every inbound/outbound transfer since a fixed cutoff date |
| **On-chain source** | `erc20_arbitrum.evt_transfer` (USDC only), joined to `tokens.erc20` for the display symbol |
| **Tracked wallets** | Vault `0x920973eEBffd3bF7da14dd9fB52Bd3BeA1664c67`, Treasury `0x43C5F0a81d538a527DbF35D27faa583AC7FADA07` |
| **Cutoff date** | 2026-03-25 (platform launch) |
| **Query file** | `proof_of_funds.sql` |

### Calculation

1. Sum all outbound USDC transfers `FROM` each tracked wallet since the cutoff (negative)
2. Sum all inbound USDC transfers `TO` each tracked wallet since the cutoff (positive)
3. `balance = SUM(inflows) + SUM(outflows)` per wallet

### Notes

There is no balance table available via Dune's decoding for these contracts, so this is a flow-based reconstruction, not a literal balance read. The cutoff matches platform launch (2026-03-25), so the reconstruction covers the full life of the platform and the reported balance is exact, not a lower bound. (Prior to 2026-06-16 the cutoff was 2026-04-01, which missed the platform's first week of flows — fixed.)

---

## Common Constants

| Constant | Value |
|---|---|
| Hypernova payment address | `0x924e3Ed4fc2130b103470270B403b2A4ac808240` |
| USDC contract (Arbitrum native) | `0xaf88d065e77c8cc2239327c5edb3a432268e5831` |
| USDC decimals | 6 (divide raw values by `1e6`) |
| Vault contract/wallet | `0x920973eEBffd3bF7da14dd9fB52Bd3BeA1664c67` |
| Treasury wallet | `0x43C5F0a81d538a527DbF35D27faa583AC7FADA07` |
| Platform launch date / partition-pruning & proof-of-funds cutoff | 2026-03-25 |
| EIP-712 deadline offset | 600 seconds (constant across all payouts) |

---

## Query Index

| File | Dashboard widget | Metrics produced |
|---|---|---|
| `headline_counter.sql` | Counters | unique_traders, paid/free/total eval accounts |
| `eval_accs.sql` | Counter + line chart | Daily/cumulative eval accounts and traders |
| `eval_passing_rate.sql` | Counter | eval_accounts, passed_evals, pass_rate_pct |
| `onchain_rules.sql` | Table | Current drawdown/profit-target rules (%) |
| `query_paid_vs_free_users.sql` | Counters | Paid/free/mixed/fully-paid user counts |
| `revenue.sql` | Table | Verified revenue by fee tier (rank-pairing) |
| `revenue_24h.sql` | Counter | Verified revenue, trailing 24h |
| `revenue_7d.sql` | Counter | Verified revenue, trailing 7d |
| `revenue_30d.sql` | Counter | Verified revenue, trailing 30d |
| `payouts_latency.sql` | Counter | Sign-to-payout latency (min/max/avg sec) |
| `profit-split.sql` | Counters | Trader/protocol gross payout split |
| `proof_of_payouts.sql` | Table | Recent payout activity feed |
| `proof_of_funds.sql` | Table | Reconstructed Vault & Treasury balances |
