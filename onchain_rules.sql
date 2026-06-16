-- ============================================================================
-- Hypernova: On-Chain Eval Rules
-- ============================================================================
-- Current eval risk/profit parameters as written on-chain: daily drawdown
-- limit, max drawdown limit, and profit target, each converted from basis
-- points (1 BPS = 0.01%) to a percentage.
--
-- Returns the most recent occurrence of each distinct rule combination, so
-- if multiple rule tiers are active simultaneously, each appears once.

with ranked as (
    select
        concat(cast(dailyDrawdownLimit / 100 as varchar), '%') as daily_drawdown_pct
        , concat(cast(maxDrawdownLimit / 100 as varchar), '%') as max_drawdown_pct
        , concat(cast(profitTarget / 100 as varchar), '%') as profit_target_pct
        , row_number() over (
            partition by dailyDrawdownLimit, maxDrawdownLimit, profitTarget
            order by evt_block_time desc
        ) as rn
    from hypernova_arbitrum.TradingAccounts_evt_EvalAccountCreated
)

select
    daily_drawdown_pct
    , max_drawdown_pct
    , profit_target_pct
from ranked
where rn <= 1

