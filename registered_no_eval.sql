-- ============================================================================
-- Hypernova: Registered Wallets That Never Started an Eval
-- ============================================================================
-- Goal: traders who registered on-chain (UserAccountCreated) but never had an
-- eval/challenge account created (EvalAccountCreated). Anti-join on `trader`.
--
-- ---------------------------------------------------------------------------
-- Why this is the correct definition (from trading_accounts.sol)
-- ---------------------------------------------------------------------------
-- createUserAccount(address) is onlyAdmin and emits UserAccountCreated. It is
-- the gate for everything else: createEvalAccount(), passEval(), accept/reject,
-- requestPayout() all carry the `whenUserExists(_trader)` modifier, which
-- reverts unless userExists[_trader] == true.
--
-- Consequence: every trader that appears in EvalAccountCreated MUST already
-- appear in UserAccountCreated. Eval-traders are a strict SUBSET of
-- user-traders, so (users - evals) is well-defined and exactly captures
-- "registered but never took a challenge."
--
-- ---------------------------------------------------------------------------
-- Interpreting an empty result
-- ---------------------------------------------------------------------------
-- The contract does NOT bundle these: createUserAccount only sets userExists and
-- emits UserAccountCreated — it never creates an eval account, and nothing forces
-- a later createEvalAccount. So "registered but no eval" is a fully valid on-chain
-- state and this query CAN legitimately return rows.
--
-- If it returns zero rows, that is an OPERATIONAL observation (the admin happens
-- to always create an eval right after the user account), not a guarantee the
-- code enforces. Off-chain-only signups that never hit createUserAccount are
-- invisible on-chain and are NOT counted here.
--
-- NOTE: A NOT EXISTS anti-join is used deliberately (it is NULL-safe, unlike
-- NOT IN). The `trader` columns are varbinary on both sides and come from the
-- same contract, so they compare directly.
--
-- No GROUP BY / dedup is needed on the user side: createUserAccount reverts with
-- UserAccountAlreadyExists if userExists[_trader] is already true, so there is
-- exactly one UserAccountCreated event per trader. We can therefore select the
-- registration row directly and keep its tx hash / block for traceability.

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


-- ============================================================================
-- DIAGNOSTIC QUERY (kept commented — see note below)
-- ============================================================================
-- IMPORTANT: DuneSQL runs exactly ONE statement per execution. Two live SELECTs
-- in one query produce: "mismatched input ';' ... Expecting <EOF>". So the
-- diagnostic below is commented out. To use it: comment out the main query
-- above, uncomment this block, and run it on its own.
--
-- Purpose: explain WHY the main query returns the row count it does, and prove
-- the subset relationship from the contract.
--
-- How to read the single output row:
--   registered_wallets   total distinct wallets that hit createUserAccount.
--                        If this is 0, the useraccountcreated table is empty /
--                        undecoded -> a data-coverage problem, NOT a funnel
--                        finding, and the main query's emptiness is meaningless.
--   wallets_with_eval    distinct wallets with >= 1 EvalAccountCreated.
--   registered_no_eval   wallets registered but with no eval (the main query's
--                        row count). Expected to be 0 given admin onboarding.
--   eval_without_user    MUST be 0. Contract's whenUserExists gate makes eval a
--                        strict subset of users; any nonzero value signals a
--                        decoding gap or an assumption break worth investigating.
--
-- SELECT
--     COUNT(DISTINCT u.trader)                                          AS registered_wallets,
--     COUNT(DISTINCT e.trader)                                          AS wallets_with_eval,
--     COUNT(DISTINCT u.trader) FILTER (
--         WHERE e.trader IS NULL
--     )                                                                 AS registered_no_eval,
--     -- Sanity check: eval-traders that have no user account (should be 0).
--     (
--         SELECT COUNT(DISTINCT ev.trader)
--         FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated ev
--         WHERE NOT EXISTS (
--             SELECT 1
--             FROM hypernova_arbitrum.tradingaccounts_evt_useraccountcreated us
--             WHERE us.trader = ev.trader
--         )
--     )                                                                 AS eval_without_user
-- FROM hypernova_arbitrum.tradingaccounts_evt_useraccountcreated u
-- LEFT JOIN hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated e
--     ON e.trader = u.trader
