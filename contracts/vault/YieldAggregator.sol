// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title YieldAggregator
/// @notice Yield aggregator with virtual shares to prevent donation attack
/// FIX #21: Use virtual shares (virtualShares/virtualReserves) model
contract YieldAggregator is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public token;
    uint256 public totalShares;
    uint256 public totalReserves;

    // FIX: Virtual shares to prevent first-deposit donation attack
    uint256 public constant VIRTUAL_SHARES = 1000;
    uint256 public constant VIRTUAL_RESERVES = 1000;

    mapping(address => uint256) public userShares;

    event Deposited(address user, uint256 amount, uint256 shares);
    event Withdrawn(address user, uint256 amount, uint256 shares);
    event YieldHarvested(uint256 reserves, uint256 shares);

    constructor(address _token) {
        token = IERC20(_token);
    }

    /// @notice Deposit tokens and receive shares
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Zero amount");

        uint256 shares;
        if (totalShares == 0) {
            // First deposit uses virtual shares as base
            shares = (amount * totalReserves) / (totalReserves + VIRTUAL_RESERVES);
            // Mint virtual shares
            totalShares += VIRTUAL_SHARES;
        } else {
            shares = (amount * totalShares) / totalReserves;
        }

        token.safeTransferFrom(msg.sender, address(this), amount);
        totalShares += shares;
        totalReserves += amount;
        userShares[msg.sender] += shares;

        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice Withdraw tokens by burning shares
    function withdraw(uint256 shareAmount) external nonReentrant {
        require(shareAmount > 0, "Zero shares");
        require(userShares[msg.sender] >= shareAmount, "Insufficient shares");

        uint256 amount = (shareAmount * totalReserves) / totalShares;
        userShares[msg.sender] -= shareAmount;
        totalShares -= shareAmount;
        totalReserves -= amount;

        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, shareAmount);
    }

    /// @notice Harvest yield and update reserves
    function harvest(uint256 yieldAmount) external {
        require(yieldAmount > 0, "Zero yield");
        totalReserves += yieldAmount;
        emit YieldHarvested(totalReserves, totalShares);
    }

    /// @notice Get user's share of reserves
    function getUserReserves(address user) external view returns (uint256) {
        if (totalShares == 0) return 0;
        return (userShares[user] * totalReserves) / totalShares;
    }

    /// @notice Get price per share
    function pricePerShare() external view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return (totalReserves * 1e18) / totalShares;
    }
}
