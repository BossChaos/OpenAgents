// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AgentRegistry
/// @notice Registry for AI agent metadata and reputation tracking
/// FIX #189: Add commit-reveal to prevent frontrunning
contract AgentRegistry is Ownable {
    struct Agent {
        string name;
        uint256 reputation;
        address owner;
    }

    mapping(uint256 => Agent) public agents;
    uint256 public nextAgentId;
    mapping(address => bool) public registered;

    // FIX #189: Commit-reveal pattern to prevent frontrunning
    mapping(bytes32 => bool) public commitments;

    event AgentRegistered(uint256 id, string name, address owner);
    event ReputationUpdated(uint256 id, uint256 newReputation);
    event Committed(bytes32 commitment);

    constructor() Ownable(msg.sender) {}

    /// @notice Commit to registering an agent (commit phase)
    function commitAgent(bytes32 commitment) external {
        require(!commitments[commitment], "Already committed");
        commitments[commitment] = true;
        emit Committed(commitment);
    }

    /// @notice Reveal agent registration
    function revealAgent(
        string calldata name,
        bytes32 salt
    ) external {
        require(!registered[msg.sender], "Already registered");
        // Verify commitment: keccak256(abi.encodePacked(name, msg.sender, salt))
        bytes32 expected = keccak256(abi.encodePacked(name, msg.sender, salt));
        require(commitments[expected], "Invalid commitment");

        uint256 id = nextAgentId++;
        agents[id] = Agent({
            name: name,
            reputation: 0,
            owner: msg.sender
        });
        registered[msg.sender] = true;

        emit AgentRegistered(id, name, msg.sender);
    }

    function updateReputation(uint256 agentId, uint256 newReputation) external {
        require(agents[agentId].owner == msg.sender, "Not owner");
        agents[agentId].reputation = newReputation;
        emit ReputationUpdated(agentId, newReputation);
    }

    function getAgent(uint256 agentId) external view returns (string memory, uint256, address) {
        Agent memory agent = agents[agentId];
        return (agent.name, agent.reputation, agent.owner);
    }
}
