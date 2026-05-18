// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Router
/// @notice Token swap router with slippage protection and deadline
/// @dev Routes swaps through AMMPool contracts
contract Router is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public factory;
    address public admin;

    event Swap(address indexed user, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    constructor(address _factory) {
        factory = _factory;
        admin = msg.sender;
    }

    /// @notice Swap tokens through the AMM with slippage protection.
    /// @param tokenIn Input token address.
    /// @param tokenOut Output token address.
    /// @param amountIn Amount of input tokens.
    /// @param amountOutMin Minimum expected output (slippage protection).
    /// @param deadline Deadline timestamp for the swap.
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "Router: zero amount");
        // FIX: Add deadline check to prevent stale transactions
        require(block.timestamp <= deadline, "Router: swap expired");
        // FIX: Require non-zero minimum output to protect against slippage
        require(amountOutMin > 0, "Router: zero min output");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        address pool = getPool(tokenIn, tokenOut);
        require(pool != address(0), "Router: no pool");

        IERC20(tokenIn).safeTransfer(pool, amountIn);

        (bool success, bytes memory data) = pool.call(
            abi.encodeWithSignature("swap(address,address,uint256)", tokenIn, tokenOut, amountIn)
        );
        require(success, "Router: swap failed");

        amountOut = abi.decode(data, (uint256));
        // FIX: Enforce slippage protection — revert if output is below minimum
        require(amountOut >= amountOutMin, "Router: slippage exceeded");

        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    function getPool(address tokenA, address tokenB) internal view returns (address) {
        (bool success, bytes memory data) = factory.call(
            abi.encodeWithSignature("getPool(address,address)", tokenA, tokenB)
        );
        if (!success) return address(0);
        return abi.decode(data, (address));
    }

    function setAdmin(address _admin) external onlyAdmin {
        require(_admin != address(0), "Router: zero address");
        admin = _admin;
    }
}
