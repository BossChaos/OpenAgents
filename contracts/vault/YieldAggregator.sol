// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title YieldAggregator
/// @notice Yield aggregator with donation attack protection
/// FIX #95: minShares parameter, zero-address check
contract YieldAggregator is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public token;
    uint256 public totalShares;
    uint256 public totalReserves;
    uint256 public constant VIRTUAL_SHARES = 1000;
    uint256 public constant VIRTUAL_RESERVES = 1000;

    mapping(address => uint256) public userShares;

    event Deposited(address user, uint256 amount, uint256 shares);
    event Withdrawn(address user, uint256 amount, uint256 shares);

    constructor(address _token) {
        require(_token != address(0), "Zero token");
        token = IERC20(_token);
    }

    /// @notice Deposit with minShares protection against donation attack
    /// FIX #95: minShares parameter + zero-address strategy
    function deposit(uint256 amount, uint256 minShares) external nonReentrant {
        require(amount > 0, "Zero amount");
        require(msg.sender != address(0), "Zero address");

        uint256 shares;
        if (totalShares == 0) {
            shares = (amount * totalReserves) / (totalReserves + VIRTUAL_RESERVES);
            totalShares += VIRTUAL_SHARES;
        } else {
            shares = (amount * totalShares) / totalReserves;
        }

        // FIX: Slippage protection
        require(shares >= minShares, "Slippage: insufficient shares");

        token.safeTransferFrom(msg.sender, address(this), amount);
        totalShares += shares;
        totalReserves += amount;
        userShares[msg.sender] += shares;
        emit Deposited(msg.sender, amount, shares);
    }

    /// @notice Withdraw with internal accounting
    function withdraw(uint256 shareAmount) external nonReentrant {
        require(shareAmount > 0, "Zero shares");
        require(userShares[msg.sender] >= shareAmount, "Insufficient shares");

        uint256 amount = (shareAmount * totalReserves) / totalShares;
        // FIX: Update internal accounting BEFORE transfer
        userShares[msg.sender] -= shareAmount;
        totalShares -= shareAmount;
        totalReserves -= amount;

        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, shareAmount);
    }

    function getUserReserves(address user) external view returns (uint256) {
        if (totalShares == 0) return 0;
        return (userShares[user] * totalReserves) / totalShares;
    }

    function pricePerShare() external view returns (uint256) {
        if (totalShares == 0) return 1e18;
        return (totalReserves * 1e18) / totalShares;
    }
}
