-- ============================================================================
-- Hypernova: Headline Counters — Traders & Eval Accounts (Paid vs Free)
-- ============================================================================
-- Single row, four numbers, one Counter visualization per column:
--   unique_traders | paid_eval_accounts | free_eval_accounts | total_eval_accounts
--
-- Paid = backed by a real USDC payment to the Hypernova payment address.
-- assessmentFee is only the list price (free beta grants have one too), so per
-- (trader, price) the number of paid accounts = least(#payments, #accounts):
-- a payment can back at most one account, an account needs one payment.
--
-- Validated 2026-06-12: 246 paid + 161 free = 407 accounts, 247 traders.

WITH payments AS (
    SELECT
        "from" AS trader,
        value  AS amount,
        COUNT(*) AS n_payments
    FROM erc20_arbitrum.evt_Transfer
    WHERE "to" = 0x924e3Ed4fc2130b103470270B403b2A4ac808240               -- Hypernova payment address
      AND contract_address = 0xaf88d065e77c8cc2239327c5edb3a432268e5831  -- USDC (Arbitrum native)
      AND evt_block_date >= DATE '2026-03-25'                            -- partition pruning
    GROUP BY 1, 2
),

accounts AS (
    SELECT
        trader,
        assessmentFee AS amount,
        COUNT(*) AS n_accounts
    FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated
    GROUP BY 1, 2
)

SELECT
    COUNT(DISTINCT a.trader)                                  AS unique_traders,
    SUM(LEAST(COALESCE(p.n_payments, 0), a.n_accounts))       AS paid_eval_accounts,
    SUM(a.n_accounts)
      - SUM(LEAST(COALESCE(p.n_payments, 0), a.n_accounts))   AS free_eval_accounts,
    SUM(a.n_accounts)                                         AS total_eval_accounts
FROM accounts a
LEFT JOIN payments p
  ON p.trader = a.trader
 AND p.amount = a.amount
