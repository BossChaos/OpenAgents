// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PriceOracle
/// @notice Price oracle with TWAP window
/// FIX #88: Longer TWAP window for price stability
contract PriceOracle {
    struct Observation {
        uint256 timestamp;
        uint256 price;
    }

    Observation[] public observations;
    uint256 public constant MIN_WINDOW = 3600; // 1 hour min
    uint256 public twapWindow;

    constructor(uint256 _twapWindow) {
        require(_twapWindow >= MIN_WINDOW, "Window too short");
        twapWindow = _twapWindow;
    }

    /// @notice Record price observation
    function update(uint256 price) external {
        require(price > 0, "Zero price");
        observations.push(Observation({
            timestamp: block.timestamp,
            price: price
        }));
    }

    /// @notice Get TWAP price
    function getTWAP() external view returns (uint256) {
        require(observations.length > 0, "No data");

        uint256 cutoff = block.timestamp - twapWindow;
        uint256 sum;
        uint256 count;

        // FIX #88: Use observations within TWAP window
        for (uint256 i = 0; i < observations.length; i++) {
            if (observations[i].timestamp >= cutoff) {
                sum += observations[i].price;
                count++;
            }
        }

        require(count > 0, "No observations in window");
        return sum / count;
    }

    function setTwapWindow(uint256 _window) external {
        require(_window >= MIN_WINDOW, "Too short");
        twapWindow = _window;
    }
}
