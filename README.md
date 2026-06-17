# Hypernova Dune Dashboard Query Reference

 DuneSQL queries powering the live Hypernova dashboard. 
 **Chain:** Arbitrum.
  **Schema:** `hypernova_arbitrum`. 

## Queries

| # | File | Dune ID | Description |
|---|------|---------|-------------|
| Q1 | [`headline_counter.sql`](headline_counter.sql) | — | Unique traders + paid/free/total eval account split |
| Q2 | [`eval_accs.sql`](eval_accs.sql) | — | Daily new eval accounts and traders with cumulative totals |
| Q3 | [`eval_passing_rate.sql`](eval_passing_rate.sql) | — | Eval → pass conversion rate |
| Q4 | [`onchain_rules.sql`](onchain_rules.sql) | — | Current on-chain drawdown/profit-target rules as % |
| Q5 | [`query_paid_vs_free_users.sql`](query_paid_vs_free_users.sql) | — | Trader-level payment segmentation (paid / free / mixed) |
| Q6 | [`revenue.sql`](revenue.sql) | — | Verified assessment revenue by fee tier (all-time) |
| Q7 | [`revenue_24h.sql`](revenue_24h.sql) | — | Verified assessment revenue, trailing 24 hours |
| Q8 | [`revenue_7d.sql`](revenue_7d.sql) | — | Verified assessment revenue, trailing 7 days |
| Q9 | [`revenue_30d.sql`](revenue_30d.sql) | — | Verified assessment revenue, trailing 30 days |
| Q10 | [`payouts_latency.sql`](payouts_latency.sql) | — | Off-chain payout latency (min / max / avg seconds) |
| Q11 | [`profit-split.sql`](profit-split.sql) | — | Trader vs. protocol gross payout split |
| Q12 | [`proof_of_payouts.sql`](proof_of_payouts.sql) | — | 20 most recent payouts (public activity feed) |
| Q13 | [`proof_of_funds.sql`](proof_of_funds.sql) |  [`query`](dune.com/queries/7650637/11604660) | Reconstructed Vault & Treasury USDC balances |
| Q14 | [`registered_no_eval.sql`](registered_no_eval.sql) | — | Wallets registered but never started an eval |

## Key Addresses

| Role | Address |
|------|---------|
| Payment address | `0x924e3Ed4fc2130b103470270B403b2A4ac808240` |
| Vault contract / wallet | `0x920973eEBffd3bF7da14dd9fB52Bd3BeA1664c67` |
| Treasury wallet | `0x43C5F0a81d538a527DbF35D27faa583AC7FADA07` |
| USDC (Arbitrum native, 6 dec) | `0xaf88d065e77c8cc2239327c5edb3a432268e5831` |

For the full decoded-table column reference, see `../hypernova_arbitrum_tables.md`. Contract source is in `trading_accounts.sol` and `vault.sol`.

---

## 1. Query Catalog

### Acquisition & Eval Funnel

| File | Widget | Purpose | Key Output Columns |
|---|---|---|---|
| `headline_counter.sql` | Counters | Unique traders + paid/free/total eval account split + evals-per-trader | `unique_traders`, `paid_eval_accounts`, `free_eval_accounts`, `total_eval_accounts`, `avg_evals_per_trader` |
| `eval_accs.sql` | Counter + line chart | Daily new eval accounts and traders, with running cumulative totals | `day`, `new_eval_accounts`, `cumulative_eval_accounts`, `new_traders`, `cumulative_unique_traders` |
| `eval_passing_rate.sql` | Counter | Eval → pass conversion rate | `eval_accounts`, `passed_evals`, `pass_rate_pct` |
| `onchain_rules.sql` | Table | Current eval risk/profit parameters, as written on-chain | `daily_drawdown_pct`, `max_drawdown_pct`, `profit_target_pct` |
| `query_paid_vs_free_users.sql` | Counters | Trader-level payment segmentation (paid / free / mixed) + account-level totals | `total_users`, `paid_users`, `free_users`, `mixed_users`, `fully_paid_users`, `paid_eval_accounts`, `free_eval_accounts`, `total_eval_accounts`, `ratio_free_who_purchased_pct` |

### Revenue

| File | Widget | Purpose | Key Output Columns |
|---|---|---|---|
| `revenue.sql` | Table | Verified assessment revenue, grouped by fee tier | `amount_usdc`, `purchased_accounts`, `tier_revenue_usdc`, `grand_total_revenue_usdc` |
| `revenue_24h.sql` | Counter | Verified assessment revenue, trailing 24 hours | `revenue_usdc_24h` |
| `revenue_7d.sql` | Counter | Verified assessment revenue, trailing 7 days | `revenue_usdc_7d` |
| `revenue_30d.sql` | Counter | Verified assessment revenue, trailing 30 days | `revenue_usdc_30d` |

