// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title InterestRateModel
/// @notice Interest rate model with proper events
/// FIX #130: Add RateParametersUpdated event
contract InterestRateModel {
    uint256 public baseRate;
    uint256 public multiplier;
    uint256 public jumpRate;
    uint256 public optimalUtilization;

    /// @notice FIX #130: Event for parameter updates
    event RateParametersUpdated(
        uint256 oldBaseRate,
        uint256 newBaseRate,
        uint256 oldMultiplier,
        uint256 newMultiplier,
        uint256 oldJumpRate,
        uint256 newJumpRate
    );
    event BorrowRateUpdated(address asset, uint256 rate);
    event SupplyRateUpdated(address asset, uint256 rate);

    /// @notice Update rate parameters with events
    function updateRateParameters(
        uint256 _baseRate,
        uint256 _multiplier,
        uint256 _jumpRate
    ) external {
        // FIX: Emit old and new values
        emit RateParametersUpdated(
            baseRate, _baseRate,
            multiplier, _multiplier,
            jumpRate, _jumpRate
        );
        baseRate = _baseRate;
        multiplier = _multiplier;
        jumpRate = _jumpRate;
    }

    function getBorrowRate(uint256 utilization) external view returns (uint256) {
        if (utilization <= optimalUtilization) {
            return (utilization * multiplier) / 1e18 + baseRate;
        } else {
            uint256 excessUtil = utilization - optimalUtilization;
            return (excessUtil * jumpRate) / 1e18 +
                   (optimalUtilization * multiplier) / 1e18 + baseRate;
        }
    }
}
