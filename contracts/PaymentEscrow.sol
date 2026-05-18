// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title PaymentEscrow
/// @notice Escrow with dispute resolution and auto-refund
/// FIX #75: Add dispute function, owner resolveDispute, 30-day timeout
contract PaymentEscrow is Ownable {
    using SafeERC20 for IERC20;

    struct Escrow {
        address buyer;
        address seller;
        IERC20 token;
        uint256 amount;
        bool disputed;
        bool resolved;
        uint256 createdAt;
    }

    mapping(uint256 => Escrow) public escrows;
    uint256 public nextEscrowId;

    uint256 public constant DISPUTE_TIMEOUT = 30 days;

    event EscrowCreated(uint256 id, address buyer, address seller, uint256 amount);
    event EscrowReleased(uint256 id);
    event EscrowDisputed(uint256 id, address disputer);
    event DisputeResolved(uint256 id, uint256 buyerRefund, uint256 sellerPayout);
    event EscrowRefunded(uint256 id, address refundedTo, uint256 amount);

    constructor() Ownable(msg.sender) {}

    function createEscrow(
        address seller,
        IERC20 token,
        uint256 amount
    ) external returns (uint256) {
        require(seller != address(0), "Zero seller");
        require(amount > 0, "Zero amount");

        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 id = nextEscrowId++;
        escrows[id] = Escrow({
            buyer: msg.sender,
            seller: seller,
            token: token,
            amount: amount,
            disputed: false,
            resolved: false,
            createdAt: block.timestamp
        });

        emit EscrowCreated(id, msg.sender, seller, amount);
        return id;
    }

    function release(uint256 id) external {
        Escrow storage escrow = escrows[id];
        require(escrow.buyer == msg.sender, "Not buyer");
        require(!escrow.disputed && !escrow.resolved, "Invalid state");

        escrow.resolved = true;
        escrow.token.safeTransfer(escrow.seller, escrow.amount);
        emit EscrowReleased(id);
    }

    // FIX #75: Dispute function for either party
    function dispute(uint256 id) external {
        Escrow storage escrow = escrows[id];
        require(msg.sender == escrow.buyer || msg.sender == escrow.seller, "Not a party");
        require(!escrow.disputed && !escrow.resolved, "Already resolved");

        escrow.disputed = true;
        emit EscrowDisputed(id, msg.sender);
    }

    // FIX: Owner resolves dispute with custom split
    function resolveDispute(
        uint256 id,
        uint256 buyerRefundAmount,
        uint256 sellerPayoutAmount
    ) external onlyOwner {
        Escrow storage escrow = escrows[id];
        require(escrow.disputed && !escrow.resolved, "Not disputed");
        require(
            buyerRefundAmount + sellerPayoutAmount <= escrow.amount,
            "Over-refund"
        );

        escrow.resolved = true;

        if (buyerRefundAmount > 0) {
            escrow.token.safeTransfer(escrow.buyer, buyerRefundAmount);
        }
        if (sellerPayoutAmount > 0) {
            escrow.token.safeTransfer(escrow.seller, sellerPayoutAmount);
        }

        emit DisputeResolved(id, buyerRefundAmount, sellerPayoutAmount);
    }

    // FIX: Auto-refund after 30-day timeout
    function refundExpired(uint256 id) external {
        Escrow storage escrow = escrows[id];
        require(!escrow.resolved, "Already resolved");
        require(
            block.timestamp > escrow.createdAt + DISPUTE_TIMEOUT,
            "Not expired"
        );

        uint256 amount = escrow.amount;
        escrow.resolved = true;
        escrow.amount = 0;

        escrow.token.safeTransfer(escrow.buyer, amount);
        emit EscrowRefunded(id, escrow.buyer, amount);
    }
}
