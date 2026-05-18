// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SecureVestingWallet
/// @notice Vesting wallet with overflow protection
/// FIX #12: Use SafeMath / checked arithmetic for vesting schedule
contract SecureVestingWallet {
    using SafeERC20 for IERC20;

    event Released(address beneficiary, uint256 amount);

    uint256 public immutable start;
    uint256 public immutable duration;
    uint64 public immutable cliff;
    uint256 public immutable totalAmount;

    mapping(address => uint256) public released;

    constructor(
        uint256 _start,
        uint256 _duration,
        uint256 _cliff,
        uint256 _totalAmount
    ) {
        require(_duration > 0, "Zero duration");
        require(_cliff <= _duration, "Cliff > duration");
        // FIX #12: totalAmount should not overflow when computing releases
        require(_totalAmount <= type(uint256).max / _duration, "Amount too large");

        start = _start;
        duration = _duration;
        cliff = uint64(_cliff);
        totalAmount = _totalAmount;
    }

    function release(address beneficiary) external {
        require(block.timestamp >= cliff, "Before cliff");
        uint256 releasable = vestedAmount(beneficiary) - released[beneficiary];
        require(releasable > 0, "Nothing to release");
        released[beneficiary] += releasable; // Use SafeMath in production

        IERC20 token = IERC20(address(this)); // For native token: use this contract's balance
        // For ERC20: adjust accordingly
        // token.safeTransfer(beneficiary, releasable);
        emit Released(beneficiary, releasable);
    }

    /// @notice FIX #12: Compute vested amount with safe arithmetic
    function vestedAmount(address) public view returns (uint256) {
        if (block.timestamp < cliff) return 0;
        if (block.timestamp >= start + duration) return totalAmount;

        // Safe: duration > 0 guaranteed in constructor
        uint256 elapsed = block.timestamp - start;
        // FIX #12: checked multiplication prevents overflow
        return (totalAmount * elapsed) / duration;
    }
}
