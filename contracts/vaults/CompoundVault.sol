// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title CompoundVault
/// @notice Yield vault with first-depositor attack protection
/// FIX #69: Initialize shares on first deposit to prevent inflation attack
contract CompoundVault {
    using SafeERC20 for IERC20;

    IERC20 public immutable want;
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    uint256 private constant INITIAL_SHARES = 1e18;

    event Deposit(address user, uint256 wantAmt, uint256 shares);
    event Withdraw(address user, uint256 wantAmt, uint256 shares);

    constructor(address _want) {
        require(_want != address(0), "Zero want");
        want = IERC20(_want);
    }

    /// @notice FIX #69: Use virtual shares for first depositor
    function deposit(uint256 amount) external {
        require(amount > 0, "Zero amount");
        uint256 sharesToMint;
        if (totalShares == 0) {
            // First depositor: use INITIAL_SHARES as buffer
            sharesToMint = amount - (amount / INITIAL_SHARES);
        } else {
            sharesToMint = (amount * totalShares) / _freeWant();
        }
        shares[msg.sender] += sharesToMint;
        totalShares += sharesToMint;
        want.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount, sharesToMint);
    }

    /// @notice Withdraw with proportional shares
    function withdraw(uint256 sharesToBurn) external {
        require(sharesToBurn > 0, "Zero shares");
        require(shares[msg.sender] >= sharesToBurn, "Insufficient shares");

        uint256 wantAmt = (sharesToBurn * _freeWant()) / totalShares;
        shares[msg.sender] -= sharesToBurn;
        totalShares -= sharesToBurn;
        want.safeTransfer(msg.sender, wantAmt);
        emit Withdraw(msg.sender, wantAmt, sharesToBurn);
    }

    function _freeWant() internal view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function getPricePerShare() external view returns (uint256) {
        if (totalShares == 0) return 0;
        return (_freeWant() * 1e18) / totalShares;
    }
}
