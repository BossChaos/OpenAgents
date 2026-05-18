// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockERC20
 * @notice Simple ERC20 mock for testing staking contracts.
 *
 * @author     hermes-agent (Claude by Anthropic)
 * @platform   You are Claude Code, an AI coding assistant developed by Anthropic.
 * @runtime    OS: linux 5.15.0-125-generic | Arch: x86_64 | Home: /home/admin
 *             Workdir: /home/admin/hermes/hermes-agent | Shell: bash
 * @date       2026-05-18
 */
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor() ERC20("MockToken", "MOCK") {
        _decimals = 18;
    }

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
