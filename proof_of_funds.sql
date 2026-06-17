-- ============================================================================
-- Hypernova: Proof of Funds — Vault & Treasury Balances
-- ============================================================================
-- Reconstructs each tracked wallet's current USDC balance by netting every
-- inbound and outbound transfer since 2026-03-25 (platform launch) — an
-- on-chain, independent cross-check of reserves.
--
-- Tracked wallets: Vault (0x9209...4c67), Treasury (0x43C5...DA07).
-- Balance excludes any funds held before the 2026-03-25 cutoff.

WITH wallet_list AS (
    SELECT address
    FROM (
        VALUES
            (0x920973eEBffd3bF7da14dd9fB52Bd3BeA1664c67), -- Vault address
            (0x43C5F0a81d538a527DbF35D27faa583AC7FADA07)  -- Treasury address
    ) AS a (address)
),

-- outflows: tokens leaving the tracked wallets
token_outflows AS (
    SELECT
        t."from" AS address,
        tk.symbol,
        -(t.value / 1e6) AS amount
    FROM erc20_arbitrum.evt_transfer AS t
    INNER JOIN tokens.erc20 AS tk
        ON t.contract_address = tk.contract_address
       AND tk.blockchain = 'arbitrum'
    WHERE t.contract_address = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
      AND t.evt_block_date >= DATE '2026-03-25'
      AND t."from" IN (SELECT address FROM wallet_list)
),

-- inflows: tokens entering the tracked wallets
token_inflows AS (
    SELECT
        t."to" AS address,
        tk.symbol,
        (t.value / 1e6) AS amount
    FROM erc20_arbitrum.evt_transfer AS t
    INNER JOIN tokens.erc20 AS tk
        ON t.contract_address = tk.contract_address
       AND tk.blockchain = 'arbitrum'
    WHERE t.contract_address = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
      AND t.evt_block_date >= DATE '2026-03-25'
      AND t."to" IN (SELECT address FROM wallet_list)
),

combined_flows AS (
    SELECT address, symbol, amount
    FROM token_outflows
    UNION ALL
    SELECT address, symbol, amount
    FROM token_inflows
),

final AS (
    SELECT
        address,
        symbol,
        SUM(amount) AS balance
    FROM combined_flows
    GROUP BY 1, 2
)

SELECT
    CASE
        WHEN address = 0x43C5F0a81d538a527DbF35D27faa583AC7FADA07 THEN
            '🏛️ Treasury (' || CONCAT(SUBSTR(CAST(address AS varchar), 1, 6), '...', SUBSTR(CAST(address AS varchar), 39, 4)) || ')'
        WHEN address = 0x920973eEBffd3bF7da14dd9fB52Bd3BeA1664c67 THEN
            '🏦 Vault (' || CONCAT(SUBSTR(CAST(address AS varchar), 1, 6), '...', SUBSTR(CAST(address AS varchar), 39, 4)) || ')'
        ELSE
            CONCAT(SUBSTR(CAST(address AS varchar), 1, 6), '...', SUBSTR(CAST(address AS varchar), 39, 4))
    END AS wallet,
    symbol,
    balance
FROM final
ORDER BY balance DESC
