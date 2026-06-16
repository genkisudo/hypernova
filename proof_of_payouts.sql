-- ============================================================================
-- Hypernova: Proof of Payouts — Recent Activity Feed
-- ============================================================================
-- Last 20 processed payouts, formatted for a public-facing activity table:
-- truncated addresses/hashes, a status badge, and the trader's USDC amount.
--
-- Display-only — truncated values are not unique keys and should not be
-- used for joins or deduplication.

SELECT
  -- 1. Truncate the Vault contract address and add a visual cue
  '🏦 ' || concat(substr(cast(contract_address as varchar), 1, 6), '...', substr(cast(contract_address as varchar), 39, 4)) AS source_vault,
  
  -- 2. Keep the timestamp native so Dune handles timezones and formatting perfectly
  evt_block_time AS payout_time,
  
  -- 3. Truncate the Transaction Hash (Tx hashes are 66 chars: 0x + 64)
  concat(substr(cast(evt_tx_hash as varchar), 1, 6), '...', substr(cast(evt_tx_hash as varchar), 63, 4)) AS tx_hash,
  
  -- 4. Truncate the receiving Trader's Wallet and add a user emoji
  '👤 ' || concat(substr(cast(trader as varchar), 1, 6), '...', substr(cast(trader as varchar), 39, 4)) AS trader_wallet,

  -- 5. Add a hardcoded trust-building Status column
  '✅ Settled' AS status,

  -- 6. Leave payout as a pure number so Dune can sort it correctly
  ROUND(traderAmount / 1e6, 2) AS usdc_payout

FROM hypernova_arbitrum.vault_evt_payoutprocessed 
ORDER BY evt_block_time DESC 
LIMIT 20