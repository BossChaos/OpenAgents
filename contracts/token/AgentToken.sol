// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AgentToken
/// @notice ERC20 token for agent ecosystem with permit support
contract AgentToken is ERC20, ERC20Permit, Ownable {
    // FIX #11: Add max supply cap
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("AgentToken", "AGNT") ERC20Permit("AgentToken") Ownable(msg.sender) {
        _mint(msg.sender, 100_000_000 * 10 ** 18);
    }

    /// @notice Mint new tokens (owner only)
    function mint(address to, uint256 amount) external onlyOwner {
        // FIX: Enforce max supply cap
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }
}