### Payouts & Treasury

| File | Widget | Purpose | Key Output Columns |
|---|---|---|---|
| `payouts_latency.sql` | Counter | Sign-to-payout latency (EIP-712 deadline derived) | `payouts`, `min_sec`, `max_sec`, `avg_sec` |
| `profit-split.sql` | Counters | Platform-wide payout totals and trader/protocol split | `unique_traders`, `total_payouts`, `total_trader_usdc`, `total_protocol_usdc`, `total_gross_usdc`, `trader_pct`, `protocol_pct` |
| `proof_of_payouts.sql` | Table | Recent payout activity feed (public-facing) | `source_vault`, `payout_time`, `tx_hash`, `trader_wallet`, `status`, `usdc_payout` |
| `proof_of_funds.sql` | Table | Reconstructed Vault & Treasury USDC balances | `wallet`, `symbol`, `balance` |

---

## 2. Contract Architecture

Hypernova runs on two contracts deployed on Arbitrum. Both are the authoritative on-chain source for all data in this query folder.

### 2.1 Contract Overview

**TradingAccounts** (`trading_accounts.sol`)
- UUPS upgradeable proxy; inherits `Ownable`, `EIP712`, `Initializable` (via Solady)
- Manages the full trader lifecycle: user account creation → eval account creation → eval pass/fail → funded account creation → funded account acceptance → equity updates → payout requests
- All state-changing actions are either admin-gated (`onlyAdmin`) or trader-signed via EIP-712 and submitted by a relayer
- Holds no USDC; delegates payout execution to the Vault via `IVault.processPayout`

**Vault** (`vault.sol`)
- Non-upgradeable; inherits `Ownable`
- USDC custodian: holds all platform USDC and transfers the trader share on every `processPayout` call
- Only callable by the TradingAccounts contract (`onlyTradingAccounts` modifier)
- Owner controls profit split percentage, per-transaction withdrawal limit, and pause state

### 2.2 Permission Model

| Role | Who | What they can do |
|---|---|---|
| Owner | Multisig / deployer | Upgrade TradingAccounts (UUPS); set vault and admin addresses; configure Vault (profit split, limits, pause) |
| Admin | Hot wallet / relayer | All trader lifecycle management: create user/eval accounts, update eval/funded status, update equity, suspend/unsuspend users |
| Trader (via relayer) | EIP-712 signer | `acceptFundedAccount`, `requestPayout`, `rejectFundedAccount`, `incrementNonce` |

`createUserAccount` is `onlyAdmin` — traders cannot self-register. Every wallet that appears in any eval or funded account event was first registered by the admin.

### 2.3 State Machines

**EvalStatus** (stored on `EvalAccount.evalStatus`; emitted in `EvalStatusUpdated`):

```
                    passEval() [admin]
        ┌───────────────────────────────────► PASSED
        │
  ACTIVE ──── updateEvalStatus() [admin] ───► SUSPENDED
        │                                ───► FAILED
        └──────────────────────────────────── CLOSED
```

Transitions are not enforced by the contract (except that PASSED requires `passEval`, not `updateEvalStatus`). The admin can move an account to any non-PASSED terminal status at will.

Enum integer values in Dune decoded tables: `ACTIVE=0`, `PASSED=1`, `SUSPENDED=2`, `FAILED=3`, `CLOSED=4`

---

**FundedStatus** (stored on `FundedAccount.fundedStatus`; emitted in `FundedStatusUpdated`):

```
  [created by passEval()]
          │
  AWAITING_SIGNATURE ──── acceptFundedAccount() [trader EIP-712] ──► ACTIVE
          │                                                              │
          └──── rejectFundedAccount() [trader] ──────────────────────► CLOSED
                                                                         │
                                              updateFundedStatus() [admin] ──► CLOSED
                                                                            ──► SUSPENDED
                                                                            ──► FAILED
```

Admin cannot set `NONE` or `AWAITING_SIGNATURE` via `updateFundedStatus`. An account in `AWAITING_SIGNATURE` can only exit via `acceptFundedAccount` or `rejectFundedAccount`.

Enum integer values: `NONE=0`, `AWAITING_SIGNATURE=1`, `ACTIVE=2`, `CLOSED=3`, `SUSPENDED=4`, `FAILED=5`

### 2.4 Data Encoding

