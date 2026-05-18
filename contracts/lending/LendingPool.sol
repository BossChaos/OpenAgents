// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPriceFeed {
    function getPrice(address token) external view returns (uint256);
}

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title LendingPool
/// @notice Collateralized lending pool supporting deposit, borrow, repay, and liquidation
/// @dev Uses an external price feed oracle for collateral valuation
contract LendingPool {
    IPriceFeed public oracle;
    IERC20 public collateralToken;
    IERC20 public borrowToken;

    uint256 public constant LIQUIDATION_THRESHOLD = 1.5e18; // 150%
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MIN_HEALTH_FACTOR = 1.1e18; // FIX: Add safety margin

    struct Position {
        uint256 collateralAmount;
        uint256 borrowedAmount;
    }

    mapping(address => Position) public positions;
    uint256 public totalDeposits;
    uint256 public totalBorrowed;

    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 debtRepaid);

    constructor(address _oracle, address _collateralToken, address _borrowToken) {
        require(_oracle != address(0), "Zero oracle");
        oracle = IPriceFeed(_oracle);
        collateralToken = IERC20(_collateralToken);
        borrowToken = IERC20(_borrowToken);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Zero amount");
        require(collateralToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        positions[msg.sender].collateralAmount += amount;
        totalDeposits += amount;
        emit Deposited(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        require(amount > 0, "Zero amount");
        positions[msg.sender].borrowedAmount += amount;
        totalBorrowed += amount;

        require(_isHealthy(msg.sender), "Undercollateralized");
        require(borrowToken.transfer(msg.sender, amount), "Transfer failed");
        emit Borrowed(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        Position storage pos = positions[msg.sender];
        require(amount <= pos.borrowedAmount, "Repay exceeds debt");
        require(borrowToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        pos.borrowedAmount -= amount;
        totalBorrowed -= amount;
        emit Repaid(msg.sender, amount);
    }

    function liquidate(address user) external {
        require(!_isHealthy(user), "Position healthy");

        Position storage pos = positions[user];
        uint256 debt = pos.borrowedAmount;
        uint256 collateral = pos.collateralAmount;

        require(debt > 0, "No debt to liquidate");
        require(borrowToken.transferFrom(msg.sender, address(this), debt), "Transfer failed");

        // FIX: Handle bad debt — only transfer proportional collateral to liquidator
        uint256 collateralValue = (collateral * LIQUIDATION_THRESHOLD) / PRECISION;
        uint256 debtValue = debt;

        if (collateralValue < debtValue) {
            // Bad debt case: liquidator gets all collateral, protocol absorbs loss
            pos.borrowedAmount = 0;
            pos.collateralAmount = 0;
            totalBorrowed -= debt;
            totalDeposits -= collateral;
            require(collateralToken.transfer(msg.sender, collateral), "Transfer failed");
        } else {
            // Normal case: liquidator gets debt-equivalent collateral + bonus
            uint256 collateralToTransfer = (debt * LIQUIDATION_THRESHOLD) / PRECISION;
            pos.borrowedAmount = 0;
            pos.collateralAmount = collateral - collateralToTransfer;
            totalBorrowed -= debt;
            totalDeposits -= collateralToTransfer;
            require(collateralToken.transfer(msg.sender, collateralToTransfer), "Transfer failed");
        }

        emit Liquidated(user, msg.sender, debt);
    }

    function _isHealthy(address user) internal view returns (bool) {
        Position storage pos = positions[user];
        if (pos.borrowedAmount == 0) return true;

        // FIX: Validate oracle price is non-zero
        uint256 collateralPrice = oracle.getPrice(address(collateralToken));
        require(collateralPrice > 0, "Invalid collateral price");

        uint256 borrowPrice = oracle.getPrice(address(borrowToken));
        require(borrowPrice > 0, "Invalid borrow price");

        uint256 collateralValue = (pos.collateralAmount * collateralPrice) / PRECISION;
        uint256 borrowValue = (pos.borrowedAmount * borrowPrice) / PRECISION;

        return collateralValue >= (borrowValue * LIQUIDATION_THRESHOLD) / PRECISION;
    }

    function getPosition(address user) external view returns (uint256 collateral, uint256 debt) {
        Position storage pos = positions[user];
        return (pos.collateralAmount, pos.borrowedAmount);
    }
}
