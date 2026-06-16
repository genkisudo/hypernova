-- ============================================================================
-- Hypernova: Assessment Revenue — Last 7 Days
-- ============================================================================
-- USDC received in the last 7 days from eval account purchases: transfers
-- from known eval traders to the Hypernova payment address.
--
-- Counts raw transfers, not verified 1:1 payment-to-account matches —
-- orphan/duplicate payments are not excluded (see headline_counter.sql for
-- the verified paid/free split methodology).
WITH eval_traders AS (
    SELECT DISTINCT trader
    FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated
),

recent_transfers AS (
    SELECT
        tr.value / 1e6 AS amount_usdc
    FROM erc20_arbitrum.evt_transfer AS tr
    INNER JOIN eval_traders AS vt
        ON tr."from" = vt.trader
    WHERE tr."to" = 0x924e3Ed4fc2130b103470270B403b2A4ac808240   -- Hypernova address
        AND tr.contract_address = 0xaf88d065e77c8cc2239327c5edb3a432268e5831  -- USDC
        AND tr.evt_block_time >= NOW() - INTERVAL '7' DAY
)

SELECT
    SUM(amount_usdc) AS revenue_usdc_last_week
FROM recent_transfers