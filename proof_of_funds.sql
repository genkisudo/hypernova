-- ============================================================================
-- Hypernova: Proof of Funds — Vault & Treasury Balances
-- ============================================================================
-- Reconstructs each tracked wallet's current USDC balance by netting every
-- inbound and outbound transfer since 2026-03-25 (platform launch) — an
-- on-chain, independent cross-check of reserves.
--
-- Tracked wallets: Vault (0x9209...4c67), Treasury (0x43C5...DA07).
-- Balance excludes any funds held before the 2026-03-25 cutoff.

with wallet_list as (
    select address
    from (
        values
            (0x920973eEBffd3bF7da14dd9fB52Bd3BeA1664c67) -- Vault address
          , (0x43C5F0a81d538a527DbF35D27faa583AC7FADA07)  -- Treasury address
    ) as a (address)
)

-- outflows: tokens leaving the tracked wallets
, token_outflows as (
    select
        t."from"       as address
      , tk.symbol
      , -(t.value / 1e6) as amount
    from erc20_arbitrum.evt_transfer as t
    inner join tokens.erc20 as tk
        on t.contract_address = tk.contract_address
       and tk.blockchain = 'arbitrum'
    where t.contract_address = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
      and t.evt_block_date >= date '2026-03-25'
      and t."from" in (select address from wallet_list)
)

-- inflows: tokens entering the tracked wallets
, token_inflows as (
    select
        t."to"         as address
      , tk.symbol
      , (t.value / 1e6) as amount
    from erc20_arbitrum.evt_transfer as t
    inner join tokens.erc20 as tk
        on t.contract_address = tk.contract_address
       and tk.blockchain = 'arbitrum'
    where t.contract_address = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831
      and t.evt_block_date >= date '2026-03-25'
      and t."to" in (select address from wallet_list)
)

, combined_flows as (
    select address, symbol, amount
    from token_outflows
    union all
    select address, symbol, amount
    from token_inflows
)

, final as (
    select
        address
      , symbol
      , sum(amount) as balance
    from combined_flows
    group by 1, 2
)

select 
    CASE 
        WHEN address = 0x43C5F0a81d538a527DbF35D27faa583AC7FADA07 THEN 
            '🏛️ Treasury (' || concat(substr(cast(address as varchar), 1, 6), '...', substr(cast(address as varchar), 39, 4)) || ')'
        WHEN address = 0x920973eEBffd3bF7da14dd9fB52Bd3BeA1664c67 THEN 
            '🏦 Vault (' || concat(substr(cast(address as varchar), 1, 6), '...', substr(cast(address as varchar), 39, 4)) || ')'
        ELSE 
            concat(substr(cast(address as varchar), 1, 6), '...', substr(cast(address as varchar), 39, 4))
    END as wallet,
    symbol,
    balance
from final
order by balance desc