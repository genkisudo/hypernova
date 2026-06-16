-- ============================================================================
-- Hypernova: Eval Pass Rate
-- ============================================================================
-- Share of eval accounts that went on to pass (EvalPassed event), as a
-- percentage: pass_rate_pct = passed_evals / eval_accounts.
--
-- Counts events, not accounts — a trader who took multiple evals is counted
-- once per eval attempt, not once per trader.

WITH counts AS (
    SELECT
        (SELECT COUNT(*) FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated) AS eval_accounts,
        (SELECT COUNT(*) FROM hypernova_arbitrum.tradingaccounts_evt_evalpassed) AS passed_evals
)
SELECT
    eval_accounts,
    passed_evals,
    (CAST(passed_evals AS double) / eval_accounts * 100) AS pass_rate_pct
FROM counts
