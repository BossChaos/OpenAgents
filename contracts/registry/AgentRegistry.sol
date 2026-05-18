// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AgentRegistry
/// @notice Agent registry with frontrunning protection
/// FIX #169: Commit-reveal for agent registration
contract AgentRegistry is Ownable {
    struct Agent {
        address owner;
        string name;
        bool active;
        bytes32 commitment;
        uint256 deadline;
    }

    mapping(address => Agent) public agents;
    address[] public agentList;

    event AgentCommitted(address agent, bytes32 commitment);
    event AgentRegistered(address agent, string name);

    constructor() Ownable(msg.sender) {}

    /// @notice Commit to register an agent (prevents frontrunning)
    function commitRegistration(bytes32 commitment, uint256 deadline) external {
        require(deadline > block.timestamp, "Past deadline");
        agents[msg.sender].commitment = commitment;
        agents[msg.sender].deadline = deadline;
        agents[msg.sender].owner = msg.sender;
        emit AgentCommitted(msg.sender, commitment);
    }

    /// @notice Reveal and register agent
    function revealRegistration(string calldata name, uint256 nonce) external {
        Agent storage agent = agents[msg.sender];
        require(block.timestamp <= agent.deadline, "Expired");
        require(!agent.active, "Already active");

        bytes32 expected = keccak256(abi.encodePacked(name, nonce, msg.sender));
        require(expected == agent.commitment, "Commitment mismatch");

        agent.name = name;
        agent.active = true;
        agentList.push(msg.sender);
        emit AgentRegistered(msg.sender, name);
    }

    function getAgentCount() external view returns (uint256) {
        return agentList.length;
    }

    /// @notice FIX #169: Check if agent exists before operations
    function isAgent(address addr) external view returns (bool) {
        return agents[addr].active;
    }
}
