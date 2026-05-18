// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title GovernorAlpha
/// @notice Governance with proposal cancellation
/// FIX #40: Add cancelProposal for owner
contract GovernorAlpha is Ownable {
    struct Proposal {
        uint256 id;
        address proposer;
        bool executed;
        bool cancelled;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    event ProposalCancelled(uint256 id, address cancelledBy);

    constructor() Ownable(msg.sender) {}

    function propose() external returns (uint256) {
        uint256 id = ++proposalCount;
        proposals[id] = Proposal({
            id: id,
            proposer: msg.sender,
            executed: false,
            cancelled: false
        });
        return id;
    }

    /// @notice Cancel a proposal (owner only)
    /// FIX #40: Allow cancellation before execution
    function cancelProposal(uint256 proposalId) external onlyOwner {
        require(!proposals[proposalId].executed, "Already executed");
        require(!proposals[proposalId].cancelled, "Already cancelled");
        proposals[proposalId].cancelled = true;
        emit ProposalCancelled(proposalId, msg.sender);
    }

    function execute(uint256 proposalId) external {
        require(!proposals[proposalId].cancelled, "Cancelled");
        require(!proposals[proposalId].executed, "Already executed");
        proposals[proposalId].executed = true;
    }
}
