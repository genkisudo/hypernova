// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity ^0.8.13;

import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title Vault
/// @notice Holds USDC and handles profit splitting for trader withdrawals
/// @dev Only the TradingAccounts contract can initiate withdrawals. Owner can configure profit split and withdraw protocol fees.
contract Vault is Ownable {
    // ============ Errors ============

    /// @notice Thrown when contract is paused
    error Paused();

    /// @notice Thrown when caller is not the TradingAccounts contract
    error NotTradingAccounts();

    /// @notice Thrown when withdrawal amount exceeds the maximum limit (checked against the pre-split amount, before fees are deducted)
    error ExceedsMaxWithdrawal();

    /// @notice Thrown when vault has insufficient balance for transfer
    error InsufficientBalance();

    /// @notice Thrown when a zero address is provided
    error ZeroAddress();

    /// @notice Thrown when a zero amount is provided
    error ZeroAmount();

    /// @notice Thrown when profit split is invalid (must be MIN_PROFIT_SPLIT-10000 BPS)
    error InvalidProfitSplit();

    /// @notice Thrown when profitSplit + bonusBps exceeds BPS_DENOMINATOR
    error InvalidBonusSplit();

    // ============ Events ============

    /// @notice Emitted when a payout is processed
    /// @param trader Address of the trader receiving funds
    /// @param traderAmount Amount sent to the trader
    /// @param protocolAmount Amount retained by the protocol
    event PayoutProcessed(address indexed trader, uint256 traderAmount, uint256 protocolAmount);

    /// @notice Emitted when the maximum withdrawal limit is updated
    /// @param newLimit New maximum withdrawal limit
    event MaxWithdrawalLimitUpdated(uint256 newLimit);

    /// @notice Emitted when the paused state changes
    /// @param isPaused New paused state
    event PausedStateChanged(bool isPaused);

    /// @notice Emitted when the profit split is updated
    /// @param profitSplit New profit split in basis points
    event ProfitSplitUpdated(uint256 profitSplit);

    // ============ Constants ============

    /// @notice Denominator for basis points calculations (10000 = 100%)
    uint256 public constant BPS_DENOMINATOR = 10_000;

    // ============ Immutables ============

    /// @notice USDC token contract
    address public immutable USDC;

    /// @notice Address of the TradingAccounts contract authorized to call withdraw
    address public immutable TRADING_ACCOUNTS;

    /// @notice Minimum profit split in basis points (e.g., 8000 = 80%)
    uint256 public immutable MIN_PROFIT_SPLIT;

    // ============ State ============

    /// @notice Whether withdrawals are paused
    bool public paused;

    /// @notice Maximum amount that can be withdrawn in a single transaction (applied to the pre-split amount, before fees)
    uint256 public maxWithdrawalLimit;

    /// @notice Percentage of profit that goes to the trader in basis points (e.g., 8000 = 80%)
    uint256 public profitSplit;

    // ============ Constructor ============

    /// @notice Initializes the vault with configuration parameters
    /// @param _owner Address of the contract owner
    /// @param _tradingAccounts Address of the TradingAccounts contract
    /// @param _usdc Address of the USDC token contract
    /// @param _maxWithdrawalLimit Maximum withdrawal amount per transaction (applied to the pre-split amount, before fees)
    /// @param _profitSplit Trader's share of profit in basis points (MIN_PROFIT_SPLIT-10000)
    /// @param _minProfitSplit Minimum allowed profit split in basis points
    constructor(
        address _owner,
        address _tradingAccounts,
        address _usdc,
        uint256 _maxWithdrawalLimit,
        uint256 _profitSplit,
        uint256 _minProfitSplit
    ) {
        if (_owner == address(0)) revert ZeroAddress();
        if (_tradingAccounts == address(0)) revert ZeroAddress();
        if (_usdc == address(0)) revert ZeroAddress();
        if (_minProfitSplit == 0 || _minProfitSplit > BPS_DENOMINATOR) revert InvalidProfitSplit();
        if (_profitSplit < _minProfitSplit || _profitSplit > BPS_DENOMINATOR) revert InvalidProfitSplit();
        _initializeOwner(_owner);
        MIN_PROFIT_SPLIT = _minProfitSplit;
        TRADING_ACCOUNTS = _tradingAccounts;
        USDC = _usdc;
        maxWithdrawalLimit = _maxWithdrawalLimit;
        profitSplit = _profitSplit;
    }

    // ============ Modifiers ============

    /// @notice Reverts if contract is paused
    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    /// @notice Restricts function access to TradingAccounts contract only
    modifier onlyTradingAccounts() {
        if (msg.sender != TRADING_ACCOUNTS) revert NotTradingAccounts();
        _;
    }

    // ============ Owner Functions ============

    /// @notice Pauses all withdrawals
    /// @dev Only callable by owner
    function pause() external onlyOwner {
        paused = true;
        emit PausedStateChanged(true);
    }

    /// @notice Unpauses withdrawals
    /// @dev Only callable by owner
    function unpause() external onlyOwner {
        paused = false;
        emit PausedStateChanged(false);
    }

    /// @notice Sets the maximum withdrawal limit per transaction (applied to the pre-split amount, before fees)
    /// @dev Only callable by owner
    /// @param _newLimit New maximum withdrawal limit (pre-split)
    function setMaxWithdrawalLimit(uint256 _newLimit) external onlyOwner {
        maxWithdrawalLimit = _newLimit;
        emit MaxWithdrawalLimitUpdated(_newLimit);
    }

    /// @notice Sets the profit split percentage for traders
    /// @dev Only callable by owner. Value is in basis points (e.g., 8000 = 80%)
    /// @param _profitSplit New profit split in basis points (MIN_PROFIT_SPLIT-10000)
    function setProfitSplit(uint256 _profitSplit) external onlyOwner {
        if (_profitSplit < MIN_PROFIT_SPLIT || _profitSplit > BPS_DENOMINATOR) revert InvalidProfitSplit();
        profitSplit = _profitSplit;
        emit ProfitSplitUpdated(_profitSplit);
    }

    /// @notice Withdraws accumulated protocol fees to the owner
    /// @dev Only callable by owner
    /// @param _amount Amount of USDC to withdraw
    function ownerWithdraw(uint256 _amount) external onlyOwner {
        if (_amount == 0) revert ZeroAmount();
        if (_amount > SafeTransferLib.balanceOf(USDC, address(this))) revert InsufficientBalance();

        SafeTransferLib.safeTransfer(USDC, owner(), _amount);
    }

    // ============ TradingAccounts Functions ============

    /// @notice Processes a trader payout with profit splitting
    /// @dev Only callable by TradingAccounts contract. Splits the amount between trader and protocol.
    ///      Trader receives (profitSplit + _bonusBps)% of the amount, protocol retains the rest.
    ///      maxWithdrawalLimit is enforced on the pre-split _amount (before fees are deducted).
    /// @param _trader Address of the trader to receive funds
    /// @param _amount Total profit amount to split
    /// @param _bonusBps Per-user bonus split in basis points (additive to profitSplit)
    function processPayout(address _trader, uint256 _amount, uint256 _bonusBps)
        external
        onlyTradingAccounts
        whenNotPaused
    {
        if (_trader == address(0)) revert ZeroAddress();
        if (_amount > maxWithdrawalLimit) revert ExceedsMaxWithdrawal();

        uint256 totalSplit = profitSplit + _bonusBps;
        if (totalSplit > BPS_DENOMINATOR) totalSplit = BPS_DENOMINATOR;

        // Calculate split: trader gets (profitSplit + bonus)%, protocol keeps the rest
        uint256 traderAmount = (_amount * totalSplit) / BPS_DENOMINATOR;

        if (traderAmount > SafeTransferLib.balanceOf(USDC, address(this))) revert InsufficientBalance();

        // Transfer trader's share (protocol share stays in vault)
        SafeTransferLib.safeTransfer(USDC, _trader, traderAmount);

        emit PayoutProcessed(_trader, traderAmount, _amount - traderAmount);
    }
}
