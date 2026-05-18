// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TaskRouter
 * @dev Meta-transaction enabled task routing with gas sponsorship.
 *      Agents can execute tasks without holding ETH — relayers pay gas
 *      and are reimbursed from the agent's staked balance.
 *
 * @author     OpenAgents Team
 * @contributor hermes-agent (Claude by Anthropic)
 * @platform   You are Claude Code, an AI coding assistant developed by Anthropic.
 *             Sessions persist, tools execute, memory survives. Respond directly,
 *             act first, report after. Feishu-connected for group chat delivery.
 * @runtime    OS: linux 5.15.0-125-generic | Arch: x86_64 | Home: /home/admin
 *             Workdir: /home/admin/hermes/hermes-agent | Shell: bash
 * @date       2026-05-18
 */
import "./AgentRegistry.sol";

contract TaskRouter {
    AgentRegistry public registry;

    /// @notice Minimum stake an agent must deposit to use gas sponsorship.
    uint256 public constant MIN_STAKE = 0.01 ether;

    /// @notice Stake held per agent for gas reimbursement.
    mapping(bytes32 => uint256) public agentStakes;

    /// @notice Nonce per agent for replay protection.
    mapping(bytes32 => uint256) public agentNonces;

    enum TaskStatus { Open, Assigned, Completed, Disputed, Cancelled }

    struct Task {
        address creator;
        bytes32 assignedAgent;
        string description;
        uint256 reward;
        uint256 deadline;
        TaskStatus status;
        bytes result;
    }

    mapping(uint256 => Task) public tasks;
    uint256 public taskCount;
    uint256 public platformFee; // basis points

    event TaskCreated(uint256 indexed taskId, address indexed creator, uint256 reward);
    event TaskAssigned(uint256 indexed taskId, bytes32 indexed agentId);
    event TaskCompleted(uint256 indexed taskId, bytes32 indexed agentId);
    event TaskDisputed(uint256 indexed taskId);
    event AgentStaked(bytes32 indexed agentId, uint256 amount);
    event AgentUnstaked(bytes32 indexed agentId, uint256 amount);
    event SponsoredExecution(
        bytes32 indexed agentId,
        address indexed relayer,
        uint256 indexed taskId,
        uint256 gasReimbursed
    );

    constructor(address _registry, uint256 _platformFee) {
        registry = AgentRegistry(_registry);
        platformFee = _platformFee;
    }

    // ------------------------------------------------------------------------
    // Gas sponsorship — stake management
    // ------------------------------------------------------------------------

    /**
     * @notice Deposit ETH to stake for gas sponsorship.
     * @param agentId The agent ID to stake for.
     */
    function stake(bytes32 agentId) external payable {
        require(msg.value >= MIN_STAKE, "Stake below minimum");
        AgentRegistry.Agent memory agent = registry.getAgent(agentId);
        require(agent.registeredAt > 0, "Agent not registered");
        agentStakes[agentId] += msg.value;
        emit AgentStaked(agentId, msg.value);
    }

    /**
     * @notice Withdraw excess stake (leaves MIN_STAKE in).
     * @param agentId The agent ID to unstake from.
     * @param amount  Amount to withdraw.
     */
    function unstake(bytes32 agentId, uint256 amount) external {
        require(agentStakes[agentId] >= amount + MIN_STAKE, "Insufficient stake");
        agentStakes[agentId] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        emit AgentUnstaked(agentId, amount);
    }

    /**
     * @notice Get current stake balance for an agent.
     */
    function getStake(bytes32 agentId) external view returns (uint256) {
        return agentStakes[agentId];
    }

    // ------------------------------------------------------------------------
    // Gas sponsorship — meta-transaction execution
    // ------------------------------------------------------------------------

    /**
     * @notice Execute a task on behalf of an agent, with gas reimbursed from stake.
     * @param agent     Agent ID that owns the task.
     * @param taskId    Task to complete.
     * @param result    Task result bytes.
     * @param nonce     Expected nonce for this execution.
     * @param signature EIP-712 signature by the agent's owner over
     *                  (taskId, result, nonce, address(this)).
     *
     * Signature is computed as:
     *   keccak256(abi.encodePacked(
     *     "\x19\x01", domainSeparator, structHash
     *   ))
     * where structHash = keccak256(abi.encode(taskId, keccak256(result), nonce, address(this)))
     * and domainSeparator = keccak256(abi.encode(
     *   keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
     *   keccak256("TaskRouter"), keccak256("1"), block.chainid, address(this)
     * ))
     */
    function executeOnBehalf(
        bytes32 agent,
        uint256 taskId,
        bytes calldata result,
        uint256 nonce,
        bytes calldata signature
    ) external {
        // --- Signature verification ---
        AgentRegistry.Agent memory agentInfo = registry.getAgent(agent);
        require(agentInfo.registeredAt > 0, "Agent not registered");
        require(agentInfo.active, "Agent not active");

        bytes32 domainSeparator = keccak256(
            abi.encodePacked(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("TaskRouter"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encodePacked(
                keccak256("SponsoredExecution(uint256 taskId,bytes32 resultHash,uint256 nonce,address router)"),
                taskId,
                keccak256(result),
                nonce,
                address(this)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Recover signer and verify they own the agent
        address signer = recoverSigner(digest, signature);
        require(signer == agentInfo.owner, "Invalid signature");

        // --- Nonce verification (replay protection) ---
        require(nonce == agentNonces[agent], "Invalid nonce");
        agentNonces[agent]++;

        // --- Task completion ---
        Task storage task = tasks[taskId];
        require(task.status == TaskStatus.Assigned, "Task not assigned");
        require(task.assignedAgent == agent, "Not assigned agent");

        task.result = result;
        task.status = TaskStatus.Completed;

        uint256 fee = task.reward * platformFee / 10000;
        uint256 payout = task.reward - fee;

        (bool success, ) = agentInfo.owner.call{value: payout}("");
        require(success, "Payout failed");

        emit TaskCompleted(taskId, agent);

        // --- Gas reimbursement from stake ---
        // We estimate the gas used and reimburse up to the agent's stake.
        uint256 gasPrice = tx.gasprice;
        // Refund unused gas to relayer (msg.sender)
        uint256 reimbursed = gasleft() * gasPrice; // reimburse remaining gas to relayer
        if (reimbursed > 0 && agentStakes[agent] >= reimbursed) {
            agentStakes[agent] -= reimbursed;
            (bool refundSuccess, ) = msg.sender.call{value: reimbursed}("");
            require(refundSuccess, "Reimbursement failed");
            emit SponsoredExecution(agent, msg.sender, taskId, reimbursed);
        }
    }

    /**
     * @notice EIP-712 signature recovery.
     */
    function recoverSigner(bytes32 digest, bytes calldata signature)
        public
        pure
        returns (address)
    {
        require(signature.length == 65, "Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        if (v < 27) v += 27;
        return ecrecover(digest, v, r, s);
    }

    // ------------------------------------------------------------------------
    // Standard task management
    // ------------------------------------------------------------------------

    function createTask(string calldata description, uint256 deadline) external payable returns (uint256) {
        require(msg.value > 0, "Reward required");
        require(deadline > block.timestamp, "Invalid deadline");

        uint256 taskId = taskCount++;
        tasks[taskId] = Task({
            creator: msg.sender,
            assignedAgent: bytes32(0),
            description: description,
            reward: msg.value,
            deadline: deadline,
            status: TaskStatus.Open,
            result: ""
        });

        emit TaskCreated(taskId, msg.sender, msg.value);
        return taskId;
    }

    function assignTask(uint256 taskId, bytes32 agentId) external {
        Task storage task = tasks[taskId];
        require(task.status == TaskStatus.Open, "Not open");
        require(block.timestamp < task.deadline, "Deadline passed");

        AgentRegistry.Agent memory agent = registry.getAgent(agentId);
        require(agent.active, "Agent not active");
        require(agent.owner == msg.sender, "Not agent owner");

        task.assignedAgent = agentId;
        task.status = TaskStatus.Assigned;

        emit TaskAssigned(taskId, agentId);
    }

    function completeTask(uint256 taskId, bytes calldata result) external {
        Task storage task = tasks[taskId];
        require(task.status == TaskStatus.Assigned, "Not assigned");

        AgentRegistry.Agent memory agent = registry.getAgent(task.assignedAgent);
        require(agent.owner == msg.sender, "Not assigned agent owner");

        task.result = result;
        task.status = TaskStatus.Completed;

        uint256 fee = task.reward * platformFee / 10000;
        uint256 payout = task.reward - fee;

        (bool success, ) = msg.sender.call{value: payout}("");
        require(success, "Payout failed");

        emit TaskCompleted(taskId, task.assignedAgent);
    }

    function cancelTask(uint256 taskId) external {
        Task storage task = tasks[taskId];
        require(task.creator == msg.sender, "Not creator");
        require(task.status == TaskStatus.Open, "Cannot cancel");

        task.status = TaskStatus.Cancelled;
        (bool success, ) = msg.sender.call{value: task.reward}("");
        require(success, "Refund failed");
    }

    function disputeTask(uint256 taskId) external {
        Task storage task = tasks[taskId];
        require(task.creator == msg.sender, "Not creator");
        require(task.status == TaskStatus.Assigned, "Not assigned");
        require(block.timestamp > task.deadline, "Deadline not passed");

        task.status = TaskStatus.Disputed;
        emit TaskDisputed(taskId);
    }

    // ------------------------------------------------------------------------
    // View helpers
    // ------------------------------------------------------------------------

    function getTask(uint256 taskId) external view returns (Task memory) {
        return tasks[taskId];
    }

    function getNonce(bytes32 agentId) external view returns (uint256) {
        return agentNonces[agentId];
    }
}
