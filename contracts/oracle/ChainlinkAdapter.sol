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
    function decimals() external view returns (uint8);
}

/// @title ChainlinkAdapter
/// @notice Adapter for Chainlink price feeds with staleness + negative price + round validation
/// @dev Fixes: answeredInRound check, heartbeat staleness, negative price rejection
contract ChainlinkAdapter {
    address public admin;
    uint256 public constant TARGET_DECIMALS = 18;

    struct FeedConfig {
        AggregatorV3Interface feed;
        uint256 heartbeat; // max seconds between updates
        bool active;
    }

    mapping(address => FeedConfig) public feeds;

    event FeedRegistered(address indexed token, address feed, uint256 heartbeat);
    event FeedDeactivated(address indexed token);
    event PriceStale(address indexed token, uint256 updatedAt, uint256 heartbeat);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function registerFeed(
        address token,
        address feed,
        uint256 heartbeat
    ) external onlyAdmin {
        require(feed != address(0), "Invalid feed");
        require(heartbeat > 0, "Invalid heartbeat");

        feeds[token] = FeedConfig({
            feed: AggregatorV3Interface(feed),
            heartbeat: heartbeat,
            active: true
        });

        emit FeedRegistered(token, feed, heartbeat);
    }

    function deactivateFeed(address token) external onlyAdmin {
        feeds[token].active = false;
        emit FeedDeactivated(token);
    }

    function getPrice(address token) external view returns (uint256) {
        FeedConfig storage config = feeds[token];
        require(config.active, "Feed not active");

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = config.feed.latestRoundData();

        // FIX: Reject negative prices (int256 -> uint256 cast produces huge value)
        require(answer >= 0, "Chainlink negative price");

        // FIX: Check roundId completeness — answer must be from the current round
        require(answeredInRound >= roundId, "Stale round");

        // FIX: Check staleness against heartbeat
        require(
            block.timestamp <= updatedAt + config.heartbeat,
            "Price feed stale"
        );

        uint256 price = uint256(answer);

        // Normalize to 18 decimals
        uint8 feedDecimals = config.feed.decimals();
        if (feedDecimals < TARGET_DECIMALS) {
            price = price * (10 ** (TARGET_DECIMALS - feedDecimals));
        } else if (feedDecimals > TARGET_DECIMALS) {
            price = price / (10 ** (feedDecimals - TARGET_DECIMALS));
        }

        return price;
    }

    // FIX: Multi-hop price with intermediate validation
    function getMultiHopPrice(address tokenA, address tokenB)
        external
        view
        returns (uint256 priceA, uint256 priceB)
    {
        priceA = getPrice(tokenA);
        priceB = getPrice(tokenB);
        require(priceB > 0, "Invalid price for token B");
    }

    function getFeedInfo(address token) external view returns (
        address feedAddress,
        uint256 heartbeat,
        bool active
    ) {
        FeedConfig storage config = feeds[token];
        return (address(config.feed), config.heartbeat, config.active);
    }

    // FIX: Health check — returns whether a feed is considered healthy
    function isFeedHealthy(address token) external view returns (bool) {
        FeedConfig storage config = feeds[token];
        if (!config.active) return false;

        (, int256 answer,, uint256 updatedAt,) = config.feed.latestRoundData();

        // Negative price or stale = unhealthy
        if (answer < 0) return false;
        if (block.timestamp > updatedAt + config.heartbeat) return false;

        return true;
    }
}
