// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Timelock
/// @notice Timelock with min delay enforcement
/// FIX #14: Enforce MIN_DELAY to prevent bypassing governance
contract Timelock is Ownable {
    uint256 public constant MIN_DELAY = 2 days;
    uint256 public constant MAX_DELAY = 30 days;
    uint256 public delay;

    mapping(bytes32 => bool) public queuedTransactions;

    event NewDelay(uint256 indexed newDelay);
    event QueueTransaction(bytes32 indexed txHash, address target, bytes data, uint256 eta);
    event ExecuteTransaction(bytes32 indexed txHash);

    constructor(uint256 _delay) Ownable(msg.sender) {
        require(_delay >= MIN_DELAY && _delay <= MAX_DELAY, "Delay out of range");
        delay = _delay;
    }

    function setDelay(uint256 newDelay) external onlyOwner {
        require(newDelay >= MIN_DELAY, "Below min delay");
        require(newDelay <= MAX_DELAY, "Above max delay");
        delay = newDelay;
        emit NewDelay(newDelay);
    }

    function queueTransaction(
        address target,
        bytes memory data,
        uint256 value
    ) external onlyOwner returns (bytes32) {
        uint256 eta = block.timestamp + delay;
        bytes32 txHash = keccak256(abi.encode(target, data, value, eta));
        queuedTransactions[txHash] = true;
        emit QueueTransaction(txHash, target, data, eta);
        return txHash;
    }

    function executeTransaction(
        address target,
        bytes memory data,
        uint256 value,
        uint256 eta
    ) external onlyOwner returns (bytes memory) {
        bytes32 txHash = keccak256(abi.encode(target, data, value, eta));
        require(queuedTransactions[txHash], "Not queued");
        require(block.timestamp >= eta + MIN_DELAY, "Delay not enforced"); // FIX #14
        require(block.timestamp <= eta + MAX_DELAY, "Expired");
        queuedTransactions[txHash] = false;
        (bool success, bytes memory returnData) = target.call{value: value}(data);
        require(success, "Tx failed");
        emit ExecuteTransaction(txHash);
        return returnData;
    }

    function cancelTransaction(bytes32 txHash) external onlyOwner {
        queuedTransactions[txHash] = false;
    }
}
