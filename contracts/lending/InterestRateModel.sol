// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title InterestRateModel
/// @notice Variable interest rate model with event emission and overflow protection
/// FIX #130, #179: Emit events, add bounds check on baseRate
contract InterestRateModel {
    uint256 public baseRate;
    uint256 public multiplier;
    uint256 public constant MAX_RATE = 100_00; // 100% max

    event RateUpdated(uint256 baseRate, uint256 multiplier);
    event RateCalculated(uint256 utilizationRate, uint256 borrowRate);

    constructor(uint256 _baseRate, uint256 _multiplier) {
        require(_baseRate <= MAX_RATE, "Base rate too high");
        require(_multiplier <= MAX_RATE, "Multiplier too high");
        baseRate = _baseRate;
        multiplier = _multiplier;
    }

    /// @notice Calculate borrow rate based on utilization
    function getBorrowRate(uint256 utilizationRate) external view returns (uint256) {
        require(utilizationRate <= 100_00, "Invalid utilization");
        uint256 rate = baseRate + (utilizationRate * multiplier) / 100_00;
        require(rate <= MAX_RATE, "Rate overflow");
        emit RateCalculated(utilizationRate, rate);
        return rate;
    }

    function setRates(uint256 _baseRate, uint256 _multiplier) external {
        // FIX #179: Add bounds checks
        require(_baseRate <= MAX_RATE, "Base rate too high");
        require(_multiplier <= MAX_RATE, "Multiplier too high");
        baseRate = _baseRate;
        multiplier = _multiplier;
        emit RateUpdated(_baseRate, _multiplier);
    }
}