| Field | Unit | Conversion |
|---|---|---|
| `assessmentFee`, `traderAmount`, `protocolAmount`, all equity values | Micro-USDC (6 decimals) | `÷ 1e6` for human-readable USDC |
| `dailyDrawdownLimit`, `maxDrawdownLimit`, `profitTarget` | Basis points | `÷ 100` for percentage |
| Vault `profitSplit`, per-trader `userBonusBps` | Basis points out of `BPS_DENOMINATOR` (10,000) | e.g., `8000 = 80%` |

The Vault `profitSplit` is global. A per-trader `userBonusBps` set by admin is additive. Effective trader share = `(profitSplit + userBonusBps) / 10000`, capped at 100%.

### 2.5 Event → Dune Table Mapping

All table names follow the pattern `hypernova_arbitrum.<contract>_<evt|call>_<name>` (fully lowercase).

| Solidity Event / Call | Dune Table | Key Columns |
|---|---|---|
| `UserAccountCreated(trader)` | `tradingaccounts_evt_useraccountcreated` | `trader` |
| `EvalAccountCreated(trader, evalAccountId, ...)` | `tradingaccounts_evt_evalaccountcreated` | `trader`, `evalAccountId`, `assessmentFee`, `dailyDrawdownLimit`, `maxDrawdownLimit`, `profitTarget`, `initialEquity` |
| `EvalStatusUpdated(trader, evalAccountId, status)` | `tradingaccounts_evt_evalstatusupdated` | `trader`, `evalAccountId`, `status` (enum int — see §2.3) |
| `EvalPassed(trader, evalAccountId, ..., fundedAccountId)` | `tradingaccounts_evt_evalpassed` | `trader`, `evalAccountId`, `fundedAccountId`, `initialEquity`, `equity`, `profitTarget` |
| `FundedAccountCreated(trader, fundedAccountId, ...)` | `tradingaccounts_evt_fundedaccountcreated` | `trader`, `fundedAccountId`, `initialEquity`, `dailyDrawdownLimit`, `maxDrawdownLimit` |
| `FundedStatusUpdated(trader, fundedAccountId, status)` | `tradingaccounts_evt_fundedstatusupdated` | `trader`, `fundedAccountId`, `status` (enum int — see §2.3) |
| `EquityUpdated(trader, fundedAccountId, equity)` | `tradingaccounts_evt_equityupdated` | `trader`, `fundedAccountId`, `equity` |
| `PayoutRequested(trader, fundedAccountId, amount, nonce)` | `tradingaccounts_evt_payoutrequested` | `trader`, `fundedAccountId`, `amount`, `nonce` |
| `FundedAccountAccepted(trader, fundedAccountId, ...)` | `tradingaccounts_evt_fundedaccountaccepted` | `trader`, `fundedAccountId`, `acceptTermsHash`, `nonce` |
| `FundedAccountRejected(trader, fundedAccountId)` | `tradingaccounts_evt_fundedaccountrejected` | `trader`, `fundedAccountId` |
| `UserSuspended(trader)` | `tradingaccounts_evt_usersuspended` | `trader` |
| `UserUnsuspended(trader)` | `tradingaccounts_evt_userunsuspended` | `trader` |
| `PayoutProcessed(trader, traderAmount, protocolAmount)` | `vault_evt_payoutprocessed` | `trader`, `traderAmount`, `protocolAmount` |
| `requestPayout(...)` call | `tradingaccounts_call_requestpayout` | `_trader`, `_deadline`, `_amount`, `_fundedAccountId`, `call_success` |

The decoded call table (`tradingaccounts_call_requestpayout`) is used — rather than the `PayoutRequested` event — wherever the EIP-712 `_deadline` parameter is needed, because event data does not include function arguments.

### 2.6 Payout Execution Flow

`requestPayout` and `processPayout` execute atomically in the same transaction — there is no asynchronous settlement step.

```
Trader signs EIP-712 Payout struct:
  { trader, fundedAccountId, amount, nonce, deadline }
          │
          ▼
Relayer calls TradingAccounts.requestPayout()
  ├── Validates: signature, deadline, canWithdraw flag, ACTIVE status, amount ≤ profit
  ├── Emits: PayoutRequested(trader, fundedAccountId, amount, nonce)
  ├── Reduces equity by amount; sets canWithdraw = false
  └── Calls Vault.processPayout(trader, amount, userBonusBps[trader])
                │
                ▼
          Vault.processPayout()
            ├── traderAmount = amount × (profitSplit + bonusBps) / 10000
            ├── Transfers traderAmount USDC → trader wallet
            └── Emits: PayoutProcessed(trader, traderAmount, amount − traderAmount)
                        (protocol share stays in vault)
```

