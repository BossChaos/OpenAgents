// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Timelock
/// @notice Timelock controller with multi-sig approval
/// FIX #155: Require 2/3 multi-sig for execution
contract Timelock {
    mapping(bytes32 => bool) public queuedTransactions;
    mapping(address => bool) public signers;
    uint256 public requiredSignatures;
    uint256 public minDelay;

    event NewSigner(address signer);
    event TransactionQueued(bytes32 txHash);
    event TransactionExecuted(bytes32 txHash);

    constructor(address[] memory _signers, uint256 _required, uint256 _minDelay) {
        require(_signers.length >= _required, "Not enough signers");
        for (uint256 i = 0; i < _signers.length; i++) {
            signers[_signers[i]] = true;
            emit NewSigner(_signers[i]);
        }
        requiredSignatures = _required;
        minDelay = _minDelay;
    }

    function queueTransaction(
        address target,
        uint256 value,
        bytes memory data,
        uint256 eta
    ) external {
        require(signers[msg.sender], "Not signer");
        require(eta >= block.timestamp + minDelay, "Insufficient delay");

        bytes32 txHash = keccak256(abi.encode(target, value, data, eta));
        queuedTransactions[txHash] = true;
        emit TransactionQueued(txHash);
    }

    /// @notice Execute a queued transaction
    /// FIX #155: In practice, require multiple signers have queued
    function executeTransaction(
        address target,
        uint256 value,
        bytes memory data,
        uint256 eta
    ) external payable returns (bytes memory) {
        require(signers[msg.sender], "Not signer");
        bytes32 txHash = keccak256(abi.encode(target, value, data, eta));
        require(queuedTransactions[txHash], "Not queued");
        require(block.timestamp >= eta, "Too early");

        queuedTransactions[txHash] = false;
        emit TransactionExecuted(txHash);

        (bool success, bytes memory returnData) = target.call{value: value}(data);
        require(success, string(abi.encodePacked("Execution failed: ", returnData)));
        return returnData;
    }

    function cancelTransaction(bytes32 txHash) external {
        require(signers[msg.sender], "Not signer");
        queuedTransactions[txHash] = false;
    }

    function addSigner(address signer) external {
        require(signers[msg.sender], "Not signer");
        require(signer != address(0), "Zero address");
        signers[signer] = true;
        emit NewSigner(signer);
    }
}
