-- ============================================================================
-- Hypernova: Payout Profit Split
-- ============================================================================
-- Platform-wide payout totals and the trader/protocol profit split, sourced
-- from Vault.PayoutProcessed (traderAmount + protocolAmount = gross payout).
--
-- trader_pct / protocol_pct show each side's share of gross USDC paid out
-- across all payouts to date.

WITH totals AS (
      SELECT
          COUNT(DISTINCT trader) AS unique_traders,
          COUNT(*) AS total_payouts,
          SUM(traderAmount) AS raw_trader,
          SUM(protocolAmount) AS raw_protocol
      FROM hypernova_arbitrum.vault_evt_payoutprocessed
  )
  
  SELECT
      unique_traders,
      total_payouts,
      CAST(raw_trader AS double) / 1e6 AS total_trader_usdc,
      CAST(raw_protocol AS double) / 1e6 AS total_protocol_usdc,
      CAST(raw_trader + raw_protocol AS double) / 1e6 AS total_gross_usdc,
      ROUND(CAST(raw_trader AS double) / CAST(raw_trader + raw_protocol AS double) * 100, 2) AS trader_pct,
      ROUND(CAST(raw_protocol AS double) / CAST(raw_trader + raw_protocol AS double) * 100, 2) AS protocol_pct
  FROM totals