`protocolAmount` in `vault_evt_payoutprocessed` equals `amount − traderAmount` and is the primary protocol revenue signal used in `profit-split.sql`.

---

## 3. On-Chain Data Sources

| Table | Description | Used By |
|---|---|---|
| `hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated` | Eval account creation events — `trader`, `evalAccountId`, `assessmentFee`, drawdown/profit-target params | `headline_counter`, `eval_accs`, `eval_passing_rate`, `onchain_rules`, `query_paid_vs_free_users`, `revenue*` (rank-pairing join) |
| `hypernova_arbitrum.tradingaccounts_evt_evalpassed` | Eval-passed events | `eval_passing_rate` |
| `hypernova_arbitrum.tradingaccounts_call_requestpayout` | Decoded `requestPayout` calls — includes the signed `_deadline` parameter | `payouts_latency` |
| `hypernova_arbitrum.vault_evt_payoutprocessed` | Payout settlement events — `trader`, `traderAmount`, `protocolAmount` | `profit-split`, `proof_of_payouts` |
| `erc20_arbitrum.evt_transfer` | Generic ERC-20 `Transfer` events (USDC inflows/outflows) | `headline_counter`, `query_paid_vs_free_users`, `revenue*`, `proof_of_funds` |
| `tokens.erc20` | Dune spellbook token metadata (symbol lookup) | `proof_of_funds` |

---

## 4. Core Methodology

### 4.1 Paid vs. Free Verification

The contract writes `assessmentFee` (the list price) onto **every** eval account, including ones granted for free during closed beta/alpha. There is no on-chain "paid" flag, so payment must be reconstructed by matching USDC transfers.

Two variants of this verification are used in this folder:

**Aggregate cap** (`headline_counter.sql`, `query_paid_vs_free_users.sql`):

1. Group USDC transfers to the Hypernova payment address by `(sender, amount)` → `n_payments`
2. Group eval accounts by `(trader, assessmentFee)` → `n_accounts`
3. Left-join on `(trader = sender, assessmentFee = amount)`
4. `paid = LEAST(n_payments, n_accounts)` — one payment backs at most one account, one account needs exactly one payment

This produces correct **totals** but doesn't determine *which specific* account a payment funded.

**Rank-pairing** (`revenue.sql`, `revenue_24h.sql`, `revenue_7d.sql`, `revenue_30d.sql`):

1. Number each USDC transfer per `(sender, amount)` chronologically: `ROW_NUMBER() OVER (PARTITION BY "from", value ORDER BY evt_block_time) AS k`
2. Number each eval account per `(trader, assessmentFee)` chronologically: `ROW_NUMBER() OVER (PARTITION BY trader, assessmentFee ORDER BY evt_block_time) AS k`
3. `INNER JOIN` on `(trader = sender, assessmentFee = amount, payments.k = accounts.k)`
4. Only matched rows survive — orphan payments and duplicates are excluded

Both methods produce **identical totals** (`SUM(purchased_accounts)` from `revenue.sql` = `paid_eval_accounts` from `headline_counter.sql`). The rank-pairing method additionally identifies *which* payment backs *which* account, which allows windowed revenue queries (24h/7d/30d) to correctly attribute payments to time windows.

### 4.2 Revenue Methodology

**All revenue queries in this folder use verified methodology** — orphan payments (paid but no matching account) and duplicate payments (paid twice for one account slot) are excluded. Every `revenue*.sql` query uses the rank-pairing variant (§4.1) and reconciles exactly with the headline counters.

For the windowed queries (`revenue_24h.sql`, `revenue_7d.sql`, `revenue_30d.sql`), the full payment history is scanned to build correct rank assignments, then the final output is filtered to payments landing within the trailing window. This is required for rank-pairing correctness — windowing the input would shift rank assignments.

### 4.3 Payout Latency

`requestPayout` (TradingAccounts) and `processPayout` (Vault) execute in the same transaction — payout settlement itself is atomic (see §2.6). The only measurable latency is **off-chain**: time from the trader's EIP-712 signature to the relayer landing `requestPayout` on-chain.

There is no on-chain signing timestamp, so `payouts_latency.sql` derives one from the signed `_deadline` parameter, which the frontend sets to `signing_time + 600s`:

```
latency_sec = 600 − (_deadline − call_block_time)
```

The 600-second offset is treated as constant; see `../payout_flow_analysis.md` for the full derivation and engineering confirmation.

### 4.4 Treasury Reconstruction

