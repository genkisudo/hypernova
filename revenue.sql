-- ============================================================================
-- Hypernova: Assessment Revenue by Price Tier
-- ============================================================================
-- All-time USDC revenue from eval account purchases, grouped by fee tier:
-- per-tier purchase count, tier revenue, and the grand total across tiers.
--
-- Counts raw transfers from known eval traders to the Hypernova payment
-- address, not verified 1:1 payment-to-account matches — orphan/duplicate
-- payments are not excluded (see headline_counter.sql for the verified
-- paid/free split methodology).

WITH eval_traders AS (
    SELECT DISTINCT trader 
    FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated
),

trader_transfers AS (
    -- 2. Filter transaction data to only those made by eval traders
    SELECT 
        (tr.value / 1e6) AS amount_usdc
    FROM erc20_arbitrum.evt_Transfer AS tr
    INNER JOIN eval_traders vt 
        ON tr."from" = vt.trader
    WHERE tr."to" = 0x924e3Ed4fc2130b103470270B403b2A4ac808240  --Hypernova address
        AND tr.contract_address = 0xaf88d065e77c8cc2239327c5edb3a432268e5831  -- USDC
        AND tr.evt_block_time >= TIMESTAMP '2026-03-25'
)
-- 3. Calculate grouped counts, tier sums, and the grand total
SELECT 
    amount_usdc,
    COUNT(*) AS purchased_accounts,
    SUM(amount_usdc) AS tier_revenue_usdc,
    SUM(SUM(amount_usdc)) OVER () AS grand_total_revenue_usdc
FROM trader_transfers
GROUP BY amount_usdc
ORDER BY amount_usdc ASC