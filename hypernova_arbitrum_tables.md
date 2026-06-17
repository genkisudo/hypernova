# Hypernova on Arbitrum -- Dune Decoded Tables

**Chain:** Arbitrum  
**Dune Schema:** `hypernova_arbitrum`  
**Total decoded tables:** 176  
**Contracts:** 2

---

## Contract 1: Vault

USDC-denominated vault that handles payouts to traders and protocol fee splits.

### Key Events

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `vault_evt_payoutprocessed` | `trader`, `traderAmount`, `protocolAmount` | Payout distributed to a trader (highest activity table, page_rank 1.05) |
| `vault_evt_profitsplitupdated` | `profitSplit` | Protocol/trader profit split ratio changed |
| `vault_evt_maxwithdrawallimitupdated` | `newLimit` | Max withdrawal limit updated |
| `vault_evt_pausedstatechanged` | `isPaused` | Contract paused/unpaused |
| `vault_evt_ownershiptransferred` | `oldOwner`, `newOwner` | Ownership transfer |
| `vault_evt_ownershiphandoverrequested` | `pendingOwner` | Two-step ownership handover initiated |
| `vault_evt_ownershiphandovercanceled` | `pendingOwner` | Ownership handover canceled |

### Key Calls

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `vault_call_processpayout` | `_trader`, `_amount`, `_bonusBps` | Process a payout to a trader with optional bonus |
| `vault_call_ownerwithdraw` | `_amount` | Owner withdraws funds from vault |
| `vault_call_setprofitsplit` | `_profitSplit` | Set the profit split ratio |
| `vault_call_setmaxwithdrawallimit` | `_newLimit` | Set max withdrawal limit |
| `vault_call_pause` | -- | Pause the vault |
| `vault_call_unpause` | -- | Unpause the vault |
| `vault_call_usdc` | `output_0` | Read the USDC token address |
| `vault_call_trading_accounts` | `output_0` | Read the linked TradingAccounts contract address |
| `vault_call_profitsplit` | `output_0` | Read current profit split |
| `vault_call_maxwithdrawallimit` | `output_0` | Read current max withdrawal limit |
| `vault_call_bps_denominator` | `output_0` | Read BPS denominator (basis points scaling) |
| `vault_call_min_profit_split` | `output_0` | Read minimum profit split |
| `vault_call_paused` | `output_0` | Read paused state |
| `vault_call_owner` | `output_result` | Read owner address |
| `vault_call_transferownership` | `newOwner` | Transfer ownership |
| `vault_call_renounceownership` | -- | Renounce ownership |
| `vault_call_requestownershiphandover` | -- | Request ownership handover |
| `vault_call_cancelownershiphandover` | -- | Cancel ownership handover |
| `vault_call_completeownershiphandover` | `pendingOwner` | Complete ownership handover |
| `vault_call_ownershiphandoverexpiresat` | `pendingOwner`, `output_result` | Check handover expiry |

---

## Contract 2: TradingAccounts

Core trading logic -- manages eval accounts, funded accounts, equity tracking, drawdowns, payouts, and user lifecycle. This is an upgradeable proxy (UUPS pattern).

### Key Events -- Account Lifecycle

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `tradingaccounts_evt_useraccountcreated` | `trader` | New user registered on-chain |
| `tradingaccounts_evt_evalaccountcreated` | `trader`, `evalAccountId`, `initialEquity`, `profitTarget`, `dailyDrawdownLimit`, `maxDrawdownLimit`, `assessmentFee`, `startOfDayBalance` | Eval (challenge) account created (highest activity, page_rank 1.90) |
| `tradingaccounts_evt_evalpassed` | `trader`, `evalAccountId`, `fundedAccountId`, `equity`, `initialEquity`, `profitTarget` | Trader passed eval, funded account created |
| `tradingaccounts_evt_fundedaccountcreated` | `trader`, `fundedAccountId`, `initialEquity`, `dailyDrawdownLimit`, `maxDrawdownLimit`, `startOfDayBalance` | Funded account created directly |
| `tradingaccounts_evt_fundedaccountaccepted` | `trader`, `fundedAccountId`, `acceptTermsHash`, `nonce` | Trader accepted funded account terms (signature-verified) |
| `tradingaccounts_evt_fundedaccountrejected` | `trader`, `fundedAccountId` | Funded account rejected |

### Key Events -- Trading & Equity

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `tradingaccounts_evt_equityupdated` | `trader`, `fundedAccountId`, `equity` | Funded account equity updated |
| `tradingaccounts_evt_equitytoppedup` | `trader`, `fundedAccountId`, `amount` | Equity topped up |
| `tradingaccounts_evt_startofdaybalanceupdated` | `trader`, `fundedAccountId`, `startOfDayBalance` | Funded start-of-day balance reset |
| `tradingaccounts_evt_evalstartofdaybalanceupdated` | `trader`, `evalAccountId`, `startOfDayBalance` | Eval start-of-day balance reset |

