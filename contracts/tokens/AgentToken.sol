// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title AgentToken
/// @notice ERC20 token with max supply cap
/// FIX #57: Add max supply cap and minting control
contract AgentToken is ERC20 {
    uint256 public constant MAX_SUPPLY = 1_000_000_000e18; // 1B tokens

    mapping(address => bool) public minters;

    event MinterUpdated(address minter, bool allowed);

    constructor() ERC20("AgentToken", "AGT") {
        minters[msg.sender] = true;
    }

    modifier onlyMinter() {
        require(minters[msg.sender], "Not a minter");
        _;
    }

    function setMinter(address minter, bool allowed) external {
        require(minters[msg.sender], "Caller not minter");
        minters[minter] = allowed;
        emit MinterUpdated(minter, allowed);
    }

    function mint(address to, uint256 amount) external onlyMinter {
        require(totalSupply() + amount <= MAX_SUPPLY, "Max supply exceeded");
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
