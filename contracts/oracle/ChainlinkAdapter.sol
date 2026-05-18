// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title ChainlinkAdapter
/// @notice Chainlink oracle with derived price support
/// FIX #133: Add derivedPrice(address base, address quote) using two feeds
interface AggregatorV3Interface {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

contract ChainlinkAdapter is Ownable {
    mapping(address => address) public priceFeeds;

    event FeedUpdated(address asset, address feed);

    constructor() Ownable(msg.sender) {}

    function setPriceFeed(address asset, address feed) external onlyOwner {
        require(feed != address(0), "Zero feed");
        priceFeeds[asset] = feed;
        emit FeedUpdated(asset, feed);
    }

    /// @notice Get price for single asset
    function getPrice(address asset) external view returns (uint256) {
        address feed = priceFeeds[asset];
        require(feed != address(0), "No feed");
        (, int256 price,, uint256 updatedAt,) = AggregatorV3Interface(feed).latestRoundData();
        require(price > 0, "Negative price");
        require(block.timestamp - updatedAt < 1 hours, "Stale price");
        return uint256(price);
    }

    /// @notice FIX #133: Derived price using two feeds
    function derivedPrice(address base, address quote) external view returns (uint256) {
        address baseFeed = priceFeeds[base];
        address quoteFeed = priceFeeds[quote];
        require(baseFeed != address(0), "No base feed");
        require(quoteFeed != address(0), "No quote feed");

        (, int256 basePrice,, uint256 baseUpdated,) = AggregatorV3Interface(baseFeed).latestRoundData();
        (, int256 quotePrice,, uint256 quoteUpdated,) = AggregatorV3Interface(quoteFeed).latestRoundData();

        require(basePrice > 0 && quotePrice > 0, "Negative price");
        require(block.timestamp - baseUpdated < 1 hours, "Stale base price");
        require(block.timestamp - quoteUpdated < 1 hours, "Stale quote price");

        // Normalize decimals - assume both have 8 decimals
        return (uint256(basePrice) * 1e18) / uint256(quotePrice);
    }
}
