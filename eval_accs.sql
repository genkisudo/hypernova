-- ============================================================================
-- Hypernova: Eval Accounts — Daily + Cumulative
-- ============================================================================
-- Daily new eval account creations with running cumulative totals, plus
-- daily and cumulative unique traders (first-eval-day attribution).
--
-- Single query feeds two visualizations: counters read row 1 (latest day,
-- ORDER BY day DESC); the line chart plots day vs new/cumulative values.
-- Each trader is counted once, on the date of their first eval, so
-- cumulative_unique_traders is a true distinct count.

WITH events AS (
    SELECT evt_block_date AS day, evalAccountId, trader
    FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated
),

daily AS (
    SELECT day, COUNT(DISTINCT evalAccountId) AS new_eval_accounts
    FROM events
    GROUP BY day
),

trader_first AS (
    SELECT trader, MIN(day) AS first_day
    FROM events
    GROUP BY trader
),

new_traders AS (
    SELECT first_day AS day, COUNT(*) AS new_traders
    FROM trader_first
    GROUP BY first_day
)

SELECT
    d.day,
    d.new_eval_accounts,
    SUM(d.new_eval_accounts) OVER (ORDER BY d.day) AS cumulative_eval_accounts,
    COALESCE(t.new_traders, 0) AS new_traders,
    SUM(COALESCE(t.new_traders, 0)) OVER (ORDER BY d.day) AS cumulative_unique_traders
FROM daily d
LEFT JOIN new_traders t ON t.day = d.day
ORDER BY d.day DESC

