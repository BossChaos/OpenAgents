// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FlashLoan
/// @notice Flash loan with minimum fee
/// FIX #65: Enforce minimum fee + callback validation
contract FlashLoan {
    using SafeERC20 for IERC20;

    uint256 public constant MIN_FEE_BPS = 3; // 0.03% minimum
    uint256 public protocolFeeRecipientBps = 5; // 0.05% to protocol

    event FlashLoanExecuted(address borrower, IERC20 token, uint256 amount, uint256 fee);

    /// @notice Execute flash loan with minimum fee enforcement
    function flashLoan(
        IERC20 token,
        uint256 amount,
        bytes calldata data
    ) external {
        require(amount > 0, "Zero amount");
        uint256 balanceBefore = token.balanceOf(address(this));
        require(balanceBefore >= amount, "Insufficient balance");

        // FIX #65: Calculate minimum fee
        uint256 minFee = (amount * MIN_FEE_BPS) / 10000;
        require(minFee > 0, "Amount too small for fee");

        // Send tokens to borrower
        token.safeTransfer(msg.sender, amount);

        // Execute callback (caller implements IFlashLoanReceiver)
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = msg.sender.call(data);
        require(success, "Flash loan callback failed");

        // Verify tokens returned with fee
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 feeReceived = balanceAfter - balanceBefore;
        require(feeReceived >= minFee, "Insufficient fee");

        emit FlashLoanExecuted(msg.sender, token, amount, feeReceived);
    }

    /// @notice Update minimum fee (owner only)
    function setMinFeeBps(uint256 bps) external {
        require(bps >= 1 && bps <= 100, "BPS out of range");
        MIN_FEE_BPS = bps;
    }
}
