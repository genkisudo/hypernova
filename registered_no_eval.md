# Hypernova: Registered Wallets That Never Started an Eval

**File:** `registered_no_eval.sql` · **Chain:** Arbitrum · **Schema:** `hypernova_arbitrum`

## Question

Which traders **registered on-chain** (`UserAccountCreated`) but **never had an
eval/challenge account created** (`EvalAccountCreated`)? I.e. wallets that exist
in the protocol but never took a challenge.

## Why this anti-join is correct (from `trading_accounts.sol`)

- `createUserAccount(address)` is `onlyAdmin` and emits `UserAccountCreated`. It
  is the gate for everything else.
- `createEvalAccount()`, `passEval()`, `acceptFundedAccount()`,
  `rejectFundedAccount()`, and `requestPayout()` all carry the
  `whenUserExists(_trader)` modifier, which reverts unless
  `userExists[_trader] == true`.
- **Consequence:** every trader in `EvalAccountCreated` must already appear in
  `UserAccountCreated`. Eval-traders are a strict **subset** of user-traders, so
  `users − evals` is well-defined and exactly captures "registered but never
  took a challenge."
- `createUserAccount` reverts with `UserAccountAlreadyExists` on duplicates, so
  there is **exactly one** `UserAccountCreated` per trader — no dedup needed,
  and we can keep the registration tx/block for traceability.

## Can a user account exist with no eval? (yes)

The contract does **not** bundle the two. `createUserAccount` only sets
`userExists[_trader] = true` and emits `UserAccountCreated` — it never creates an
eval account, and nothing forces a later `createEvalAccount`. The only ordering
constraint is one-directional (`whenUserExists` on `createEvalAccount`), so
**registered-but-no-eval is a fully valid on-chain state** and this query *can*
legitimately return rows.

## Interpreting an empty result

Zero rows is **not guaranteed by the contract** — it would be an *operational*
observation that the admin happens to always create an eval right after the user
account. It is not a code-enforced invariant. Off-chain-only signups that never
hit `createUserAccount` are invisible on-chain and are **not** counted here.

## Main query

```sql
SELECT
    u.trader,
    u.evt_block_time   AS registered_at,
    u.evt_block_number AS registered_block,
    u.evt_tx_hash      AS registration_tx
FROM hypernova_arbitrum.tradingaccounts_evt_useraccountcreated u
WHERE NOT EXISTS (
    SELECT 1
    FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated e
    WHERE e.trader = u.trader
)
ORDER BY u.evt_block_time DESC
```

Notes:
- `NOT EXISTS` is used deliberately — it is NULL-safe (unlike `NOT IN`).
- `trader` is `varbinary` on both sides and from the same contract, so it
  compares directly.
- **No trailing `;`** and only one statement: DuneSQL runs exactly one statement
  per execution. Two live `SELECT`s produce
  `mismatched input ';' ... Expecting <EOF>`.

## Diagnostic query (run separately)

Run this on its own to confirm *why* the main query returns its row count and to
prove the subset relationship.

| Column | Meaning |
|---|---|
| `registered_wallets` | Distinct wallets that hit `createUserAccount`. **If 0**, the table is empty/undecoded — a data-coverage problem, not a funnel finding. |
| `wallets_with_eval` | Distinct wallets with ≥ 1 `EvalAccountCreated`. |
| `registered_no_eval` | Wallets registered but with no eval (the main query's row count). Expected `0` given admin onboarding. |
| `eval_without_user` | **Must be 0.** The `whenUserExists` gate makes eval a strict subset of users; nonzero signals a decoding gap or broken assumption. |

```sql
SELECT
    COUNT(DISTINCT u.trader)                              AS registered_wallets,
    COUNT(DISTINCT e.trader)                              AS wallets_with_eval,
    COUNT(DISTINCT u.trader) FILTER (
        WHERE e.trader IS NULL
    )                                                     AS registered_no_eval,
    -- Sanity check: eval-traders that have no user account (should be 0).
    (
        SELECT COUNT(DISTINCT ev.trader)
        FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated ev
        WHERE NOT EXISTS (
            SELECT 1
            FROM hypernova_arbitrum.tradingaccounts_evt_useraccountcreated us
            WHERE us.trader = ev.trader
        )
    )                                                     AS eval_without_user
FROM hypernova_arbitrum.tradingaccounts_evt_useraccountcreated u
LEFT JOIN hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated e
    ON e.trader = u.trader
```
