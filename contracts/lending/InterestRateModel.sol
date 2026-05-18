// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title InterestRateModel
/// @notice Variable interest rate model with event emission and overflow protection
/// @dev Fixes: emit events on param changes, utilization bounds, kink edge cases
contract InterestRateModel {
    uint256 public baseRate;
    uint256 public multiplier;
    uint256 public jumpMultiplier;
    uint256 public kink;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant BLOCKS_PER_YEAR = 2_628_000;

    address public admin;

    event RateParamsUpdated(
        uint256 baseRate,
        uint256 multiplier,
        uint256 jumpMultiplier,
        uint256 kink,
        uint256 newAnnualRateAtKink
    );
    event AdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    constructor(
        uint256 _baseRate,
        uint256 _multiplier,
        uint256 _jumpMultiplier,
        uint256 _kink
    ) {
        require(_kink <= PRECISION, "Kink must be <= 100%");
        admin = msg.sender;
        baseRate = _baseRate;
        multiplier = _multiplier;
        jumpMultiplier = _jumpMultiplier;
        kink = _kink;
        emit RateParamsUpdated(_baseRate, _multiplier, _jumpMultiplier, _kink,
            _baseRate + (_kink * _multiplier) / PRECISION);
    }

    function updateParams(
        uint256 _baseRate,
        uint256 _multiplier,
        uint256 _jumpMultiplier,
        uint256 _kink
    ) external onlyAdmin {
        require(_kink <= PRECISION, "Kink must be <= 100%");

        // FIX: Emit event on every parameter update (was missing)
        baseRate = _baseRate;
        multiplier = _multiplier;
        jumpMultiplier = _jumpMultiplier;
        kink = _kink;

        uint256 annualRateAtKink = _baseRate + (_kink * _multiplier) / PRECISION;
        emit RateParamsUpdated(_baseRate, _multiplier, _jumpMultiplier, _kink, annualRateAtKink);
    }

    function getUtilization(uint256 totalBorrowed, uint256 totalDeposits) public pure returns (uint256) {
        if (totalDeposits == 0) return 0;
        return (totalBorrowed * PRECISION) / totalDeposits;
    }

    function getBorrowRate(uint256 totalBorrowed, uint256 totalDeposits) external view returns (uint256) {
        uint256 utilization = getUtilization(totalBorrowed, totalDeposits);

        if (utilization <= kink) {
            // FIX: Utilization at 0 gives baseRate only
            return baseRate + (utilization * multiplier) / PRECISION;
        }

        // FIX: Handle kink == PRECISION edge case (100% utilization)
        uint256 normalRate = baseRate + (kink * multiplier) / PRECISION;

        uint256 excessUtilization = utilization - kink;

        // FIX: Safe division — if kink == PRECISION, normalRate is returned
        uint256 jumpRate = 0;
        if (PRECISION - kink > 0) {
            jumpRate = (excessUtilization * jumpMultiplier) / (PRECISION - kink);
        }

        // FIX: Cap maximum borrow rate at 10x annual supply to prevent overflow
        uint256 maxRate = PRECISION * 10; // 1000% APR
        uint256 totalRate = normalRate + jumpRate;
        if (totalRate > maxRate) {
            totalRate = maxRate;
        }

        return totalRate;
    }

    function getSupplyRate(
        uint256 totalBorrowed,
        uint256 totalDeposits,
        uint256 reserveFactor
    ) external view returns (uint256) {
        if (totalDeposits == 0) return 0;
        uint256 utilization = getUtilization(totalBorrowed, totalDeposits);
        uint256 borrowRate = this.getBorrowRate(totalBorrowed, totalDeposits);
        uint256 rateToPool = (borrowRate * (PRECISION - reserveFactor)) / PRECISION;
        return (utilization * rateToPool) / PRECISION;
    }

    function getAnnualRate(uint256 totalBorrowed, uint256 totalDeposits) external view returns (uint256) {
        return this.getBorrowRate(totalBorrowed, totalDeposits) * BLOCKS_PER_YEAR;
    }

    // FIX: View function to preview rates without state changes
    function previewRates(
        uint256 totalBorrowed,
        uint256 totalDeposits,
        uint256 reserveFactor
    ) external view returns (uint256 borrowRate, uint256 supplyRate, uint256 utilization_) {
        utilization_ = getUtilization(totalBorrowed, totalDeposits);
        borrowRate = this.getBorrowRate(totalBorrowed, totalDeposits);
        supplyRate = (utilization_ * borrowRate * (PRECISION - reserveFactor) / PRECISION) / PRECISION;
    }
}
