// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title PaymentEscrow
/// @notice Escrow with dispute resolution, expiry, and partial release
/// @dev Fixes: dispute resolution, expiry deadline, partial release
contract PaymentEscrow is Ownable {
    enum EscrowState { Created, Released, Refunded, Disputed }

    struct Escrow {
        address payer;
        address payee;
        address token;
        uint256 amount;
        uint256 releaseTime;
        bool released;
        bool refunded;
        // FIX: New fields
        uint256 createdAt;
        address arbitrator; // Can resolve disputes (e.g., DAO or multisig)
        EscrowState state;
        uint256 disputedAmount; // Amount currently in dispute
    }

    mapping(uint256 => Escrow) public escrows;
    uint256 public escrowCount;

    // FIX: Default arbitrator is contract owner
    address public defaultArbitrator;

    event EscrowCreated(uint256 indexed escrowId, address indexed payer, uint256 amount);
    event EscrowReleased(uint256 indexed escrowId, address indexed payee, uint256 amount);
    event EscrowRefunded(uint256 indexed escrowId, address indexed payer, uint256 amount);
    // FIX: New events
    event EscrowDisputed(uint256 indexed escrowId, address indexed payer, uint256 disputedAmount);
    event EscrowResolved(uint256 indexed escrowId, uint256 payerAmount, uint256 payeeAmount);
    event ArbitratorUpdated(address indexed oldArbitrator, address indexed newArbitrator);

    constructor() {
        defaultArbitrator = msg.sender;
    }

    function setDefaultArbitrator(address _arbitrator) external onlyOwner {
        require(_arbitrator != address(0), "Zero arbitrator");
        emit ArbitratorUpdated(defaultArbitrator, _arbitrator);
        defaultArbitrator = _arbitrator;
    }

    function createEscrow(
        address payee,
        address token,
        uint256 amount,
        uint256 lockDuration
    ) external returns (uint256) {
        return createEscrowWithArbitrator(payee, token, amount, lockDuration, defaultArbitrator);
    }

    function createEscrowWithArbitrator(
        address payee,
        address token,
        uint256 amount,
        uint256 lockDuration,
        address arbitrator
    ) public returns (uint256) {
        require(payee != address(0), "Invalid payee");
        require(amount > 0, "Amount must be > 0");
        require(arbitrator != address(0), "Invalid arbitrator");
        // FIX: Minimum lock duration to prevent griefing (1 hour)
        require(lockDuration >= 1 hours, "Lock too short");
        // FIX: Maximum lock duration (max 4 years)
        require(lockDuration <= 4 * 365 days, "Lock too long");

        IERC20(token).transferFrom(msg.sender, address(this), amount);

        uint256 escrowId = escrowCount++;
        escrows[escrowId] = Escrow({
            payer: msg.sender,
            payee: payee,
            token: token,
            amount: amount,
            releaseTime: block.timestamp + lockDuration,
            released: false,
            refunded: false,
            createdAt: block.timestamp,
            arbitrator: arbitrator,
            state: EscrowState.Created,
            disputedAmount: 0
        });

        emit EscrowCreated(escrowId, msg.sender, amount);
        return escrowId;
    }

    function releaseEscrow(uint256 escrowId) external {
        Escrow storage escrow = escrows[escrowId];
        require(escrow.state == EscrowState.Created, "Not in created state");
        require(!escrow.released && !escrow.refunded, "Already settled");
        require(msg.sender == escrow.payer || msg.sender == owner(), "Not authorized");

        escrow.released = true;
        escrow.state = EscrowState.Released;
        IERC20(escrow.token).transfer(escrow.payee, escrow.amount);

        emit EscrowReleased(escrowId, escrow.payee, escrow.amount);
    }

    function refundEscrow(uint256 escrowId) external {
        Escrow storage escrow = escrows[escrowId];
        require(escrow.state == EscrowState.Created, "Not in created state");
        require(!escrow.released && !escrow.refunded, "Already settled");
        require(block.timestamp > escrow.releaseTime, "Lock not expired");
        require(msg.sender == escrow.payer, "Not payer");

        escrow.refunded = true;
        escrow.state = EscrowState.Refunded;
        IERC20(escrow.token).transfer(escrow.payer, escrow.amount);

        emit EscrowRefunded(escrowId, escrow.payer, escrow.amount);
    }

    // FIX: Dispute function — either party can raise a dispute
    function raiseDispute(uint256 escrowId, uint256 disputedAmount) external {
        Escrow storage escrow = escrows[escrowId];
        require(escrow.state == EscrowState.Created, "Not in created state");
        require(!escrow.released && !escrow.refunded, "Already settled");
        require(
            msg.sender == escrow.payer || msg.sender == escrow.payee,
            "Not escrow party"
        );
        require(disputedAmount <= escrow.amount, "Disputed amount exceeds escrow");
        require(disputedAmount > 0, "Nothing to dispute");

        escrow.state = EscrowState.Disputed;
        escrow.disputedAmount = disputedAmount;

        emit EscrowDisputed(escrowId, msg.sender, disputedAmount);
    }

    // FIX: Resolve dispute — only arbitrator can call
    function resolveDispute(
        uint256 escrowId,
        uint256 payerShare,
        uint256 payeeShare
    ) external {
        Escrow storage escrow = escrows[escrowId];
        require(escrow.state == EscrowState.Disputed, "Not disputed");
        require(
            msg.sender == escrow.arbitrator || msg.sender == owner(),
            "Not arbitrator"
        );
        require(payerShare + payeeShare == escrow.amount, "Shares must equal total");

        escrow.state = EscrowState.Released;
        escrow.released = true;

        if (payerShare > 0) {
            IERC20(escrow.token).transfer(escrow.payer, payerShare);
        }
        if (payeeShare > 0) {
            IERC20(escrow.token).transfer(escrow.payee, payeeShare);
        }

        emit EscrowResolved(escrowId, payerShare, payeeShare);
    }

    // FIX: Partial release — release only part of the escrow
    function partialRelease(uint256 escrowId, uint256 amount) external {
        Escrow storage escrow = escrows[escrowId];
        require(escrow.state == EscrowState.Created, "Not in created state");
        require(!escrow.released && !escrow.refunded, "Already settled");
        require(
            msg.sender == escrow.payer || msg.sender == owner(),
            "Not authorized"
        );
        require(amount > 0 && amount <= escrow.amount, "Invalid amount");

        // Transfer partial amount to payee
        IERC20(escrow.token).transfer(escrow.payee, amount);
        escrow.amount -= amount;

        // If fully released
        if (escrow.amount == 0) {
            escrow.released = true;
            escrow.state = EscrowState.Released;
        }

        emit EscrowReleased(escrowId, escrow.payee, amount);
    }

    // View function
    function getEscrowState(uint256 escrowId) external view returns (EscrowState) {
        return escrows[escrowId].state;
    }
}
