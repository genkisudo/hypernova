// SPDX-License-Identifier: LicenseRef-BUSL
pragma solidity ^0.8.13;

import {Ownable} from "solady/auth/Ownable.sol";
import {UUPSUpgradeable} from "solady/utils/UUPSUpgradeable.sol";
import {Initializable} from "solady/utils/Initializable.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

/// @notice Minimal interface for the Vault contract used by TradingAccounts to process trader payouts
interface IVault {
    function processPayout(address _trader, uint256 _amount, uint256 _bonusBps) external;
    function profitSplit() external view returns (uint256);
    function BPS_DENOMINATOR() external view returns (uint256);
}

/// @title TradingAccounts
/// @notice Manages trader evaluation and funded trading accounts for a prop trading firm
/// @dev Each trader has a user account containing multiple trading accounts that track evaluation and funded status.
///      Evaluation status (EvalStatus) is stored on-chain but without enforced transition ordering —
///      status transitions are also emitted as EvalStatusUpdated events for off-chain indexers to reconstruct history.
///
///      Storage gap (__gap) is intentionally omitted. Solady's base contracts (Ownable, UUPSUpgradeable, Initializable)
///      use fixed assembly-level storage slots (not sequential storage), so there is no collision risk with this
///      contract's state variables. New variables in future upgrades can safely be appended after existing ones.
contract TradingAccounts is Ownable, UUPSUpgradeable, Initializable, EIP712 {
    // ============ Errors ============

    /// @notice Thrown when attempting to create a user account that already exists
    error UserAccountAlreadyExists();

    /// @notice Thrown when attempting to access a non-existent user account
    error UserAccountDoesNotExist();

    /// @notice Thrown when the funded account does not exist
    error FundedAccountIdDoesNotExist();

    /// @notice Thrown when attempting to withdraw from a funded account that is not active
    error FundedAccountNotActive();

    /// @notice Thrown when attempting to withdraw with no profit available
    error NoProfit();

    /// @notice Thrown when withdrawal amount exceeds available profit
    error ExceedsWithdrawableAmount();

    /// @notice Thrown when vault address is not set
    error VaultNotSet();

    /// @notice Thrown when a zero address is provided
    error ZeroAddress();

    /// @notice Thrown when a zero amount is provided
    error ZeroAmount();

    /// @notice Thrown when bonus split would cause total split (profitSplit + bonus) to exceed 100%
    error BonusExceedsBpsCap();

    /// @notice Thrown when caller is not the admin
    error NotAdmin();

    /// @notice Thrown when withdrawal is not enabled (admin must call updateEquityAndSettle first)
    error CannotWithdraw();

    /// @notice Thrown when user account is suspended
    error UserIsSuspended();

    /// @notice Thrown when funded account is not awaiting signature
    error FundedAccountNotAwaitingSignature();

    /// @notice Thrown when attempting to set funded status to NONE
    error CannotSetFundedStatusToNone();

    /// @notice Thrown when attempting to set funded status to AWAITING_SIGNATURE (only set on creation)
    error CannotSetFundedStatusToAwaitingSignature();

    /// @notice Thrown when admin calls updateFundedStatus on an account that is still AWAITING_SIGNATURE
    /// @dev An account in AWAITING_SIGNATURE must leave the state via acceptFundedAccount or rejectFundedAccount
    error CannotUpdateStatusWhileAwaitingSignature();

    /// @notice Thrown when attempting to set eval status to PASSED via updateEvalStatus (use passEval instead)
    error CannotSetEvalStatusToPassed();

    /// @notice Thrown when a zero bytes32 ID is provided
    error ZeroId();

    /// @notice Thrown when caller is not the deployer during initialization
    error NotDeployer();

    /// @notice Thrown when the eval account does not exist
    error EvalAccountDoesNotExist();

    /// @notice Thrown when attempting to pass an eval account that is not in ACTIVE status
    error EvalAccountNotActive();

    /// @notice Thrown when an account ID has already been used (eval or funded)
    error IdAlreadyUsed();

    /// @notice Thrown when input array lengths do not match
    error ArrayLengthMismatch();

    /// @notice Thrown when the EIP-712 signature is invalid
    error InvalidSignature();

    /// @notice Thrown when the payout signature deadline has passed
    error SignatureExpired();

    /// @notice Thrown when the provided accept terms string does not hash to the stored accept terms hash
    error InvalidAcceptTerms();

    /// @notice Thrown when attempting to accept a funded account before the admin has set the accept terms hash
    error AcceptTermsHashNotSet();

    /// @notice Thrown when attempting to set the accept terms hash to zero
    error ZeroHash();

    // ============ Enums ============

    /// @notice Status of a trading account during evaluation phase
    /// @param ACTIVE Account is actively being evaluated
    /// @param PASSED Trader passed evaluation, eligible for funded account
    /// @param SUSPENDED Account temporarily suspended
    /// @param FAILED Trader failed evaluation
    /// @param CLOSED Account closed
    enum EvalStatus {
        ACTIVE,
        PASSED,
        SUSPENDED,
        FAILED,
        CLOSED
    }

    /// @notice Status of a funded trading account
    /// @param NONE No funded account created yet (default)
    /// @param AWAITING_SIGNATURE Funded account created, awaiting trader acceptance
    /// @param ACTIVE Trader accepted, actively trading
    /// @param CLOSED Account closed
    /// @param SUSPENDED Account temporarily suspended
    /// @param FAILED Account failed (e.g., violated rules)
    enum FundedStatus {
        NONE,
        AWAITING_SIGNATURE,
        ACTIVE,
        CLOSED,
        SUSPENDED,
        FAILED
    }

    // ============ Structs ============

    /// @notice Parameters for creating an evaluation trading account (event-sourced, not stored on-chain)
    /// @param initialEquity Starting equity amount
    /// @param dailyDrawdownLimit Maximum allowed daily drawdown
    /// @param maxDrawdownLimit Maximum allowed total drawdown
    /// @param profitTarget Profit target to pass evaluation
    /// @param assessmentFee Fee paid by the trader for this evaluation
    struct EvalParams {
        uint256 initialEquity;
        uint256 dailyDrawdownLimit;
        uint256 maxDrawdownLimit;
        uint256 profitTarget;
        uint256 assessmentFee;
    }

    /// @notice Represents an evaluation trading account for a trader
    /// @param evalStatus Current evaluation status (stored on-chain, no transition enforcement)
    /// @param initialEquity Starting equity amount (also used as existence check — zero means account doesn't exist)
    /// @param startOfDayBalance Balance at the start of the current trading day (for future drawdown enforcement)
    /// @param equity Current equity amount (changes with admin updates)
    /// @param dailyDrawdownLimit Maximum allowed daily drawdown
    /// @param maxDrawdownLimit Maximum allowed total drawdown
    /// @param profitTarget Profit target to pass evaluation
    struct EvalAccount {
        EvalStatus evalStatus;
        uint256 initialEquity;
        uint256 startOfDayBalance;
        uint256 equity;
        uint256 dailyDrawdownLimit;
        uint256 maxDrawdownLimit;
        uint256 profitTarget;
    }

    /// @notice Represents a funded trading account for a trader
    /// @param fundedStatus Current funded phase status (NONE means account doesn't exist)
    /// @param initialEquity Starting equity amount (constant baseline for profit calculation)
    /// @param startOfDayBalance Balance at the start of the current trading day (for future drawdown enforcement)
    /// @param equity Current equity amount (changes with P&L and withdrawals)
    /// @param canWithdraw Whether withdrawal is currently enabled (set by admin via updateEquityAndSettle)
    /// @param dailyDrawdownLimit Maximum allowed daily drawdown (inherited from eval account)
    /// @param maxDrawdownLimit Maximum allowed total drawdown (inherited from eval account)
    struct FundedAccount {
        FundedStatus fundedStatus;
        uint256 initialEquity;
        uint256 startOfDayBalance;
        uint256 equity;
        bool canWithdraw;
        uint256 dailyDrawdownLimit;
        uint256 maxDrawdownLimit;
    }

    // ============ Events ============

    /// @notice Emitted when a new user account is created
    /// @param trader Address of the trader
    event UserAccountCreated(address indexed trader);

    /// @notice Emitted when a new evaluation trading account is created
    /// @param trader Address of the trader
    /// @param evalAccountId ID of the eval account
    /// @param initialEquity Starting equity amount
    /// @param startOfDayBalance Starting value for start-of-day balance (equals initialEquity at creation)
    /// @param dailyDrawdownLimit Maximum allowed daily drawdown
    /// @param maxDrawdownLimit Maximum allowed total drawdown
    /// @param profitTarget Profit target to pass evaluation
    /// @param assessmentFee Fee paid by the trader for this evaluation
    event EvalAccountCreated(
        address indexed trader,
        bytes32 indexed evalAccountId,
        uint256 initialEquity,
        uint256 startOfDayBalance,
        uint256 dailyDrawdownLimit,
        uint256 maxDrawdownLimit,
        uint256 profitTarget,
        uint256 assessmentFee
    );

    /// @notice Emitted when evaluation status is updated
    /// @param trader Address of the trader
    /// @param evalAccountId ID of the eval account
    /// @param status New evaluation status
    event EvalStatusUpdated(address indexed trader, bytes32 indexed evalAccountId, EvalStatus status);

    /// @notice Emitted when a funded account is created (after passing evaluation)
    /// @param trader Address of the trader
    /// @param fundedAccountId ID of the trading account
    /// @param initialEquity Starting equity inherited from the eval account
    /// @param startOfDayBalance Starting value for start-of-day balance (equals initialEquity at creation)
    /// @param dailyDrawdownLimit Daily drawdown limit inherited from the eval account
    /// @param maxDrawdownLimit Max drawdown limit inherited from the eval account
    event FundedAccountCreated(
        address indexed trader,
        bytes32 indexed fundedAccountId,
        uint256 initialEquity,
        uint256 startOfDayBalance,
        uint256 dailyDrawdownLimit,
        uint256 maxDrawdownLimit
    );

    /// @notice Emitted when funded account status is updated
    /// @param trader Address of the trader
    /// @param fundedAccountId ID of the trading account
    /// @param status New funded status
    event FundedStatusUpdated(address indexed trader, bytes32 indexed fundedAccountId, FundedStatus status);

    /// @notice Emitted when equity is updated for a trading account
    /// @param trader Address of the trader
    /// @param fundedAccountId ID of the trading account
    /// @param equity New equity amount
    event EquityUpdated(address indexed trader, bytes32 indexed fundedAccountId, uint256 equity);

    /// @notice Emitted when a payout is requested
    /// @param trader Address of the trader
    /// @param fundedAccountId ID of the trading account
    /// @param amount Amount of profit paid out
    /// @param nonce The nonce used for this payout's EIP-712 signature
    event PayoutRequested(address indexed trader, bytes32 indexed fundedAccountId, uint256 amount, uint256 nonce);

    /// @notice Emitted when vault address is updated
    /// @param vault New vault address
    event VaultUpdated(address indexed vault);

    /// @notice Emitted when admin address is updated
    /// @param admin New admin address
    event AdminUpdated(address indexed admin);

    /// @notice Emitted when a user is suspended
    /// @param trader Address of the suspended trader
    event UserSuspended(address indexed trader);

    /// @notice Emitted when a user is unsuspended
    /// @param trader Address of the unsuspended trader
    event UserUnsuspended(address indexed trader);

    /// @notice Emitted when a user's bonus split is updated
    /// @param trader Address of the trader
    /// @param bonusBps Bonus split in basis points
    event UserBonusSplitUpdated(address indexed trader, uint256 bonusBps);

    /// @notice Emitted when equity is topped up for a trading account
    /// @param trader Address of the trader
    /// @param fundedAccountId ID of the trading account
    /// @param amount Amount added to both initialEquity and equity
    event EquityToppedUp(address indexed trader, bytes32 indexed fundedAccountId, uint256 amount);

    /// @notice Emitted when start-of-day balance is updated for an eval account
    /// @param trader Address of the trader
    /// @param evalAccountId ID of the eval account
    /// @param startOfDayBalance New start-of-day balance value
    event EvalStartOfDayBalanceUpdated(
        address indexed trader, bytes32 indexed evalAccountId, uint256 startOfDayBalance
    );

    /// @notice Emitted when start-of-day balance is updated for a funded trading account
    /// @param trader Address of the trader
    /// @param fundedAccountId ID of the trading account
    /// @param startOfDayBalance New start-of-day balance value
    event StartOfDayBalanceUpdated(address indexed trader, bytes32 indexed fundedAccountId, uint256 startOfDayBalance);

    /// @notice Emitted when a trader increments their nonce (invalidating pending signatures)
    /// @param trader Address of the trader
    /// @param newNonce The new nonce value
    event NonceIncremented(address indexed trader, uint256 newNonce);

    /// @notice Emitted when a trader accepts a funded account
    /// @param trader Address of the trader
    /// @param fundedAccountId ID of the trading account
    /// @param acceptTermsHash The hash of the accept-terms string the trader signed over
    /// @param nonce The nonce used for this acceptance's EIP-712 signature
    event FundedAccountAccepted(
        address indexed trader, bytes32 indexed fundedAccountId, bytes32 acceptTermsHash, uint256 nonce
    );

    /// @notice Emitted when the admin updates the stored accept-terms hash
    /// @param newHash The new accept-terms hash
    event AcceptTermsHashUpdated(bytes32 indexed oldHash, bytes32 indexed newHash);

    /// @notice Emitted when a trader rejects a funded account
    /// @param trader Address of the trader
    /// @param fundedAccountId ID of the trading account
    event FundedAccountRejected(address indexed trader, bytes32 indexed fundedAccountId);

    /// @notice Emitted when an eval account passes evaluation
    /// @param trader Address of the trader
    /// @param evalAccountId ID of the eval account
    /// @param initialEquity Starting equity of the eval account
    /// @param equity Current equity of the eval account at time of passing
    /// @param profitTarget Profit target that was hit
    /// @param fundedAccountId ID of the funded trading account created from this eval
    event EvalPassed(
        address indexed trader,
        bytes32 indexed evalAccountId,
        uint256 initialEquity,
        uint256 equity,
        uint256 profitTarget,
        bytes32 fundedAccountId
    );

    // ============ Constants ============

    /// @notice EIP-712 typehash for the Payout struct
    bytes32 public constant PAYOUT_TYPEHASH =
        keccak256("Payout(address trader,bytes32 fundedAccountId,uint256 amount,uint256 nonce,uint256 deadline)");

    /// @notice EIP-712 typehash for the AcceptFundedAccount struct
    bytes32 public constant ACCEPT_FUNDED_ACCOUNT_TYPEHASH = keccak256(
        "AcceptFundedAccount(address trader,bytes32 fundedAccountId,string acceptTerms,uint256 nonce,uint256 deadline)"
    );

    // ============ State ============

    /// @notice Address of the vault contract that handles withdrawals
    address public vault;

    /// @notice Address of the admin who manages accounts
    address public admin;

    /// @notice Whether a user account exists
    mapping(address => bool) public userExists;

    /// @notice Trading accounts indexed by trader address and account ID
    mapping(address => mapping(bytes32 => FundedAccount)) public fundedAccounts;

    /// @notice Whether a user account is suspended (blocks all user actions across all trading accounts)
    mapping(address => bool) public userSuspended;

    /// @notice Per-user bonus split in basis points (additive to global profitSplit in the Vault)
    mapping(address => uint256) public userBonusBps;

    /// @notice Eval accounts indexed by trader address and eval account ID
    mapping(address => mapping(bytes32 => EvalAccount)) public evalAccounts;

    /// @notice Maps account IDs to the trader address that owns them (enforces global ID uniqueness)
    mapping(bytes32 => address) public idOwner;

    /// @notice Sequential nonces for EIP-712 signatures (per trader)
    mapping(address => uint256) public nonces;

    /// @notice keccak256 hash of the current accept-terms string that traders must sign when accepting a funded account
    /// @dev Set by admin via setAcceptTermsHash. A zero value bricks acceptFundedAccount until set.
    bytes32 public acceptTermsHash;

    // ============ Immutables ============

    /// @notice Address that deployed the implementation, used to restrict who can call initialize
    address public immutable DEPLOYER;

    // ============ Constructor ============

    /// @notice Disables initializers on the implementation contract and records deployer
    constructor() {
        DEPLOYER = msg.sender;
        _disableInitializers();
    }

    /// @notice Initializes the contract with owner and admin
    /// @dev Only callable by the deployer to prevent front-running proxy initialization
    /// @param _owner Address of the contract owner
    /// @param _admin Address of the admin
    function initialize(address _owner, address _admin) external initializer {
        if (msg.sender != DEPLOYER) revert NotDeployer();
        if (_owner == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();
        _initializeOwner(_owner);
        admin = _admin;
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev Only callable by owner
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ============ Modifiers ============

    /// @notice Restricts function access to admin only
    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    /// @notice Reverts if the specified user account is suspended
    /// @param _trader Address of the trader to check
    modifier whenNotSuspended(address _trader) {
        if (userSuspended[_trader]) revert UserIsSuspended();
        _;
    }

    /// @notice Reverts if the given trader does not have a user account
    /// @param _trader Address of the trader to check
    modifier whenUserExists(address _trader) {
        if (!userExists[_trader]) revert UserAccountDoesNotExist();
        _;
    }

    // ============ Owner Functions ============

    /// @notice Sets the vault contract address
    /// @dev Only callable by owner
    /// @param _vault Address of the vault contract
    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert ZeroAddress();
        vault = _vault;
        emit VaultUpdated(_vault);
    }

    /// @notice Sets the admin address
    /// @dev Only callable by owner
    /// @param _admin Address of the new admin
    function setAdmin(address _admin) external onlyOwner {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
        emit AdminUpdated(_admin);
    }

    // ============ Admin Functions ============

    /// @notice Creates a new user account for a trader
    /// @dev Only callable by admin. Reverts if user account already exists
    /// @param _trader Address of the trader
    function createUserAccount(address _trader) external onlyAdmin {
        if (_trader == address(0)) revert ZeroAddress();
        if (userExists[_trader]) revert UserAccountAlreadyExists();

        userExists[_trader] = true;
        emit UserAccountCreated(_trader);
    }

    /// @notice Creates a new evaluation trading account for an existing user
    /// @dev Only callable by admin. Reverts if user account doesn't exist.
    /// @param _trader Address of the trader
    /// @param _evalAccountId Admin-provided unique ID for the eval account (must be globally unused)
    /// @param _params Evaluation account parameters
    function createEvalAccount(address _trader, bytes32 _evalAccountId, EvalParams calldata _params)
        external
        onlyAdmin
        whenUserExists(_trader)
    {
        _createEvalAccount(_trader, _evalAccountId, _params);
    }

    /// @notice Updates the evaluation status of an eval account
    /// @dev Only callable by admin. Stores status on-chain but does not enforce valid transitions.
    ///      Cannot set status to PASSED — use passEval() instead.
    /// @param _trader Address of the trader
    /// @param _evalAccountId ID of the eval account
    /// @param _status New evaluation status (cannot be PASSED)
    function updateEvalStatus(address _trader, bytes32 _evalAccountId, EvalStatus _status)
        external
        onlyAdmin
        whenUserExists(_trader)
    {
        if (_status == EvalStatus.PASSED) revert CannotSetEvalStatusToPassed();
        if (evalAccounts[_trader][_evalAccountId].initialEquity == 0) revert EvalAccountDoesNotExist();

        evalAccounts[_trader][_evalAccountId].evalStatus = _status;
        emit EvalStatusUpdated(_trader, _evalAccountId, _status);
    }

    /// @notice Passes an eval account and creates a new funded trading account with a separate ID
    /// @dev Only callable by admin. Reads initialEquity from eval account storage for the funded account.
    /// @param _trader Address of the trader
    /// @param _evalAccountId ID of the eval account that passed
    /// @param _fundedAccountId ID for the new funded trading account
    function passEval(address _trader, bytes32 _evalAccountId, bytes32 _fundedAccountId)
        external
        onlyAdmin
        whenUserExists(_trader)
    {
        EvalAccount storage evalAccount = evalAccounts[_trader][_evalAccountId];
        if (evalAccount.initialEquity == 0) revert EvalAccountDoesNotExist();
        if (evalAccount.evalStatus != EvalStatus.ACTIVE) revert EvalAccountNotActive();

        evalAccount.evalStatus = EvalStatus.PASSED;
        emit EvalStatusUpdated(_trader, _evalAccountId, EvalStatus.PASSED);
        emit EvalPassed(
            _trader,
            _evalAccountId,
            evalAccount.initialEquity,
            evalAccount.equity,
            evalAccount.profitTarget,
            _fundedAccountId
        );

        _createFundedAccount(
            _trader,
            _fundedAccountId,
            evalAccount.initialEquity,
            evalAccount.dailyDrawdownLimit,
            evalAccount.maxDrawdownLimit
        );
    }

    /// @notice Updates the funded status of a trading account
    /// @dev Only callable by admin.
    /// @param _trader Address of the trader
    /// @param _fundedAccountId ID of the trading account
    /// @param _status New funded status
    function updateFundedStatus(address _trader, bytes32 _fundedAccountId, FundedStatus _status)
        external
        onlyAdmin
        whenUserExists(_trader)
    {
        if (_status == FundedStatus.NONE) revert CannotSetFundedStatusToNone();
        if (_status == FundedStatus.AWAITING_SIGNATURE) revert CannotSetFundedStatusToAwaitingSignature();
        FundedStatus currentStatus = fundedAccounts[_trader][_fundedAccountId].fundedStatus;
        if (currentStatus == FundedStatus.NONE) revert FundedAccountIdDoesNotExist();
        if (currentStatus == FundedStatus.AWAITING_SIGNATURE) revert CannotUpdateStatusWhileAwaitingSignature();

        fundedAccounts[_trader][_fundedAccountId].fundedStatus = _status;
        emit FundedStatusUpdated(_trader, _fundedAccountId, _status);
    }

    /// @notice Updates the equity of a trading account
    /// @dev Only callable by admin. Does not enable withdrawals. Uses absolute amount.
    /// @param _trader Address of the trader
    /// @param _fundedAccountId ID of the trading account
    /// @param _amount Amount to update equity to
    function updateFundedEquity(address _trader, bytes32 _fundedAccountId, uint256 _amount) external onlyAdmin {
        _updateFundedEquity(_trader, _fundedAccountId, _amount);
    }

    /// @notice Batch updates equity for multiple trading accounts in a single transaction
    /// @dev Only callable by admin. All arrays must have the same length. Uses absolute amounts.
    /// @param _traders Array of trader addresses
    /// @param _fundedAccountIds Array of trading account IDs
    /// @param _amounts Array of equity change amounts
    /// @param _isEval Array of booleans indicating eval account (true) or funded account (false)
    function batchUpdateEquity(
        address[] calldata _traders,
        bytes32[] calldata _fundedAccountIds,
        uint256[] calldata _amounts,
        bool[] calldata _isEval
    ) external onlyAdmin {
        if (
            _traders.length != _fundedAccountIds.length || _traders.length != _amounts.length
                || _traders.length != _isEval.length
        ) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < _traders.length; i++) {
            if (_isEval[i]) {
                _updateEvalEquity(_traders[i], _fundedAccountIds[i], _amounts[i]);
            } else {
                _updateFundedEquity(_traders[i], _fundedAccountIds[i], _amounts[i]);
            }
        }
    }

    /// @notice Updates equity to an absolute amount and enables withdrawal for a funded account
    /// @dev Only callable by admin. Call this when positions are closed to allow trader to withdraw.
    /// @param _trader Address of the trader
    /// @param _fundedAccountId ID of the trading account
    /// @param _amount Amount to update equity to
    function updateEquityAndSettle(address _trader, bytes32 _fundedAccountId, uint256 _amount) external onlyAdmin {
        _updateFundedEquity(_trader, _fundedAccountId, _amount);
        fundedAccounts[_trader][_fundedAccountId].canWithdraw = true;
    }

    /// @notice Suspends a user account, blocking all trader-initiated actions across all of their trading accounts
    /// @dev Only callable by admin. Blocks trader-initiated actions (accept, reject, payout) until unsuspended.
    ///      Admin functions remain fully available on the suspended user's accounts.
    /// @param _trader Address of the trader to suspend
    function suspendUser(address _trader) external onlyAdmin whenUserExists(_trader) {
        userSuspended[_trader] = true;
        emit UserSuspended(_trader);
    }

    /// @notice Unsuspends a user account, restoring user actions
    /// @dev Only callable by admin
    /// @param _trader Address of the trader to unsuspend
    function unsuspendUser(address _trader) external onlyAdmin whenUserExists(_trader) {
        userSuspended[_trader] = false;
        emit UserUnsuspended(_trader);
    }

    /// @notice Sets the keccak256 hash of the accept-terms string traders must sign over
    /// @dev Only callable by admin. Rejects zero to avoid accidentally bricking acceptFundedAccount.
    /// @param _hash The new accept-terms hash
    function setAcceptTermsHash(bytes32 _hash) external onlyAdmin {
        if (_hash == bytes32(0)) revert ZeroHash();
        bytes32 oldHash = acceptTermsHash;
        acceptTermsHash = _hash;
        emit AcceptTermsHashUpdated(oldHash, _hash);
    }

    /// @notice Sets a per-user bonus split in basis points (additive to global profitSplit in the Vault)
    /// @dev Only callable by admin.
    /// @param _trader Address of the trader
    /// @param _bonusBps Bonus split in basis points
    function setUserBonusSplit(address _trader, uint256 _bonusBps) external onlyAdmin whenUserExists(_trader) {
        if (vault == address(0)) revert VaultNotSet();
        if (_bonusBps + IVault(vault).profitSplit() > IVault(vault).BPS_DENOMINATOR()) revert BonusExceedsBpsCap();
        userBonusBps[_trader] = _bonusBps;
        emit UserBonusSplitUpdated(_trader, _bonusBps);
    }

    /// @notice Tops up the equity for a funded account by increasing both initialEquity and equity
    /// @dev Only callable by admin. Both values increase by the same amount
    ///      so the trader's current profit/loss remains unchanged.
    /// @param _trader Address of the trader
    /// @param _fundedAccountId ID of the funded account
    /// @param _amount Amount to add to both initialEquity and equity
    function topUpEquity(address _trader, bytes32 _fundedAccountId, uint256 _amount) external onlyAdmin {
        _validateEquityUpdate(_trader, _fundedAccountId);

        FundedAccount storage account = fundedAccounts[_trader][_fundedAccountId];
        account.initialEquity += _amount;
        account.equity += _amount;

        emit EquityToppedUp(_trader, _fundedAccountId, _amount);
        emit EquityUpdated(_trader, _fundedAccountId, account.equity);
    }

    /// @notice Updates the start-of-day balance for an eval account
    /// @dev Only callable by admin. Used to snapshot balance at the start of each trading day for future drawdown enforcement.
    /// @param _trader Address of the trader
    /// @param _evalAccountId ID of the eval account
    /// @param _startOfDayBalance New start-of-day balance value
    function updateEvalStartOfDayBalance(address _trader, bytes32 _evalAccountId, uint256 _startOfDayBalance)
        external
        onlyAdmin
        whenUserExists(_trader)
    {
        if (evalAccounts[_trader][_evalAccountId].initialEquity == 0) revert EvalAccountDoesNotExist();
        if (evalAccounts[_trader][_evalAccountId].evalStatus != EvalStatus.ACTIVE) revert EvalAccountNotActive();

        evalAccounts[_trader][_evalAccountId].startOfDayBalance = _startOfDayBalance;
        emit EvalStartOfDayBalanceUpdated(_trader, _evalAccountId, _startOfDayBalance);
    }

    /// @notice Updates the start-of-day balance for a funded account
    /// @dev Only callable by admin. Used to snapshot balance at the start of each trading day for future drawdown enforcement.
    /// @param _trader Address of the trader
    /// @param _fundedAccountId ID of the funded account
    /// @param _startOfDayBalance New start-of-day balance value
    function updateStartOfDayBalance(address _trader, bytes32 _fundedAccountId, uint256 _startOfDayBalance)
        external
        onlyAdmin
        whenUserExists(_trader)
    {
        if (fundedAccounts[_trader][_fundedAccountId].fundedStatus == FundedStatus.NONE) {
            revert FundedAccountIdDoesNotExist();
        }
        if (fundedAccounts[_trader][_fundedAccountId].fundedStatus != FundedStatus.ACTIVE) {
            revert FundedAccountNotActive();
        }

        fundedAccounts[_trader][_fundedAccountId].startOfDayBalance = _startOfDayBalance;
        emit StartOfDayBalanceUpdated(_trader, _fundedAccountId, _startOfDayBalance);
    }

    /// @notice Updates the equity of an eval account
    /// @dev Only callable by admin. Uses absolute amount.
    /// @param _trader Address of the trader
    /// @param _evalAccountId ID of the eval account
    /// @param _amount Amount to update equity to
    function updateEvalEquity(address _trader, bytes32 _evalAccountId, uint256 _amount) external onlyAdmin {
        _updateEvalEquity(_trader, _evalAccountId, _amount);
    }

    /// @notice Internal function to update funded account equity and emit event
    /// @param _trader Address of the trader
    /// @param _fundedAccountId ID of the funded account
    /// @param _amount Amount to update equity to
    function _updateFundedEquity(address _trader, bytes32 _fundedAccountId, uint256 _amount) internal {
        _validateEquityUpdate(_trader, _fundedAccountId);

        FundedAccount storage account = fundedAccounts[_trader][_fundedAccountId];
        account.equity = _amount;
        account.canWithdraw = false;
        emit EquityUpdated(_trader, _fundedAccountId, account.equity);
    }

    /// @notice Validates common preconditions for equity updates
    /// @param _trader Address of the trader
    /// @param _fundedAccountId ID of the funded account
    function _validateEquityUpdate(address _trader, bytes32 _fundedAccountId) internal view {
        if (!userExists[_trader]) revert UserAccountDoesNotExist();
        if (fundedAccounts[_trader][_fundedAccountId].fundedStatus == FundedStatus.NONE) {
            revert FundedAccountIdDoesNotExist();
        }
    }

    /// @notice Internal function to update eval account equity and emit event
    /// @param _trader Address of the trader
    /// @param _evalAccountId ID of the eval account
    /// @param _amount Amount to update equity to
    function _updateEvalEquity(address _trader, bytes32 _evalAccountId, uint256 _amount) internal {
        _validateEvalEquityUpdate(_trader, _evalAccountId);

        EvalAccount storage evalAccount = evalAccounts[_trader][_evalAccountId];
        evalAccount.equity = _amount;
        emit EquityUpdated(_trader, _evalAccountId, evalAccount.equity);
    }

    /// @notice Validates common preconditions for eval equity updates
    /// @param _trader Address of the trader
    /// @param _evalAccountId ID of the eval account
    function _validateEvalEquityUpdate(address _trader, bytes32 _evalAccountId) internal view {
        if (!userExists[_trader]) revert UserAccountDoesNotExist();
        if (evalAccounts[_trader][_evalAccountId].initialEquity == 0) revert EvalAccountDoesNotExist();
    }

    // ============ User Functions ============

    /// @notice Accepts a funded account using an EIP-712 signature from the trader
    /// @dev A relayer submits the acceptance on behalf of the trader.
    ///      The trader signs over (trader, fundedAccountId, acceptTerms, nonce, deadline).
    ///      The provided `_acceptTermsHash` must equal the currently stored `acceptTermsHash`.
    ///      Passing the hash directly (instead of the plaintext string) avoids an on-chain keccak256 of
    ///      arbitrary-length calldata; the EIP-712 signed type still encodes the terms as a `string`,
    ///      because EIP-712 hashes dynamic types before encoding so the struct hash is identical either way.
    /// @param _trader Address of the trader who signed
    /// @param _fundedAccountId ID of the funded account
    /// @param _deadline Timestamp after which the signature is no longer valid
    /// @param _acceptTermsHash keccak256 hash of the accept-terms string the trader is agreeing to
    /// @param _signature EIP-712 signature from the trader
    function acceptFundedAccount(
        address _trader,
        bytes32 _fundedAccountId,
        uint256 _deadline,
        bytes32 _acceptTermsHash,
        bytes calldata _signature
    ) external whenNotSuspended(_trader) whenUserExists(_trader) {
        if (block.timestamp > _deadline) revert SignatureExpired();
        if (fundedAccounts[_trader][_fundedAccountId].fundedStatus != FundedStatus.AWAITING_SIGNATURE) {
            revert FundedAccountNotAwaitingSignature();
        }

        bytes32 storedTermsHash = acceptTermsHash;
        if (storedTermsHash == bytes32(0)) revert AcceptTermsHashNotSet();
        if (_acceptTermsHash != storedTermsHash) revert InvalidAcceptTerms();

        uint256 nonce = nonces[_trader]++;

        bytes32 structHash = keccak256(
            abi.encode(ACCEPT_FUNDED_ACCOUNT_TYPEHASH, _trader, _fundedAccountId, _acceptTermsHash, nonce, _deadline)
        );
        bytes32 digest = _hashTypedData(structHash);

        address signer = ECDSA.recoverCalldata(digest, _signature);
        if (signer != _trader) revert InvalidSignature();

        fundedAccounts[_trader][_fundedAccountId].fundedStatus = FundedStatus.ACTIVE;
        emit FundedAccountAccepted(_trader, _fundedAccountId, _acceptTermsHash, nonce);
        emit FundedStatusUpdated(_trader, _fundedAccountId, FundedStatus.ACTIVE);
    }

    /// @notice Rejects a funded account that is awaiting the trader's signature
    /// @dev Only callable by the trader who owns the account. Reverts if user is suspended.
    /// @param _fundedAccountId ID of the funded account
    function rejectFundedAccount(bytes32 _fundedAccountId)
        external
        whenNotSuspended(msg.sender)
        whenUserExists(msg.sender)
    {
        if (fundedAccounts[msg.sender][_fundedAccountId].fundedStatus != FundedStatus.AWAITING_SIGNATURE) {
            revert FundedAccountNotAwaitingSignature();
        }

        fundedAccounts[msg.sender][_fundedAccountId].fundedStatus = FundedStatus.CLOSED;
        emit FundedAccountRejected(msg.sender, _fundedAccountId);
        emit FundedStatusUpdated(msg.sender, _fundedAccountId, FundedStatus.CLOSED);
    }

    /// @notice Requests a payout of profit from a funded account using an EIP-712 signature
    /// @dev A relayer submits the payout on behalf of the trader.
    ///      The trader signs over (trader, fundedAccountId, amount, nonce, deadline).
    ///      Admin must call updateEquityAndSettle first to enable payout.
    /// @param _trader Address of the trader who signed
    /// @param _fundedAccountId ID of the funded account
    /// @param _amount Amount of profit to pay out
    /// @param _deadline Timestamp after which the signature is no longer valid
    /// @param _signature EIP-712 signature from the trader
    function requestPayout(
        address _trader,
        bytes32 _fundedAccountId,
        uint256 _amount,
        uint256 _deadline,
        bytes calldata _signature
    ) external whenNotSuspended(_trader) whenUserExists(_trader) {
        if (block.timestamp > _deadline) revert SignatureExpired();
        if (_amount == 0) revert ZeroAmount();
        if (vault == address(0)) revert VaultNotSet();
        if (fundedAccounts[_trader][_fundedAccountId].fundedStatus == FundedStatus.NONE) {
            revert FundedAccountIdDoesNotExist();
        }

        uint256 nonce = nonces[_trader]++;

        bytes32 structHash =
            keccak256(abi.encode(PAYOUT_TYPEHASH, _trader, _fundedAccountId, _amount, nonce, _deadline));
        bytes32 digest = _hashTypedData(structHash);

        address signer = ECDSA.recoverCalldata(digest, _signature);
        if (signer != _trader) revert InvalidSignature();

        _executePayout(_trader, _fundedAccountId, _amount, nonce);
    }

    /// @notice Increments the caller's nonce, invalidating any pending signatures
    /// @dev The nonce is shared between `acceptFundedAccount` and `requestPayout`, so a single bump
    ///      invalidates every pending signature across both flows.
    function incrementNonce() external {
        uint256 newNonce = ++nonces[msg.sender];
        emit NonceIncremented(msg.sender, newNonce);
    }

    // ============ View Functions ============

    /// @notice Gets the profit or loss for a funded account
    /// @dev Returns (0, false) for nonexistent accounts instead of reverting
    /// @param _trader Address of the trader
    /// @param _fundedAccountId ID of the funded account
    /// @return amount The absolute value of profit or loss (0 if account doesn't exist)
    /// @return isProfit True if in profit, false if in loss or account doesn't exist
    function getProfitOrLoss(address _trader, bytes32 _fundedAccountId)
        external
        view
        returns (uint256 amount, bool isProfit)
    {
        if (!userExists[_trader]) return (0, false);
        if (fundedAccounts[_trader][_fundedAccountId].fundedStatus == FundedStatus.NONE) return (0, false);

        FundedAccount storage sub = fundedAccounts[_trader][_fundedAccountId];

        if (sub.equity > sub.initialEquity) {
            return (sub.equity - sub.initialEquity, true);
        } else {
            return (sub.initialEquity - sub.equity, false);
        }
    }

    /// @notice Gets the maximum withdrawable profit for a funded account, considering all eligibility conditions
    /// @param _trader Address of the trader
    /// @param _fundedAccountId ID of the funded account
    /// @return Maximum amount that can be withdrawn right now (0 if not eligible or no profit)
    function getMaxWithdrawable(address _trader, bytes32 _fundedAccountId) external view returns (uint256) {
        if (!userExists[_trader]) return 0;
        if (fundedAccounts[_trader][_fundedAccountId].fundedStatus == FundedStatus.NONE) return 0;
        if (userSuspended[_trader]) return 0;

        FundedAccount storage sub = fundedAccounts[_trader][_fundedAccountId];

        if (!sub.canWithdraw) return 0;
        if (sub.fundedStatus != FundedStatus.ACTIVE) return 0;
        if (sub.equity <= sub.initialEquity) return 0;

        return sub.equity - sub.initialEquity;
    }

    // ============ EIP-712 ============

    /// @dev Returns the domain name and version for EIP-712
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "TradingAccounts";
        version = "1";
    }

    // ============ Internal Functions ============

    /// @notice Executes payout logic for a trader
    /// @param _trader Address of the trader
    /// @param _fundedAccountId ID of the funded account
    /// @param _amount Amount of profit to pay out
    /// @param _nonce The nonce used for this payout's EIP-712 signature
    function _executePayout(address _trader, bytes32 _fundedAccountId, uint256 _amount, uint256 _nonce) internal {
        FundedAccount storage sub = fundedAccounts[_trader][_fundedAccountId];

        if (!sub.canWithdraw) revert CannotWithdraw();
        if (sub.fundedStatus != FundedStatus.ACTIVE) revert FundedAccountNotActive();
        if (sub.equity <= sub.initialEquity) revert NoProfit();

        uint256 profit = sub.equity - sub.initialEquity;
        if (_amount > profit) revert ExceedsWithdrawableAmount();

        emit PayoutRequested(_trader, _fundedAccountId, _amount, _nonce);

        sub.equity -= _amount;
        emit EquityUpdated(_trader, _fundedAccountId, sub.equity);

        sub.canWithdraw = false;

        IVault(vault).processPayout(_trader, _amount, userBonusBps[_trader]);
    }

    /// @notice Creates a new evaluation trading account with on-chain storage
    /// @param _trader Address of the trader
    /// @param _evalAccountId Admin-provided unique ID for the eval account
    /// @param _params Evaluation account parameters
    function _createEvalAccount(address _trader, bytes32 _evalAccountId, EvalParams calldata _params) internal {
        if (_evalAccountId == bytes32(0)) revert ZeroId();
        if (_params.initialEquity == 0) revert ZeroAmount();
        if (idOwner[_evalAccountId] != address(0)) revert IdAlreadyUsed();

        idOwner[_evalAccountId] = _trader;

        EvalAccount storage evalAccount = evalAccounts[_trader][_evalAccountId];
        evalAccount.evalStatus = EvalStatus.ACTIVE;
        evalAccount.initialEquity = _params.initialEquity;
        evalAccount.equity = _params.initialEquity;
        evalAccount.startOfDayBalance = _params.initialEquity;
        evalAccount.dailyDrawdownLimit = _params.dailyDrawdownLimit;
        evalAccount.maxDrawdownLimit = _params.maxDrawdownLimit;
        evalAccount.profitTarget = _params.profitTarget;

        emit EvalAccountCreated(
            _trader,
            _evalAccountId,
            _params.initialEquity,
            _params.initialEquity,
            _params.dailyDrawdownLimit,
            _params.maxDrawdownLimit,
            _params.profitTarget,
            _params.assessmentFee
        );
        emit EvalStatusUpdated(_trader, _evalAccountId, EvalStatus.ACTIVE);
    }

    /// @notice Creates a funded account with a new ID, inheriting values from the eval account
    /// @param _trader Address of the trader
    /// @param _fundedAccountId ID for the new funded trading account
    /// @param _initialEquity Initial equity inherited from the eval account
    /// @param _dailyDrawdownLimit Daily drawdown limit inherited from the eval account
    /// @param _maxDrawdownLimit Max drawdown limit inherited from the eval account
    function _createFundedAccount(
        address _trader,
        bytes32 _fundedAccountId,
        uint256 _initialEquity,
        uint256 _dailyDrawdownLimit,
        uint256 _maxDrawdownLimit
    ) internal {
        if (_fundedAccountId == bytes32(0)) revert ZeroId();
        if (idOwner[_fundedAccountId] != address(0)) revert IdAlreadyUsed();

        idOwner[_fundedAccountId] = _trader;

        FundedAccount storage account = fundedAccounts[_trader][_fundedAccountId];
        account.fundedStatus = FundedStatus.AWAITING_SIGNATURE;
        account.initialEquity = _initialEquity;
        account.equity = _initialEquity;
        account.startOfDayBalance = _initialEquity;
        account.dailyDrawdownLimit = _dailyDrawdownLimit;
        account.maxDrawdownLimit = _maxDrawdownLimit;

        emit FundedAccountCreated(
            _trader, _fundedAccountId, _initialEquity, _initialEquity, _dailyDrawdownLimit, _maxDrawdownLimit
        );
        emit FundedStatusUpdated(_trader, _fundedAccountId, FundedStatus.AWAITING_SIGNATURE);
    }
}
