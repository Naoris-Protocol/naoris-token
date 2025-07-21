// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

// Core upgradeable contracts

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title NaorisToken - Upgradeable ERC20 token with governance, pausing, transferring, and capped supply
/// @dev Inherits from OpenZeppelin upgradeable contracts, using UUPS upgrade pattern
contract NaorisToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC20CappedUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    /// @notice Role identifier for accounts allowed to pause/unpause the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @notice Total supply of tokens
    uint256 constant TOTAL_SUPPLY = 4_000_000_000;

    /// @notice Constructor disables initializers to prevent misuse
    constructor() {
        _disableInitializers();
    }

    /// @notice Authorizes a contract upgrade, only callable by the owner
    /// @param newImplementation The address of the new logic contract to upgrade to
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(DEFAULT_ADMIN_ROLE)
        override
    {}

    /// @notice Initializes the token contract with given parameters
    /// @dev Called only once. Sets initial state and grants roles to the `initialOwner`
    /// @param initialOwner The address to be granted admin, minter, and pauser roles
    /// @param tokenName The name of the token
    /// @param tokenSymbol The symbol of the token
    function initialize(
        address initialOwner,
        string memory tokenName,
        string memory tokenSymbol
    ) public initializer {
        require(initialOwner != address(0), "Invalid owner");

        __ERC20_init(tokenName, tokenSymbol);
        __ERC20Permit_init(tokenName);
        __ERC20Capped_init(TOTAL_SUPPLY * 10 ** decimals()); 
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _mint(initialOwner, TOTAL_SUPPLY * 10 ** decimals()); 
        _grantRole(PAUSER_ROLE, initialOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _pause();
    }

    /// @notice Pauses all token transfers and minting/burning functions
    /// @dev Can only be called by an address with the PAUSER_ROLE
    function pause() external onlyRole(PAUSER_ROLE) whenNotPaused {
        _pause();
    }

    /// @notice Unpauses the contract, enabling token transfers and minting/burning
    /// @dev Can only be called by an address with the PAUSER_ROLE
    function unpause() external onlyRole(PAUSER_ROLE) whenPaused {
        _unpause();
    }

    /// @notice Transfers tokens to a specified address
    /// @dev Token transfers are disabled when paused.
    /// @param to The address to receive the tokens
    /// @param amount The amount of tokens to transfer
    /// @return success A boolean indicating whether the transfer was successful
    function transfer(address to, uint256 amount)
        public
        whenNotPaused
        override
        returns (bool)
    {
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        } 
        address owner = _msgSender();     
        _transfer(owner, to, amount);
        return true;
    }

    /// @notice Transfers tokens from one address to another using allowance mechanism
    /// @dev Deducts from the caller’s allowance and performs the transfer. Fails if contract is paused.
    /// @param from The address from which tokens are transferred
    /// @param to The recipient address
    /// @param value The number of tokens to transfer
    /// @return success A boolean indicating whether the transfer was successful
    function transferFrom(address from, address to, uint256 value)
        public
        whenNotPaused
        override
        returns (bool)
    {   
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /// @notice Approves a spender to transfer up to a certain number of tokens on behalf of the caller
    /// @dev Emits an Approval event. Will fail if contract is paused.
    /// @param spender The address allowed to spend tokens
    /// @param value The maximum amount the spender is allowed to transfer
    /// @return success A boolean indicating whether the approval was successful
    function approve(address spender, uint256 value)
        public
        whenNotPaused
        override
        returns (bool)
    {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /// @notice Approves a spender via signature (EIP-2612) while contract is not paused
    /// @dev Applies whenNotPaused to the standard ERC20Permit permit function
    /// @param owner The address giving the approval
    /// @param spender The address allowed to spend the tokens
    /// @param value The maximum amount approved
    /// @param deadline Time by which the signature must be used
    /// @param v Signature param
    /// @param r Signature param
    /// @param s Signature param
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public whenNotPaused override {
        super.permit(owner, spender, value, deadline, v, r, s);
    }
    
    /// @notice Internal function to update token balances and track votes
    /// @dev Overridden to combine behavior from multiple parent contracts
    /// @param from Sender address
    /// @param to Recipient address
    /// @param value Amount transferred
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20CappedUpgradeable)
    {
        super._update(from, to, value);
    }

}
