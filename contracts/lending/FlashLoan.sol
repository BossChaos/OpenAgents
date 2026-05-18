// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title FlashLoan
/// @notice Flash loan pool with minimum fee and max loan cap
/// FIX #98: Minimum fee of 1 token, max loan 50% of pool
contract FlashLoan is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public token;
    uint256 public feeBps; // fee in basis points (e.g., 9 = 0.09%)
    uint256 public constant MAX_LOAN_PCT = 50; // 50% max of pool
    uint256 public constant MIN_FEE = 1; // minimum 1 token fee

    event FlashLoanExecuted(address borrower, uint256 amount, uint256 fee);

    constructor(address _token, uint256 _feeBps) Ownable(msg.sender) {
        token = IERC20(_token);
        feeBps = _feeBps;
    }

    /// @notice Execute a flash loan
    /// FIX #98: Cap at 50% of pool, enforce minimum fee
    function flashLoan(uint256 amount) external {
        uint256 balance = token.balanceOf(address(this));
        require(amount > 0, "Zero amount");
        // FIX: Max 50% of pool
        require(amount <= (balance * MAX_LOAN_PCT) / 100, "Exceeds max loan");

        uint256 fee = (amount * feeBps) / 10000;
        // FIX: Minimum fee of 1 token
        if (fee < MIN_FEE) fee = MIN_FEE;

        uint256 repayAmount = amount + fee;

        token.safeTransfer(msg.sender, amount);

        // Callback to borrower
        (bool success, ) = msg.sender.call(
            abi.encodeWithSignature("onFlashLoan(address,uint256)", address(token), amount)
        );
        require(success, "Flash loan callback failed");

        // Verify repayment
        uint256 afterBalance = token.balanceOf(address(this));
        require(afterBalance >= balance + fee, "Flash loan not repaid");

        emit FlashLoanExecuted(msg.sender, amount, fee);
    }

    function setFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 1000, "Fee too high"); // max 10%
        feeBps = _feeBps;
    }
}
