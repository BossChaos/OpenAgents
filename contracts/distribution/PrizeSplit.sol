// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title PrizeSplit
/// @notice Prize distribution with reentrancy guard
/// FIX #17: Add ReentrancyGuard + CEI pattern
abstract contract ReentrancyGuard {
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "ReentrancyGuard: reentrant call");
        _locked = 2;
        _;
        _locked = 1;
    }
}

contract PrizeSplit is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct PrizePool {
        IERC20 token;
        address[] recipients;
        uint256[] percentages; // basis points
        uint256 totalPrize;
    }

    mapping(uint256 => PrizePool) public pools;

    event PrizeClaimed(uint256 poolId, address recipient, uint256 amount);

    function createPool(
        address token,
        address[] calldata recipients,
        uint256[] calldata percentages
    ) external returns (uint256 poolId) {
        require(recipients.length == percentages.length, "Mismatch");
        uint256 total;
        for (uint256 i = 0; i < percentages.length; i++) total += percentages[i];
        require(total == 10000, "Must equal 100%"); // 10000 bps = 100%

        poolId = uint256(keccak256(abi.encode(recipients, block.timestamp)));
        pools[poolId] = PrizePool({
            token: IERC20(token),
            recipients: recipients,
            percentages: percentages,
            totalPrize: 0
        });
    }

    function fundPool(uint256 poolId, uint256 amount) external {
        PrizePool storage pool = pools[poolId];
        pool.token.safeTransferFrom(msg.sender, address(this), amount);
        pool.totalPrize += amount;
    }

    /// @notice FIX #17: CEI pattern + ReentrancyGuard
    function claimPrize(uint256 poolId, uint256 recipientIndex) external nonReentrant {
        PrizePool storage pool = pools[poolId];
        require(recipientIndex < pool.recipients.length, "Invalid index");
        require(msg.sender == pool.recipients[recipientIndex], "Not recipient");

        uint256 amount = (pool.totalPrize * pool.percentages[recipientIndex]) / 10000;
        require(amount > 0, "Nothing to claim");

        // CEI: Effects before Interactions
        pool.percentages[recipientIndex] = 0; // Mark as claimed

        // Interaction last
        pool.token.safeTransfer(msg.sender, amount);
        emit PrizeClaimed(poolId, msg.sender, amount);
    }
}
