// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

/// @title ChainlinkAdapter
/// @notice Safe Chainlink price feed adapter with staleness check
/// FIX #133, #154: Add staleness and negative price checks
contract ChainlinkAdapter {
    AggregatorV3Interface public priceFeed;
    uint256 public constant MAX_STALENESS = 1 hours;

    constructor(address _priceFeed) {
        require(_priceFeed != address(0), "Zero address");
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /// @notice Get the latest price with safety checks
    /// FIX #133: Validate staleness and negative price
    function getPrice() external view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = priceFeed.latestRoundData();

        // FIX: Check for negative price
        require(answer > 0, "Invalid price");
        // FIX: Check for staleness
        require(block.timestamp - updatedAt <= MAX_STALENESS, "Stale price");
        // FIX: Check for round completeness
        require(updatedAt > 0, "Round not complete");

        return uint256(answer);
    }

    function getPriceFeed() external view returns (address) {
        return address(priceFeed);
    }
}