`proof_of_funds.sql` has no direct balance table to query, so it nets every inbound/outbound USDC transfer to the Vault and Treasury wallets since platform launch (2026-03-25) and sums to a running balance. This is a flow-based reconstruction, not a balance snapshot — it's only as complete as the chosen cutoff, which here covers the full life of the platform.

---

## 5. Metric Glossary

| Metric | Definition | Formula / Source |
|---|---|---|
| `unique_traders` | Distinct wallets that created ≥1 eval account | `COUNT(DISTINCT trader)` on `evalaccountcreated` |
| `paid_eval_accounts` / `free_eval_accounts` | Eval accounts with / without a verified matching payment | §4.1 |
| `avg_evals_per_trader` | Mean eval accounts created per unique trader | `total_eval_accounts / unique_traders` (`headline_counter.sql`) |
| `pass_rate_pct` | Share of eval accounts that progressed to `EvalPassed` | `passed_evals / eval_accounts × 100` |
| `daily_drawdown_pct` / `max_drawdown_pct` / `profit_target_pct` | Current eval risk/profit rules | Raw on-chain value (basis points) ÷ 100 |
| `paid_users` / `free_users` / `mixed_users` / `fully_paid_users` | Trader-level payment segments | §4.1, rolled up per trader — `mixed` = has both a paid and a free account, order not considered |
| `ratio_free_who_purchased_pct` | Share of users who hold ≥1 free account that also purchased ≥1 account | `mixed_users / (free_users + mixed_users) × 100`; order-agnostic free-to-paid rate |
| `revenue_usdc_24h` / `_7d` / `_30d` | Verified USDC revenue from eval purchases over the trailing window | §4.1 rank-pairing, windowed on payment time |
| `tier_revenue_usdc` / `grand_total_revenue_usdc` | Verified revenue grouped by fee tier | §4.1 rank-pairing, all-time |
| `min_sec` / `max_sec` / `avg_sec` (payout latency) | Sign-to-payout latency distribution | §4.3 |
| `total_trader_usdc` / `total_protocol_usdc` | Gross USDC split between trader payouts and protocol take | `SUM(traderAmount)`, `SUM(protocolAmount)` on `payoutprocessed` |
| `trader_pct` / `protocol_pct` | Each side's share of gross payout volume | `side_usdc / (trader_usdc + protocol_usdc) × 100` |
| `balance` (proof of funds) | Net USDC held by Vault / Treasury since the tracking cutoff | §4.4 |

---

## 6. Known Limitations

- **`mixed_users` (query_paid_vs_free_users.sql) is order-agnostic** — it flags a trader as mixed regardless of whether the free or the paid account came first. This is intentional scope, not a defect: see `../users/08_free_to_paid_upgraders.sql` for the order-aware "upgrader" variant (free first, paid later).

### Resolved

The following were identified and fixed on 2026-06-16 — kept here for change-log visibility:

- **`query_paid_vs_free_users.sql` dropped two undocumented columns, `paid_accounts_check` and `total_accounts_check`.** These were dev-time reconciliation leftovers (sums used to sanity-check the aggregate-cap math while building the query) that were never referenced in either doc and had no place in a production widget output. Removed; the query now returns exactly the 6 documented columns (`total_users`, `paid_users`, `free_users`, `mixed_users`, `fully_paid_users`, `ratio_free_who_purchased_pct`).
- **`eval_passing_rate.sql`'s output column was renamed `funded_accounts` → `passed_evals`.** The old name implied a count of `FundedAccountCreated` events; the query actually counts `EvalPassed` events. Fixed by renaming the alias to match what it counts. *If this query is already wired to a live Dune dashboard widget under the old column name, the widget binding needs to be re-pointed to `passed_evals`.*
- **`proof_of_funds.sql`'s tracking cutoff was moved from 2026-04-01 to 2026-03-25** (platform launch). The query previously missed the first week of Vault/Treasury USDC flows; it now covers the platform's full lifetime, so the reported balance is exact rather than a lower bound.
- **`onchain_rules.sql`'s table reference was lowercased** from `TradingAccounts_evt_EvalAccountCreated` to `tradingaccounts_evt_evalaccountcreated`, matching the canonical form used elsewhere in this folder. Behavior is unchanged (DuneSQL identifiers are case-insensitive) — this was a style fix only.

---

### 📊 Custom Data Analytics
**Need a custom, high-signal data narrative?** I build world-class Dune dashboards tailored specifically to your protocol's brand and metrics. 

👉 **[DM for Dashboard Requests on X (Twitter)](https://x.com/genki_sudo132)**

---