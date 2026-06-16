-- ============================================================================
-- Hypernova: Assessment Revenue — Last 24h (Verified)
-- ============================================================================
-- Verified USDC revenue in the last 24 hours: only payments that match 1:1
-- with an eval account creation via rank-pairing. Orphan and duplicate
-- payments are excluded.
--
-- Full payment history is scanned to build correct rank assignments before
-- windowing — this is required for rank-pairing correctness.
-- Reconciles with headline_counter.sql methodology.

WITH payments AS (
    SELECT
        "from" AS trader,
        value  AS amount,
        evt_block_time,
        ROW_NUMBER() OVER (PARTITION BY "from", value ORDER BY evt_block_time) AS k
    FROM erc20_arbitrum.evt_Transfer
    WHERE "to"             = 0x924e3Ed4fc2130b103470270B403b2A4ac808240   -- Hypernova payment address
      AND contract_address = 0xaf88d065e77c8cc2239327c5edb3a432268e5831  -- USDC (Arbitrum native)
      AND evt_block_date  >= DATE '2026-03-25'                           -- partition pruning
),

accounts AS (
    SELECT
        trader,
        assessmentFee AS amount,
        ROW_NUMBER() OVER (PARTITION BY trader, assessmentFee ORDER BY evt_block_time) AS k
    FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated
),

verified_payments AS (
    SELECT
        p.evt_block_time,
        p.amount / 1e6 AS amount_usdc
    FROM payments p
    INNER JOIN accounts a
      ON p.trader = a.trader
     AND p.amount = a.amount
     AND p.k      = a.k
)

SELECT
    SUM(amount_usdc) AS revenue_usdc_24h
FROM verified_payments
WHERE evt_block_time >= NOW() - INTERVAL '24' HOUR
