// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ApexVault
 * @dev A secure, upgradable, and pausable vault for ETH and ERC20 tokens with emergency withdrawal.
 * @author Grok
 */
contract ApexVault is
    Initializable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    // Total assets under management
    uint256 public totalAssets;
    
    // User => balance
    mapping(address => uint256) public balanceOf;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _strategist) external initializer {
        __Pausable_init();
        __ReentrancyGuard_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(STRATEGIST_ROLE, _strategist);
        _grantRole(STRATEGIST_ROLE, _admin); // admin can also act as strategist
    }

    // ============ CORE FUNCTIONS ============

    /**
     * @dev Deposit ETH or any ERC20 into the Apex Vault
     * For ETH: send value with the call
     * For ERC20: approve vault first, then call with token address and amount
     */
    function deposit(address token, uint256 amount) external payable whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be > 0");

        if (token == address(0)) {
            // Native ETH deposit
            require(msg.value == amount, "ETH amount mismatch");
            balanceOf[msg.sender] += amount;
            totalAssets += amount;
            emit Deposited(msg.sender, amount);
        } else {
            // ERC20 deposit
            require(msg.value == 0, "Don't send ETH with ERC20");
            uint256 before = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            uint256 after_ = IERC20(token).balanceOf(address(this));
            uint256 received = after_ - before;
            balanceOf[msg.sender] += received;
            totalAssets += received;
            emit Deposited(msg.sender, received);
        }
    }

    /**
     * @dev Withdraw your share of assets (supports ETH or ERC20)
     */
    function withdraw(address token, uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be > 0");
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");

        balanceOf[msg.sender] -= amount;
        totalAssets -= amount;

        if (token == address(0)) {
            // Withdraw ETH
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // Withdraw ERC20
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @dev Emergency pause (only admin)
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause (only admin)
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Emergency withdraw everything (only admin + when paused)
     */
    function emergencyWithdraw(address token) external onlyRole(DEFAULT_ADMIN_ROLE) whenPaused {
        uint256 amount;
        if (token == address(0)) {
            amount = address(this).balance;
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            amount = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(msg.sender, amount);
        }
        emit EmergencyWithdrawn(msg.sender, amount);
    }

    // Allow contract to receive ETH
    receive() external payable {}
}
