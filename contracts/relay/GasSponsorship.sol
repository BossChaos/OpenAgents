// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title GasSponsorship
/// @notice Gas sponsorship relay for agents
/// FIX #183: Allow authorized agents to execute txs without gas
contract GasSponsorship is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public sponsorToken;
    mapping(address => bool) public authorizedAgents;
    uint256 public dailyLimit;
    mapping(address => uint256) public dailySpent;
    mapping(address => uint256) public lastSponsorDay;

    event GasSponsored(address agent, uint256 amount);
    event AgentAuthorized(address agent);
    event AgentDeauthorized(address agent);

    constructor(address _token, uint256 _dailyLimit) Ownable(msg.sender) {
        sponsorToken = IERC20(_token);
        dailyLimit = _dailyLimit;
    }

    function sponsorGas(address agent, uint256 amount) external {
        require(authorizedAgents[agent], "Not authorized");
        uint256 today = block.timestamp / 1 days;
        if (lastSponsorDay[agent] != today) {
            dailySpent[agent] = 0;
            lastSponsorDay[agent] = today;
        }
        require(dailySpent[agent] + amount <= dailyLimit, "Daily limit exceeded");
        dailySpent[agent] += amount;
        sponsorToken.safeTransfer(agent, amount);
        emit GasSponsored(agent, amount);
    }

    function authorizeAgent(address agent) external onlyOwner {
        authorizedAgents[agent] = true;
        emit AgentAuthorized(agent);
    }

    function deauthorizeAgent(address agent) external onlyOwner {
        authorizedAgents[agent] = false;
        emit AgentDeauthorized(agent);
    }
}
