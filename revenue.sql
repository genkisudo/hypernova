-- ============================================================================
-- Hypernova: Assessment Revenue by Price Tier (Verified)
-- ============================================================================
-- All-time USDC revenue from eval account purchases, grouped by fee tier.
-- Uses rank-pairing to match each payment 1:1 with an account creation —
-- orphan payments (no matching account) and duplicates are excluded.
--
-- Reconciles exactly with headline_counter.sql's paid_eval_accounts count:
-- SUM(purchased_accounts) here = paid_eval_accounts there.

WITH payments AS (
    SELECT
        "from" AS trader,
        value  AS amount,
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
    SELECT p.amount / 1e6 AS amount_usdc
    FROM payments p
    INNER JOIN accounts a
      ON p.trader = a.trader
     AND p.amount = a.amount
     AND p.k      = a.k
)

SELECT
    amount_usdc,
    COUNT(*)                       AS purchased_accounts,
    SUM(amount_usdc)               AS tier_revenue_usdc,
    SUM(SUM(amount_usdc)) OVER ()  AS grand_total_revenue_usdc
FROM verified_payments
GROUP BY amount_usdc
ORDER BY amount_usdc ASC
