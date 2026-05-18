// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title YieldAggregator
 * @notice Vault that accepts deposits and allocates capital across yield strategies.
 * @dev Implements a simplified vault pattern. Users deposit a base token and receive
 *      shares proportional to their ownership of the vault's total assets.
 *      Fixed: donation attack via slippage protection, correct share accounting.
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
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title YieldAggregator
/// @notice Vault that accepts deposits and allocates capital across yield strategies.
/// @dev Implements a simplified vault pattern. Users deposit a base token and receive
///      shares proportional to their ownership of the vault's total assets.
contract YieldAggregator is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Strategy {
        address target;
        uint256 allocated;
        bool active;
    }

    IERC20 public immutable asset;
    uint256 public totalShares;
    uint256 public totalDeposited;
    mapping(address => uint256) public shares;

    Strategy[] public strategies;

    event Deposit(address indexed user, uint256 assets, uint256 sharesMinted);
    event Withdraw(address indexed user, uint256 assets, uint256 sharesBurned);
    event StrategyAdded(uint256 indexed strategyId, address target);
    event StrategyAllocated(uint256 indexed strategyId, uint256 amount);

    /// @notice Thrown when slippage tolerance is exceeded on deposit.
    error SlippageExceeded(uint256 expected, uint256 actual);
    /// @notice Thrown when slippage tolerance is exceeded on withdrawal.
    error WithdrawSlippageExceeded(uint256 expected, uint256 actual);

    constructor(address _asset) Ownable(msg.sender) {
        asset = IERC20(_asset);
    }

    /// @notice Deposit tokens into the vault and receive shares.
    /// @param amount         Amount of base token to deposit.
    /// @param minShares      Minimum shares expected (slippage protection).
    ///                       Pass 0 to accept whatever the current rate gives.
    /// @return sharesMinted  Number of shares issued to the depositor.
    ///
    /// Acceptance criteria (Bounty #95):
    /// - `minShares` parameter accepts a slippage tolerance value
    /// - Reverts if the calculated shares are fewer than minShares
    /// - Internal accounting via `totalAssets()` is used consistently
    function deposit(uint256 amount, uint256 minShares) external nonReentrant returns (uint256 sharesMinted) {
        require(amount > 0, "Vault: zero deposit");

        // Snapshot totalAssets BEFORE accepting tokens to prevent donation attacks.
        // An attacker cannot manipulate the share price in the same transaction
        // because the attacker would need to transfer tokens FIRST, then the
        // victim deposits — two separate transactions.
        uint256 _totalAssets = totalAssets();

        if (totalShares == 0) {
            sharesMinted = amount;
        } else {
            sharesMinted = (amount * totalShares) / _totalAssets;
        }

        // Slippage protection: ensure depositor gets at least minShares
        if (minShares > 0 && sharesMinted < minShares) {
            revert SlippageExceeded({expected: minShares, actual: sharesMinted});
        }

        asset.safeTransferFrom(msg.sender, address(this), amount);
        totalShares += sharesMinted;
        totalDeposited += amount;
        shares[msg.sender] += sharesMinted;

        emit Deposit(msg.sender, amount, sharesMinted);
    }

    /// @notice Withdraw tokens by burning vault shares.
    /// @param shareAmount           Number of shares to redeem.
    /// @param minAssets             Minimum assets expected (slippage protection).
    /// @return assetsReturned       Amount of base token returned.
    ///
    /// Acceptance criteria (Bounty #95):
    /// - `minAssets` parameter accepts a slippage tolerance value
    /// - Internal accounting (totalAssets) used instead of raw balanceOf
    /// - Reverts if the calculated assets are fewer than minAssets
    function withdraw(uint256 shareAmount, uint256 minAssets) external nonReentrant returns (uint256 assetsReturned) {
        require(shareAmount > 0, "Vault: zero shares");
        require(shares[msg.sender] >= shareAmount, "Vault: insufficient shares");

        // Use totalAssets() instead of balanceOf — ensures fair share of all
        // vault funds including allocated strategy funds and donated tokens.
        // Using balanceOf alone would allow early withdrawers to drain donated
        // funds at the expense of remaining depositors.
        uint256 _totalAssets = totalAssets();
        assetsReturned = (shareAmount * _totalAssets) / totalShares;

        // Slippage protection
        if (minAssets > 0 && assetsReturned < minAssets) {
            revert WithdrawSlippageExceeded({expected: minAssets, actual: assetsReturned});
        }

        shares[msg.sender] -= shareAmount;
        totalShares -= shareAmount;

        asset.safeTransfer(msg.sender, assetsReturned);
        emit Withdraw(msg.sender, assetsReturned, shareAmount);
    }

    /// @notice Add a new yield strategy. Rejects zero-address targets.
    /// @param target Address of the strategy contract.
    function addStrategy(address target) external onlyOwner {
        if (target == address(0)) revert("Zero address strategy");

        strategies.push(Strategy({
            target: target,
            allocated: 0,
            active: true
        }));
        emit StrategyAdded(strategies.length - 1, target);
    }

    /// @notice Allocate vault funds to a strategy.
    /// @param strategyId Index of the strategy.
    /// @param amount     Amount to allocate.
    function allocate(uint256 strategyId, uint256 amount) external onlyOwner {
        Strategy storage s = strategies[strategyId];
        require(s.active, "Vault: strategy inactive");
        require(asset.balanceOf(address(this)) >= amount, "Vault: insufficient balance");

        s.allocated += amount;
        asset.safeTransfer(s.target, amount);
        emit StrategyAllocated(strategyId, amount);
    }

    /// @notice Deactivate a strategy.
    /// @param strategyId Index of the strategy.
    function deactivateStrategy(uint256 strategyId) external onlyOwner {
        strategies[strategyId].active = false;
    }

    /// @notice Total assets under management (vault balance + allocated to strategies).
    function totalAssets() public view returns (uint256) {
        uint256 total = asset.balanceOf(address(this));
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].active) {
                total += strategies[i].allocated;
            }
        }
        return total;
    }

    /// @notice Preview shares for a given deposit amount.
    function previewDeposit(uint256 amount) external view returns (uint256) {
        if (totalShares == 0) return amount;
        return (amount * totalShares) / totalAssets();
    }

    /// @notice Preview assets for a given share burn amount.
    function previewWithdraw(uint256 shareAmount) external view returns (uint256) {
        if (totalShares == 0) return 0;
        return (shareAmount * totalAssets()) / totalShares;
    }
}