### Key Events -- Status & Payouts

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `tradingaccounts_evt_evalstatusupdated` | `trader`, `evalAccountId`, `status` | Eval account status changed (integer enum) |
| `tradingaccounts_evt_fundedstatusupdated` | `trader`, `fundedAccountId`, `status` | Funded account status changed (integer enum) |
| `tradingaccounts_evt_payoutrequested` | `trader`, `fundedAccountId`, `amount`, `nonce` | Trader requested a payout |
| `tradingaccounts_evt_userbonussplitupdated` | `trader`, `bonusBps` | User-specific bonus split updated |

### Key Events -- Admin & System

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `tradingaccounts_evt_usersuspended` | `trader` | User suspended |
| `tradingaccounts_evt_userunsuspended` | `trader` | User unsuspended |
| `tradingaccounts_evt_adminupdated` | `admin` | Admin address changed |
| `tradingaccounts_evt_vaultupdated` | `vault` | Linked Vault contract updated |
| `tradingaccounts_evt_accepttermshashupdated` | `oldHash`, `newHash` | Terms hash changed |
| `tradingaccounts_evt_nonceincremented` | `trader`, `newNonce` | Trader nonce incremented |
| `tradingaccounts_evt_ownershiptransferred` | `oldOwner`, `newOwner` | Ownership transfer |
| `tradingaccounts_evt_ownershiphandoverrequested` | `pendingOwner` | Handover requested |
| `tradingaccounts_evt_ownershiphandovercanceled` | `pendingOwner` | Handover canceled |
| `tradingaccounts_evt_upgraded` | `implementation` | Proxy upgraded to new implementation |
| `tradingaccounts_evt_initialized` | `version` | Contract initialized |

### Key Calls -- Account Management

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `tradingaccounts_call_createuseraccount` | `_trader` | Register a new user |
| `tradingaccounts_call_createevalaccount` | `_trader`, `_evalAccountId`, `_params` | Create eval account (params as varchar) |
| `tradingaccounts_call_passeval` | `_trader`, `_evalAccountId`, `_fundedAccountId` | Pass eval, promote to funded |
| `tradingaccounts_call_acceptfundedaccount` | `_trader`, `_fundedAccountId`, `_acceptTermsHash`, `_signature`, `_deadline` | Accept funded account terms (EIP-712 signed) |
| `tradingaccounts_call_rejectfundedaccount` | `_fundedAccountId` | Reject a funded account |

### Key Calls -- Equity & Settlement

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `tradingaccounts_call_updatefundedequity` | `_trader`, `_fundedAccountId`, `_amount` | Update funded account equity |
| `tradingaccounts_call_updateevalequity` | `_trader`, `_evalAccountId`, `_amount` | Update eval account equity |
| `tradingaccounts_call_batchupdateequity` | `_traders[]`, `_fundedAccountIds[]`, `_amounts[]`, `_isEval[]` | Batch equity update (arrays) |
| `tradingaccounts_call_updateequityandsettle` | `_trader`, `_fundedAccountId`, `_amount` | Update equity and settle |
| `tradingaccounts_call_topupequity` | `_trader`, `_fundedAccountId`, `_amount` | Top up funded equity |
| `tradingaccounts_call_updatestartofdaybalance` | `_trader`, `_fundedAccountId`, `_startOfDayBalance` | Reset funded start-of-day balance |
| `tradingaccounts_call_updateevalstartofdaybalance` | `_trader`, `_evalAccountId`, `_startOfDayBalance` | Reset eval start-of-day balance |
| `tradingaccounts_call_updateevalstatus` | `_trader`, `_evalAccountId`, `_status` | Update eval status |
| `tradingaccounts_call_updatefundedstatus` | `_trader`, `_fundedAccountId`, `_status` | Update funded status |

### Key Calls -- Payouts

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `tradingaccounts_call_requestpayout` | `_trader`, `_fundedAccountId`, `_amount`, `_signature`, `_deadline` | Request payout (EIP-712 signed) |
| `tradingaccounts_call_getprofitorloss` | `_trader`, `_fundedAccountId` -> `output_isProfit`, `output_amount` | Read P&L for a funded account |
| `tradingaccounts_call_getmaxwithdrawable` | `_trader`, `_fundedAccountId` -> `output_0` | Read max withdrawable amount |

### Key Calls -- Read State

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `tradingaccounts_call_evalaccounts` | `_0` (trader), `_1` (id) -> `output_equity`, `output_evalStatus`, `output_initialEquity`, `output_profitTarget`, `output_dailyDrawdownLimit`, `output_maxDrawdownLimit`, `output_startOfDayBalance` | Read full eval account state |
| `tradingaccounts_call_fundedaccounts` | `_0` (trader), `_1` (id) -> `output_equity`, `output_fundedStatus`, `output_initialEquity`, `output_dailyDrawdownLimit`, `output_maxDrawdownLimit`, `output_startOfDayBalance`, `output_canWithdraw` | Read full funded account state |
| `tradingaccounts_call_userexists` | `_0` (trader) -> `output_0` (bool) | Check if user exists |
| `tradingaccounts_call_usersuspended` | `_0` (trader) -> `output_0` (bool) | Check if user is suspended |
| `tradingaccounts_call_userbonusbps` | `_0` (trader) -> `output_0` (uint256) | Read user bonus split in BPS |
| `tradingaccounts_call_nonces` | `_0` (trader) -> `output_0` (uint256) | Read trader nonce |
| `tradingaccounts_call_idowner` | `_0` (id) -> `output_0` (address) | Map account ID to owner address |

