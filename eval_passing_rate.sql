-- ============================================================================
-- Hypernova: Eval Pass Rate
-- ============================================================================
-- Share of eval accounts that went on to pass (EvalPassed event), as a
-- percentage: pass_rate_pct = evalpassed events / evalaccountcreated events.
--
-- Counts events, not accounts — a trader who took multiple evals is counted
-- once per eval attempt, not once per trader.

WITH counts AS (
    SELECT
        (SELECT COUNT(*) FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated) AS eval_accounts,
        (SELECT COUNT(*) FROM hypernova_arbitrum.tradingaccounts_evt_evalpassed) AS funded_accounts
)
SELECT
    eval_accounts,
    funded_accounts,
    (CAST(funded_accounts AS double) / eval_accounts * 100) AS pass_rate_pct
FROM counts
