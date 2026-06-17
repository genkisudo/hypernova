# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this directory is

The 13 production DuneSQL queries powering the live Hypernova dashboard. Every `.sql` file here is a named widget query; nothing in this folder is experimental or a scratch pad. For broader project context (contract architecture, table schema, full metric glossary), see the parent `CLAUDE.md` and `README.md` in this directory.

## Running queries

Use the Dune CLI (already installed and authenticated). Always pass `-o json` for machine-readable output.

```bash
# Ad-hoc SQL
dune query run-sql --sql "SELECT ..." -o json

# Execute a saved query by ID
dune query run <query_id> -o json

# Search decoded tables
dune dataset search --query "hypernova" --categories decoded --include-schema -o json
```

## Query catalog

| File | Dashboard widget | Produces |
|---|---|---|
| `headline_counter.sql` | Counters | `unique_traders`, `paid_eval_accounts`, `free_eval_accounts`, `total_eval_accounts` |
| `eval_accs.sql` | Counter + line chart | Daily/cumulative eval accounts and traders |
| `eval_passing_rate.sql` | Counter | `eval_accounts`, `passed_evals`, `pass_rate_pct` |
| `onchain_rules.sql` | Table | Current drawdown/profit-target rules as % |
| `query_paid_vs_free_users.sql` | Counters | `total_users`, `paid_users`, `free_users`, `mixed_users`, `fully_paid_users` |
| `revenue.sql` | Table | Verified revenue by fee tier (all-time) |
| `revenue_24h.sql` / `revenue_7d.sql` / `revenue_30d.sql` | Counters | Verified revenue over trailing windows |
| `payouts_latency.sql` | Counter | `payouts`, `min_sec`, `max_sec`, `avg_sec` |
| `profit-split.sql` | Counters | Trader/protocol gross payout split |
| `proof_of_payouts.sql` | Table | 20 most recent payouts (public activity feed) |
| `proof_of_funds.sql` | Table | Reconstructed Vault & Treasury USDC balances |

## Non-obvious methodology

### Paid vs. free account verification

`assessmentFee` is written on-chain for every eval account, including free grants — so `assessmentFee > 0` overcounts paid accounts. Payment must be reconstructed by joining against `erc20_arbitrum.evt_transfer`.

Two verified methods are used — pick the right one:

- **Aggregate cap** (`headline_counter.sql`, `query_paid_vs_free_users.sql`): group transfers by `(sender, amount)` and accounts by `(trader, assessmentFee)`, left-join, `paid = LEAST(n_payments, n_accounts)`. Correct for totals; does not identify *which* account was paid for.
- **Rank-pairing** (`revenue*.sql`): assign chronological `ROW_NUMBER()` per `(sender, amount)` and per `(trader, assessmentFee)` separately, then inner-join on matching ranks. Identifies *which specific* payment backs *which specific* account, enabling time-windowed revenue. The full payment history must always be scanned before filtering to a window — windowing the input shifts rank assignments and breaks the 1:1 match.

Both methods produce identical totals. Never use raw transfer sums.

### Payout latency derivation

On-chain payout is atomic (same tx). The only measurable latency is off-chain: EIP-712 signing → relayer submission. Since there's no on-chain signing timestamp, latency is derived from the signed `_deadline`, which the frontend sets to `signing_time + 600s`:

```
latency_sec = 600 − (_deadline − call_block_time)
```

The 600-second offset is confirmed by Hypernova engineering (see `../payout_flow_analysis.md`).

### Treasury reconstruction

`proof_of_funds.sql` has no balance table — it nets every USDC inflow/outflow to the Vault and Treasury wallets since 2026-03-25 (platform launch). The cutoff must remain at launch date; shifting it forward produces a lower-bound balance, not the actual balance.

## Conventions for new queries

- **Header comment:** `====` banner, `Hypernova: <Name>` title, brief description of what's computed and any non-obvious methodology. See `payouts_latency.sql` as the canonical style.
- **Partition pruning:** filter on `evt_block_date` and/or `evt_block_time` wherever a table supports it.
- **Verified methodology:** all revenue and paid-account metrics must use aggregate cap or rank-pairing. No raw transfer sums.
- **Enum integers:** when filtering on `status` in `evalstatusupdated` / `fundedstatusupdated`, use integers (`ACTIVE=0`, `PASSED=1`, etc.) — see `README.md §2.3`.
- **Units:** divide `assessmentFee`, `traderAmount`, `protocolAmount`, and equity fields by `1e6` for USDC; divide `dailyDrawdownLimit`, `maxDrawdownLimit`, `profitTarget` by `100` for percentages.
- **One statement per file:** DuneSQL runs exactly one `SELECT` per execution. No trailing `;`.
- **Lowercase table names:** all `hypernova_arbitrum.*` identifiers are lowercase.

## Reference constants

| Constant | Value |
|---|---|
| Hypernova payment address | `0x924e3Ed4fc2130b103470270B403b2A4ac808240` |
| USDC (Arbitrum native) | `0xaf88d065e77c8cc2239327c5edb3a432268e5831` (6 decimals) |
| Vault contract/wallet | `0x920973eEBffd3bF7da14dd9fB52Bd3BeA1664c67` |
| Treasury wallet | `0x43C5F0a81d538a527DbF35D27faa583AC7FADA07` |
| Platform launch / partition-pruning cutoff | 2026-03-25 |
| EIP-712 deadline TTL | 600 seconds |
| Vault `BPS_DENOMINATOR` | 10,000 |

## Key supporting docs in this directory

- `README.md` — full query catalog, contract architecture, state machines, data encoding, payout flow, all methodology details, known limitations, and the complete metric glossary
- `metrics_definitions.md` — per-metric definitions, formulas, validation notes
- `hypernova_arbitrum_tables.md` — full decoded-table column reference
- `registered_no_eval.md` — detailed explanation of the `registered_no_eval.sql` anti-join
- `trading_accounts.sol` / `vault.sol` — contract source (authoritative for all event/call schemas)