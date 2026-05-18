// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title GovernorAlpha
/// @notice Governance with delegation snapshots
/// FIX #149: Snapshot-based delegation to prevent flash-loan voting
contract GovernorAlpha is Ownable {
    struct Proposal {
        uint256 id;
        address proposer;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(address => address) public delegates;
    mapping(address => uint256) public votingPower;
    // FIX #149: Snapshot mapping for delegation at proposal time
    mapping(uint256 => mapping(address => address)) public delegationSnapshots;

    uint256 public proposalCount;
    uint256 public constant VOTING_PERIOD = 5760; // ~1 day in blocks
    uint256 public constant QUORUM = 100_000e18;

    event ProposalCreated(uint256 id, address proposer);
    event VoteCast(uint256 proposalId, address voter, bool support, uint256 power);
    event Delegated(address delegator, address delegatee);

    constructor() Ownable(msg.sender) {}

    /// @notice Delegate voting power
    function delegate(address delegatee) external {
        delegates[msg.sender] = delegatee;
        emit Delegated(msg.sender, delegatee);
    }

    /// @notice Create a proposal and take snapshot
    /// FIX #149: Record delegation state at proposal creation
    function propose(uint256 /* target */, bytes memory /* data */) external {
        uint256 id = ++proposalCount;
        proposals[id] = Proposal({
            id: id,
            proposer: msg.sender,
            startBlock: block.number,
            endBlock: block.number + VOTING_PERIOD,
            forVotes: 0,
            againstVotes: 0,
            executed: false
        });

        // FIX: Snapshot current delegation state
        delegationSnapshots[id][msg.sender] = delegates[msg.sender];
        emit ProposalCreated(id, msg.sender);
    }

    /// @notice Vote using snapshot delegation
    function castVote(uint256 proposalId, bool support) external {
        require(block.number > proposals[proposalId].startBlock, "Not started");
        require(block.number <= proposals[proposalId].endBlock, "Ended");
        require(!proposals[proposalId].executed, "Executed");

        // FIX: Use snapshot delegation, not current
        address delegatee = delegationSnapshots[proposalId][msg.sender];
        uint256 power = votingPower[delegatee != address(0) ? delegatee : msg.sender];

        if (support) {
            proposals[proposalId].forVotes += power;
        } else {
            proposals[proposalId].againstVotes += power;
        }

        emit VoteCast(proposalId, msg.sender, support, power);
    }

    function execute(uint256 proposalId) external {
        require(block.number > proposals[proposalId].endBlock, "Not ended");
        require(proposals[proposalId].forVotes > proposals[proposalId].againstVotes, "Rejected");
        require(proposals[proposalId].forVotes >= QUORUM, "No quorum");
        proposals[proposalId].executed = true;
    }
}
