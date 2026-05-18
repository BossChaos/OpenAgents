// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AgentRegistry
/// @notice Agent registry with batch operations
/// FIX #145: Add batch registration and deactivation
contract AgentRegistry is Ownable {
    struct Agent {
        address owner;
        string name;
        bool active;
        uint256 registeredAt;
    }

    mapping(address => Agent) public agents;
    address[] public agentList;

    event AgentRegistered(address indexed agent, string name);
    event AgentDeactivated(address indexed agent);
    event BatchRegistered(uint256 count);

    constructor() Ownable(msg.sender) {}

    function register(string calldata name) external {
        require(!agents[msg.sender].active, "Already registered");
        agents[msg.sender] = Agent({
            owner: msg.sender,
            name: name,
            active: true,
            registeredAt: block.timestamp
        });
        agentList.push(msg.sender);
        emit AgentRegistered(msg.sender, name);
    }

    /// @notice FIX #145: Batch register multiple agents
    function batchRegister(address[] calldata addrs, string[] calldata names) external onlyOwner {
        require(addrs.length == names.length, "Length mismatch");
        require(addrs.length <= 100, "Batch too large");
        for (uint256 i = 0; i < addrs.length; i++) {
            require(!agents[addrs[i]].active, "Already active");
            agents[addrs[i]] = Agent({
                owner: addrs[i],
                name: names[i],
                active: true,
                registeredAt: block.timestamp
            });
            agentList.push(addrs[i]);
        }
        emit BatchRegistered(addrs.length);
    }

    /// @notice FIX #145: Batch deactivate
    function batchDeactivate(address[] calldata addrs) external onlyOwner {
        require(addrs.length <= 100, "Batch too large");
        for (uint256 i = 0; i < addrs.length; i++) {
            if (agents[addrs[i]].active) {
                agents[addrs[i]].active = false;
                emit AgentDeactivated(addrs[i]);
            }
        }
    }

    function deactivate() external {
        require(agents[msg.sender].active, "Not active");
        agents[msg.sender].active = false;
        emit AgentDeactivated(msg.sender);
    }

    function isActive(address addr) external view returns (bool) {
        return agents[addr].active;
    }

    function getAgentCount() external view returns (uint256) {
        return agentList.length;
    }
}
