// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title PrizeSplit
/// @notice Prize distribution with reentrancy protection and zero-winner guard
/// FIX #191, #193: Zero-winner check, rounding fix
contract PrizeSplit is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;
    address[] public winners;
    uint256 public prizePool;
    bool public distributed;

    event PrizeDistributed(address winner, uint256 amount);
    event PoolFunded(uint256 amount);

    constructor(address _token) {
        rewardToken = IERC20(_token);
    }

    function fundPool(uint256 amount) external {
        require(amount > 0, "Zero amount");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        prizePool += amount;
        emit PoolFunded(amount);
    }

    function addWinner(address winner) external {
        require(winner != address(0), "Zero address");
        require(!distributed, "Already distributed");
        winners.push(winner);
    }

    /// @notice Distribute prizes to all winners
    /// FIX #191: Check for zero winners, prevent div-by-zero
    /// FIX #193: Handle rounding remainder correctly
    function distribute() external nonReentrant {
        require(!distributed, "Already distributed");
        // FIX #191: Require at least one winner
        require(winners.length > 0, "No winners");

        uint256 share = prizePool / winners.length;
        uint256 remainder = prizePool % winners.length;

        for (uint256 i = 0; i < winners.length; i++) {
            uint256 amount = share + (i < remainder ? 1 : 0); // FIX: Distribute remainder
            rewardToken.safeTransfer(winners[i], amount);
            emit PrizeDistributed(winners[i], amount);
        }

        distributed = true;
        prizePool = 0;
    }

    function getWinnerCount() external view returns (uint256) {
        return winners.length;
    }
}
