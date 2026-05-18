// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title GovernorAlpha
/// @notice Governance with execution validation
/// FIX #107: validate execute proposal
contract GovernorAlpha {
    struct Proposal {
        uint256 id;
        address proposer;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startBlock;
        uint256 endBlock;
        bool executed;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    uint256 public constant VOTING_PERIOD = 5760;
    uint256 public constant QUORUM = 100_000e18;

    event ProposalCreated(uint256 id);
    event Executed(uint256 id);

    function propose() external returns (uint256) {
        uint256 id = ++proposalCount;
        proposals[id] = Proposal({
            id: id,
            proposer: msg.sender,
            forVotes: 0,
            againstVotes: 0,
            startBlock: block.number,
            endBlock: block.number + VOTING_PERIOD,
            executed: false
        });
        emit ProposalCreated(id);
        return id;
    }

    /// @notice FIX #107: Validate execution conditions
    function execute(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(block.number > p.endBlock, "Not ended");
        require(!p.executed, "Already executed");
        require(p.forVotes > p.againstVotes, "Rejected");
        require(p.forVotes >= QUORUM, "No quorum");

        p.executed = true;
        emit Executed(proposalId);
    }

    function getQuorum() external pure returns (uint256) {
        return QUORUM;
    }
}
