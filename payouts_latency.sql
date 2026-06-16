 -- ============================================================================
  -- Hypernova: Payout Latency — Trader Signature → On-Chain Payout
  -- ============================================================================
  -- Payout latency: trader signature → on-chain payout (Arbitrum)
  --
  -- On-chain, requestPayout → Vault.processPayout is atomic (same tx,
  -- trade_code.sol), so all latency is off-chain: EIP-712 signing →
  -- relayer submission. Only signing-time proxy is the signed `_deadline`,
  -- set by the frontend as signing_time + 600s TTL (inferred: ttl is
  -- 592–599s on all calls; pending eng confirmation). Hence:
  --   latency_sec = 600 − (deadline − block_time)
  --
  -- Drift alarm: ttl_min/ttl_max ≈ [592, 599]. 
  
  SELECT
    count(*) AS payouts,
    min(600 - (_deadline - CAST(to_unixtime(call_block_time) AS double))) AS min_sec,
    max(600 - (_deadline - CAST(to_unixtime(call_block_time) AS double))) AS max_sec,
    avg(600 - (_deadline - CAST(to_unixtime(call_block_time) AS double))) AS avg_sec
  FROM hypernova_arbitrum.tradingaccounts_call_requestpayout
  WHERE call_success = true