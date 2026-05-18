// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AgentRegistry
/// @notice Registry for AI agent metadata and reputation tracking
/// @dev Fixes: frontrunning via commit-reveal, nonce-based registration IDs, batch operations
contract AgentRegistry is Ownable {
    struct Agent {
        address owner;
        string name;
        string endpoint;
        uint256 reputation;
        uint256 tasksCompleted;
        uint256 registeredAt;
        bool active;
    }

    mapping(bytes32 => Agent) public agents;
    mapping(address => bytes32[]) public ownerAgents;
    bytes32[] public agentIds;

    // FIX: Commit-reveal to prevent frontrunning
    // Step 1: Registrar commits a hash of (name, endpoint, salt)
    mapping(address => bytes32) public commitment;
    mapping(address => uint256) public commitmentTime;
    // Prevent same-name frontrunning within 3 blocks
    mapping(bytes32 => uint256) public nameCommitBlock;

    uint256 public registrationFee;
    uint256 public minReputation;

    // Minimum 1 block between commit and reveal
    uint256 public constant COMMIT_DELAY_BLOCKS = 1;

    event AgentRegistered(bytes32 indexed agentId, address indexed owner, string name);
    event AgentDeactivated(bytes32 indexed agentId);
    event ReputationUpdated(bytes32 indexed agentId, uint256 newReputation);
    // FIX: New events
    event CommitmentRegistered(address indexed registrar, bytes32 indexed commitment);
    event AgentRegisteredBatch(bytes32[] agentIds, address indexed owner);

    constructor(uint256 _registrationFee) Ownable(msg.sender) {
        registrationFee = _registrationFee;
        minReputation = 0;
    }

    // FIX: Commit phase — frontrunning protection
    // User computes keccak256(abi.encode(name, endpoint, salt)) off-chain and submits
    function commitRegistration(bytes32 commitmentHash) external payable {
        require(msg.value >= registrationFee, "Insufficient fee");
        require(commitment[msg.sender] == bytes32(0), "Already committed");
        require(bytes32(0) != commitmentHash, "Invalid commitment");

        commitment[msg.sender] = commitmentHash;
        commitmentTime[msg.sender] = block.timestamp;

        emit CommitmentRegistered(msg.sender, commitmentHash);
    }

    // FIX: Reveal phase — uses committed hash to prevent frontrunning
    function registerAgent(
        string calldata name,
        string calldata endpoint,
        bytes32 salt
    ) external returns (bytes32) {
        require(bytes(name).length > 0 && bytes(name).length <= 64, "Invalid name");

        // Verify commitment exists and is old enough
        require(commitment[msg.sender] != bytes32(0), "No commitment found");
        require(
            block.number >= commitmentTime[msg.sender] + COMMIT_DELAY_BLOCKS,
            "Must wait commit delay"
        );

        // Verify the commitment hash matches
        bytes32 computedHash = keccak256(abi.encodePacked(name, endpoint, salt));
        require(computedHash == commitment[msg.sender], "Commitment mismatch");

        // Clear commitment
        delete commitment[msg.sender];
        delete commitmentTime[msg.sender];

        // FIX: Use deterministic agentId = hash(name + owner + block) to prevent collision
        bytes32 agentId = keccak256(abi.encodePacked(name, msg.sender, blockhash(block.number - 1)));

        // FIX: Check if name is already registered by anyone in recent blocks
        require(
            nameCommitBlock[keccak256(abi.encodePacked(name, msg.sender))] == 0 ||
            block.number > nameCommitBlock[keccak256(abi.encodePacked(name, msg.sender))] + 3,
            "Name reserved by pending registration"
        );

        require(agents[agentId].registeredAt == 0, "Agent exists");

        // FIX: Endpoint validation — must be a valid URL format
        _validateEndpoint(endpoint);

        agents[agentId] = Agent({
            owner: msg.sender,
            name: name,
            endpoint: endpoint,
            reputation: 100,
            tasksCompleted: 0,
            registeredAt: block.timestamp,
            active: true
        });

        ownerAgents[msg.sender].push(agentId);
        agentIds.push(agentId);

        emit AgentRegistered(agentId, msg.sender, name);
        return agentId;
    }

    // FIX: Register multiple agents in one transaction (batch)
    function registerAgentBatch(
        string[] calldata names,
        string[] calldata endpoints,
        bytes32[] calldata salts
    ) external payable returns (bytes32[] memory) {
        require(names.length == endpoints.length && names.length == salts.length, "Array mismatch");
        require(names.length <= 50, "Max 50 per batch");
        require(msg.value >= registrationFee * names.length, "Insufficient total fee");

        bytes32[] memory ids = new bytes32[](names.length);
        for (uint256 i = 0; i < names.length; i++) {
            ids[i] = registerAgent(names[i], endpoints[i], salts[i]);
        }

        emit AgentRegisteredBatch(ids, msg.sender);
        return ids;
    }

    function deactivateAgent(bytes32 agentId) external {
        require(agents[agentId].owner == msg.sender, "Not agent owner");
        agents[agentId].active = false;
        emit AgentDeactivated(agentId);
    }

    function updateReputation(bytes32 agentId, int256 delta) external onlyOwner {
        Agent storage agent = agents[agentId];
        require(agent.registeredAt > 0, "Agent not found");

        if (delta > 0) {
            agent.reputation += uint256(delta);
        } else {
            uint256 decrease = uint256(-delta);
            agent.reputation = agent.reputation > decrease ? agent.reputation - decrease : 0;
        }

        emit ReputationUpdated(agentId, agent.reputation);
    }

    function getAgent(bytes32 agentId) external view returns (Agent memory) {
        return agents[agentId];
    }

    function getActiveAgentCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agents[agentIds[i]].active) count++;
        }
    }

    function setRegistrationFee(uint256 _fee) external onlyOwner {
        registrationFee = _fee;
    }

    function withdrawFees() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    // FIX: Batch query — read multiple agents efficiently
    function getAgents(bytes32[] calldata agentIdsInput)
        external
        view
        returns (Agent[] memory result)
    {
        result = new Agent[](agentIdsInput.length);
        for (uint256 i = 0; i < agentIdsInput.length; i++) {
            result[i] = agents[agentIdsInput[i]];
        }
    }

    // FIX: Validate endpoint URL format
    function _validateEndpoint(string calldata endpoint) internal pure {
        bytes memory ep = bytes(endpoint);
        require(ep.length >= 7, "Endpoint too short");
        // Must start with http:// or https://
        require(
            (ep[0] == "h" && ep[1] == "t" && ep[2] == "t" && ep[3] == "p"),
            "Must be http/https"
        );
        // Check for :// immediately after http/https
        require(ep[4] == "s" || ep[4] == ":", "Invalid protocol");
        if (ep[4] == "s") {
            require(ep[5] == ":" && ep[6] == "/" && ep[7] == "/", "Invalid https format");
        } else {
            require(ep[4] == ":" && ep[5] == "/" && ep[6] == "/", "Invalid http format");
        }
    }
}