### Key Calls -- Admin

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `tradingaccounts_call_setadmin` | `_admin` | Set admin address |
| `tradingaccounts_call_setvault` | `_vault` | Set linked Vault address |
| `tradingaccounts_call_setuserbonussplit` | `_trader`, `_bonusBps` | Set user bonus split |
| `tradingaccounts_call_setaccepttermshash` | `_hash` | Set terms acceptance hash |
| `tradingaccounts_call_suspenduser` | `_trader` | Suspend a user |
| `tradingaccounts_call_unsuspenduser` | `_trader` | Unsuspend a user |
| `tradingaccounts_call_incrementnonce` | -- | Increment nonce |
| `tradingaccounts_call_admin` | `output_0` | Read admin address |
| `tradingaccounts_call_vault` | `output_0` | Read vault address |
| `tradingaccounts_call_deployer` | `output_0` | Read deployer address |
| `tradingaccounts_call_accepttermshash` | `output_0` | Read current terms hash |
| `tradingaccounts_call_owner` | `output_result` | Read owner address |

### Key Calls -- Proxy & Ownership

| Table | Key Columns | Description |
|-------|-------------|-------------|
| `tradingaccounts_call_initialize` | `_owner`, `_admin` | Initialize proxy |
| `tradingaccounts_call_upgradetoandcall` | `newImplementation`, `data` | Upgrade proxy implementation |
| `tradingaccounts_call_proxiableuuid` | `output_0` | Read proxy UUID |
| `tradingaccounts_call_eip712domain` | -> `output_name`, `output_version`, `output_chainId`, `output_verifyingContract`, ... | Read EIP-712 domain |
| `tradingaccounts_call_payout_typehash` | `output_0` | Read payout EIP-712 typehash |
| `tradingaccounts_call_accept_funded_account_typehash` | `output_0` | Read accept-funded-account EIP-712 typehash |
| `tradingaccounts_call_transferownership` | `newOwner` | Transfer ownership |
| `tradingaccounts_call_renounceownership` | -- | Renounce ownership |
| `tradingaccounts_call_requestownershiphandover` | -- | Request handover |
| `tradingaccounts_call_cancelownershiphandover` | -- | Cancel handover |
| `tradingaccounts_call_completeownershiphandover` | `pendingOwner` | Complete handover |
| `tradingaccounts_call_ownershiphandoverexpiresat` | `pendingOwner` -> `output_result` | Check handover expiry |

---

## Architecture Summary

```
Trader (wallet)
    |
    |  createUserAccount / createEvalAccount / acceptFundedAccount (EIP-712)
    v
+----------------------------+         +------------------+
|      TradingAccounts       |-------->|      Vault       |
|  (upgradeable UUPS proxy)  |         |  (USDC custody)  |
+----------------------------+         +------------------+
|                            |         |                  |
| Eval Accounts:             |         | processPayout()  |
|   - equity tracking        |         | ownerWithdraw()  |
|   - profit target          |         | profitSplit      |
|   - daily/max drawdown     |         | maxWithdrawalLmt |
|   - start-of-day balance   |         | USDC token ref   |
|                            |         |                  |
| Funded Accounts:           |         +------------------+
|   - equity tracking        |
|   - daily/max drawdown     |
|   - start-of-day balance   |
|   - canWithdraw flag       |
|   - payout requests        |
|                            |
| User Management:           |
|   - suspend/unsuspend      |
|   - bonus BPS per user     |
|   - nonce (replay protect) |
|   - EIP-712 signatures     |
+----------------------------+
```

**Flow:**
1. User creates account -> takes eval (challenge)
2. Eval tracks equity vs profit target and drawdown limits
3. If eval passed -> funded account created
4. Trader accepts funded account terms via EIP-712 signature
5. Admin updates equity, start-of-day balances via batch or individual calls
6. Trader requests payout (EIP-712 signed) -> Vault processes payout, splitting between trader and protocol

**Key analytics tables for dashboards:**
- `tradingaccounts_evt_evalaccountcreated` -- new eval signups, assessment fees
- `tradingaccounts_evt_evalpassed` -- conversion rate from eval to funded
- `tradingaccounts_evt_fundedstatusupdated` -- funded account lifecycle
- `tradingaccounts_evt_payoutrequested` -- payout demand
- `vault_evt_payoutprocessed` -- actual payouts, revenue (protocolAmount), trader earnings
- `tradingaccounts_evt_equityupdated` -- track P&L over time
- `tradingaccounts_evt_usersuspended` / `userunsuspended` -- compliance actions