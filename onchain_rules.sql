-- ============================================================================
-- Hypernova: On-Chain Eval Rules
-- ============================================================================
-- Current eval risk/profit parameters as written on-chain: daily drawdown
-- limit, max drawdown limit, and profit target, each converted from basis
-- points (1 BPS = 0.01%) to a percentage.
--
-- Returns the most recent occurrence of each distinct rule combination, so
-- if multiple rule tiers are active simultaneously, each appears once.

WITH ranked AS (
    SELECT
        CONCAT(CAST(dailyDrawdownLimit / 100 AS varchar), '%') AS daily_drawdown_pct,
        CONCAT(CAST(maxDrawdownLimit / 100 AS varchar), '%') AS max_drawdown_pct,
        CONCAT(CAST(profitTarget / 100 AS varchar), '%') AS profit_target_pct,
        ROW_NUMBER() OVER (
            PARTITION BY dailyDrawdownLimit, maxDrawdownLimit, profitTarget
            ORDER BY evt_block_time DESC
        ) AS rn
    FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated
)

SELECT
    daily_drawdown_pct,
    max_drawdown_pct,
    profit_target_pct
FROM ranked
WHERE rn <= 1
