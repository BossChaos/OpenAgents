// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title TaskRouter
/// @notice Route tasks to agents with bounty payments
/// FIX #152: Add proper deadline and completion checks
contract TaskRouter is Ownable {
    using SafeERC20 for IERC20;

    struct Task {
        address creator;
        address agent;
        uint256 reward;
        uint256 deadline;
        bool completed;
        bool cancelled;
    }

    mapping(uint256 => Task) public tasks;
    IERC20 public rewardToken;
    uint256 public nextTaskId;

    event TaskCreated(uint256 taskId, address creator, address agent, uint256 reward);
    event TaskCompleted(uint256 taskId, address agent);
    event TaskCancelled(uint256 taskId);
    event TaskExpired(uint256 taskId);

    constructor(address _rewardToken) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
    }

    function createTask(address agent, uint256 reward, uint256 deadline) external {
        require(agent != address(0), "Zero agent");
        require(reward > 0, "Zero reward");
        require(deadline > block.timestamp, "Past deadline");

        rewardToken.safeTransferFrom(msg.sender, address(this), reward);

        tasks[nextTaskId] = Task({
            creator: msg.sender,
            agent: agent,
            reward: reward,
            deadline: deadline,
            completed: false,
            cancelled: false
        });

        emit TaskCreated(nextTaskId, msg.sender, agent, reward);
        nextTaskId++;
    }

    function completeTask(uint256 taskId) external {
        Task storage task = tasks[taskId];
        require(!task.completed && !task.cancelled, "Task done");
        // FIX #152: Check deadline
        require(block.timestamp <= task.deadline, "Deadline passed");
        require(msg.sender == task.creator || msg.sender == task.agent, "Not authorized");

        task.completed = true;
        rewardToken.safeTransfer(task.agent, task.reward);
        emit TaskCompleted(taskId, task.agent);
    }

    function cancelTask(uint256 taskId) external {
        Task storage task = tasks[taskId];
        require(!task.completed, "Task completed");
        require(msg.sender == task.creator, "Not creator");

        task.cancelled = true;
        rewardToken.safeTransfer(task.creator, task.reward);
        emit TaskCancelled(taskId);
    }

    function expireTask(uint256 taskId) external {
        Task storage task = tasks[taskId];
        require(!task.completed && !task.cancelled, "Task done");
        // FIX: Allow anyone to expire expired tasks and refund
        require(block.timestamp > task.deadline, "Not expired");

        task.cancelled = true;
        rewardToken.safeTransfer(task.creator, task.reward);
        emit TaskExpired(taskId);
    }
}
