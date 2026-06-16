-- ============================================================================
-- Hypernova: Paid vs Free Users (Trader-Level)
-- ============================================================================
-- Account-level matching tells us WHICH accounts were purchased; this query rolls
-- it up to USERS. Logic per the plan:
--   1. Universe = every unique trader in evalaccountcreated (paid and free)
--   2. Payments = USDC transfers to the Hypernova payment address; a trader's
--      paid accounts per price tier = least(#payments, #accounts) at that price
--   3. free_users = total_users - paid_users
--   4. Mixed traders (own BOTH paid and free accounts) are counted as PAID users
--      in the headline split, and reported separately in mixed_users
--
-- Definitions:
--   paid_users  = traders with at least one purchased (payment-backed) account
--   free_users  = traders who never had a payment-backed account
--   mixed_users = paid traders who ALSO hold at least one free/granted account
--                 (subset of paid_users; fully_paid_users = paid_users - mixed_users)
--
-- Wallets that paid but never created an account (4 x $60 as of 2026-06-12) are
-- not traders and are excluded from the universe by construction.
WITH

payments AS (
    SELECT
        "from" AS trader,
        value  AS amount,            -- raw micro-USDC, exact integer match
        count(*) AS n_pay
    FROM erc20_arbitrum.evt_Transfer
    WHERE "to" = 0x924e3Ed4fc2130b103470270B403b2A4ac808240               -- Hypernova payment address
      AND contract_address = 0xaf88d065e77c8cc2239327c5edb3a432268e5831  -- USDC (Arbitrum native)
      AND evt_block_time >= TIMESTAMP '2026-03-25'                       -- platform launch
    GROUP BY 1, 2
),

accounts AS (
    SELECT
        trader,
        assessmentFee AS amount,
        count(*) AS n_acc
    FROM hypernova_arbitrum.tradingaccounts_evt_evalaccountcreated
    GROUP BY 1, 2
),

-- Per trader: total accounts vs how many are backed by a payment.
-- least() caps matched accounts at the number of payments per price tier,
-- so a single payment can never back two same-priced accounts.
per_trader AS (
    SELECT
        a.trader,
        sum(a.n_acc)                                       AS total_accounts,
        sum(least(coalesce(p.n_pay, 0), a.n_acc))          AS paid_accounts
    FROM accounts a
    LEFT JOIN payments p
      ON p.trader = a.trader AND p.amount = a.amount
    GROUP BY 1
)

SELECT
    count(*)                                                    AS total_users,
    count_if(paid_accounts > 0)                                 AS paid_users,
    count_if(paid_accounts = 0)                                 AS free_users,
    count_if(paid_accounts > 0 AND paid_accounts < total_accounts) AS mixed_users,
    count_if(paid_accounts > 0 AND paid_accounts = total_accounts) AS fully_paid_users,
    sum(paid_accounts)                                          AS paid_accounts_check,   
    sum(total_accounts)                                         AS total_accounts_check   
FROM per_trader
