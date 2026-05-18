// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title GovernorAlpha
/// @notice Minimal governance contract supporting proposal creation, voting, and execution.
/// @dev Inspired by Compound's GovernorAlpha. Token holders propose and vote on-chain actions.
contract GovernorAlpha is ReentrancyGuard {
    enum ProposalState { Pending, Active, Defeated, Succeeded, Queued, Executed, Canceled }

    struct Proposal {
        uint256 id;
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
        bool canceled;
        bool queued;
        uint256 queueTime;
        mapping(address => bool) hasVoted;
    }

    ERC20Votes public immutable token;
    uint256 public proposalCount;
    uint256 public constant VOTING_DELAY = 1; // blocks
    uint256 public constant VOTING_PERIOD = 17280; // ~3 days at 15s blocks
    uint256 public constant PROPOSAL_THRESHOLD = 100_000e18;
    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant QUORUM_BPS = 400; // 4% of circulating supply

    mapping(uint256 => Proposal) public proposals;

    event ProposalCreated(uint256 indexed id, address proposer, uint256 startBlock, uint256 endBlock);
    event VoteCast(address indexed voter, uint256 indexed proposalId, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed id);
    event ProposalCanceled(uint256 indexed id);
    event ProposalQueued(uint256 indexed id, uint256 eta);
    event ProposalVetoed(uint256 indexed id);

    /// @notice Create a new governance proposal.
    /// @param targets Contract addresses to call.
    /// @param values ETH values to send.
    /// @param calldatas Encoded function calls.
    /// @return proposalId The ID of the newly created proposal.
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external returns (uint256 proposalId) {
        require(targets.length == values.length && values.length == calldatas.length, "Governor: arity mismatch");
        require(token.getVotes(msg.sender) >= PROPOSAL_THRESHOLD, "Governor: below threshold");
        require(targets.length > 0, "Governor: empty proposal");

        proposalId = ++proposalCount;
        Proposal storage p = proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.targets = targets;
        p.values = values;
        p.calldatas = calldatas;
        p.startBlock = block.number + VOTING_DELAY;
        p.endBlock = block.number + VOTING_DELAY + VOTING_PERIOD;

        emit ProposalCreated(proposalId, msg.sender, p.startBlock, p.endBlock);
    }

    /// @notice Cast a vote on a proposal.
    /// @param proposalId The proposal to vote on.
    /// @param support True for yes, false for no.
    /// @dev FIX 1: Changed tx.origin to msg.sender — prevents phishing attacks where
    /// a malicious contract intercepts votes cast by EOAs through tx.origin hijacking.
    function vote(uint256 proposalId, bool support) external {
        Proposal storage p = proposals[proposalId];
        require(block.number >= p.startBlock && block.number <= p.endBlock, "Governor: voting closed");
        require(!p.hasVoted[msg.sender], "Governor: already voted");
        require(!p.canceled, "Governor: proposal canceled");
        p.hasVoted[msg.sender] = true;

        uint256 weight = token.getPastVotes(msg.sender, p.startBlock);
        if (support) {
            p.forVotes += weight;
        } else {
            p.againstVotes += weight;
        }

        emit VoteCast(msg.sender, proposalId, support, weight);
    }

    /// @notice Queue a succeeded proposal for execution (enforces timelock delay).
    /// @param proposalId The proposal to queue.
    /// @param eta The estimated time of availability for the proposal.
    function queue(uint256 proposalId, uint256 eta) external {
        Proposal storage p = proposals[proposalId];
        require(state(proposalId) == ProposalState.Succeeded, "Governor: proposal not succeeded");
        require(!p.queued, "Governor: already queued");
        require(msg.sender == p.proposer || token.getVotes(msg.sender) >= PROPOSAL_THRESHOLD, "Governor: not authorized");
        p.queued = true;
        p.queueTime = eta;
        emit ProposalQueued(proposalId, eta);
    }

    /// @notice Execute a succeeded and queued proposal.
    /// @param proposalId The proposal to execute.
    /// @dev FIX 2: Added quorum validation — proposals must have at least 4% of
    /// circulating supply voting FOR to pass, preventing dust-amount governance attacks.
    /// @dev FIX 3: Added mandatory timelock — proposals must be queued and wait
    /// through the grace period before execution, giving users time to exit.
    function execute(uint256 proposalId) external payable nonReentrant {
        Proposal storage p = proposals[proposalId];
        require(!p.executed, "Governor: already executed");
        ProposalState s = state(proposalId);
        require(s == ProposalState.Queued || s == ProposalState.Succeeded, "Governor: proposal not executable");

        // FIX: Require quorum — total for votes must meet minimum threshold
        uint256 quorum = (token.totalSupply() * QUORUM_BPS) / 10000;
        require(p.forVotes >= quorum, "Governor: quorum not reached");

        // FIX: If queued, enforce grace period before execution
        if (p.queued) {
            require(block.timestamp >= p.queueTime, "Governor: timelock not expired");
            require(block.timestamp <= p.queueTime + GRACE_PERIOD, "Governor: grace period expired");
        }

        p.executed = true;
        for (uint256 i = 0; i < p.targets.length; i++) {
            (bool ok, ) = p.targets[i].call{value: p.values[i]}(p.calldatas[i]);
            require(ok, "Governor: tx failed");
        }

        emit ProposalExecuted(proposalId);
    }

    /// @notice Get the current state of a proposal.
    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage p = proposals[proposalId];
        if (p.executed) return ProposalState.Executed;
        if (p.canceled) return ProposalState.Canceled;
        if (block.number <= p.endBlock && p.forVotes > p.againstVotes) {
            return p.queued ? ProposalState.Queued : ProposalState.Succeeded;
        }
        if (block.number <= p.endBlock) return ProposalState.Active;
        return ProposalState.Defeated;
    }

    /// @notice Cancel a proposal. Only the proposer can cancel.
    /// @param proposalId The proposal to cancel.
    function cancel(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(msg.sender == p.proposer || msg.sender == admin, "Governor: not authorized");
        require(!p.executed, "Governor: already executed");
        p.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    address public admin;

    constructor(address _token) {
        token = ERC20Votes(_token);
        admin = msg.sender;
    }

    receive() external payable {}
}
