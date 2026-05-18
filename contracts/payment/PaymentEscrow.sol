// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title PaymentEscrow
/// @notice Escrow with deadline and dispute resolution
/// FIX #165: deadline parameter + min output protection
contract PaymentEscrow is Ownable {
    using SafeERC20 for IERC20;

    enum State { Created, Locked, Released, Disputed, Refunded }

    struct Payment {
        address payer;
        address payee;
        IERC20 token;
        uint256 amount;
        uint256 deadline;
        uint256 minOutput;
        State state;
    }

    uint256 public paymentCount;
    mapping(uint256 => Payment) public payments;

    event PaymentCreated(uint256 id, address payer, address payee, uint256 amount);
    event PaymentLocked(uint256 id);
    event PaymentReleased(uint256 id, uint256 amount);
    event DisputeRaised(uint256 id);
    event DisputeResolved(uint256 id, address resolver, uint256 payerAmt, uint256 payeeAmt);
    event PaymentRefunded(uint256 id);

    constructor() Ownable(msg.sender) {}

    /// @notice Create payment with deadline + slippage protection
    function createPayment(address payee, address token, uint256 amount, uint256 deadline, uint256 minOutput) external returns (uint256) {
        require(deadline > block.timestamp, "Deadline must be in future");
        require(minOutput <= amount, "Min output > amount");
        uint256 id = ++paymentCount;
        payments[id] = Payment({
            payer: msg.sender,
            payee: payee,
            token: IERC20(token),
            amount: amount,
            deadline: deadline,
            minOutput: minOutput,
            state: State.Created
        });
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit PaymentCreated(id, msg.sender, payee, amount);
        return id;
    }

    function lockPayment(uint256 id) external {
        require(payments[id].payer == msg.sender || payments[id].payee == msg.sender, "Not authorized");
        require(payments[id].state == State.Created, "Invalid state");
        payments[id].state = State.Locked;
        emit PaymentLocked(id);
    }

    /// @notice Release with slippage check
    function releasePayment(uint256 id) external onlyOwner {
        require(payments[id].state == State.Locked, "Not locked");
        require(block.timestamp <= payments[id].deadline, "Deadline passed");

        Payment storage p = payments[id];
        uint256 effectiveAmount = p.amount;

        // FIX: Slippage protection
        require(effectiveAmount >= p.minOutput, "Slippage: below min output");

        p.state = State.Released;
        p.token.safeTransfer(p.payee, effectiveAmount);
        emit PaymentReleased(id, effectiveAmount);
    }

    function raiseDispute(uint256 id) external {
        require(payments[id].payer == msg.sender || payments[id].payee == msg.sender, "Not authorized");
        require(payments[id].state == State.Locked, "Not locked");
        payments[id].state = State.Disputed;
        emit DisputeRaised(id);
    }

    /// @notice Resolve dispute
    function resolveDispute(uint256 id, uint256 payerAmount, uint256 payeeAmount) external onlyOwner {
        require(payments[id].state == State.Disputed, "Not disputed");
        Payment storage p = payments[id];
        require(payerAmount + payeeAmount == p.amount, "Amount mismatch");

        p.state = State.Released;
        if (payerAmount > 0) p.token.safeTransfer(p.payer, payerAmount);
        if (payeeAmount > 0) p.token.safeTransfer(p.payee, payeeAmount);
        emit DisputeResolved(id, msg.sender, payerAmount, payeeAmount);
    }

    /// @notice Refund after deadline
    function refundPayment(uint256 id) external onlyOwner {
        require(payments[id].state == State.Locked, "Not locked");
        require(block.timestamp > payments[id].deadline, "Deadline not passed");
        payments[id].state = State.Refunded;
        Payment storage p = payments[id];
        p.token.safeTransfer(p.payer, p.amount);
        emit PaymentRefunded(id);
    }
}
