// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title Timelock
/// @notice Multi-sig timelock controller
/// FIX #31: Multi-sig approval requirement
contract Timelock is Ownable {
    struct Transaction {
        address target;
        bytes data;
        uint256 value;
        uint256 eta;
        bool executed;
        uint256 confirmations;
        mapping(address => bool) confirmedBy;
    }

    uint256 public proposalId;
    uint256 public minSignatures;
    mapping(uint256 => Transaction) public transactions;
    mapping(address => bool) public signers;

    uint256 public constant MIN_DELAY = 2 days;
    uint256 public constant MAX_DELAY = 30 days;

    event Queued(uint256 id, address target, uint256 eta);
    event Executed(uint256 id);
    event Confirmed(uint256 id, address signer);

    constructor(address[] memory _signers, uint256 _minSignatures) Ownable(msg.sender) {
        require(_signers.length > 0, "No signers");
        require(_minSignatures > 0 && _minSignatures <= _signers.length, "Invalid threshold");
        minSignatures = _minSignatures;
        for (uint256 i = 0; i < _signers.length; i++) {
            signers[_signers[i]] = true;
        }
    }

    /// @notice Queue a transaction
    function queueTransaction(address target, bytes memory data, uint256 value, uint256 eta) external onlyOwner returns (uint256) {
        require(eta >= block.timestamp + MIN_DELAY, "Delay too short");
        require(eta <= block.timestamp + MAX_DELAY, "Delay too long");

        uint256 id = ++proposalId;
        transactions[id].target = target;
        transactions[id].data = data;
        transactions[id].value = value;
        transactions[id].eta = eta;
        transactions[id].executed = false;
        transactions[id].confirmations = 0;
        emit Queued(id, target, eta);
        return id;
    }

    /// @notice Confirm transaction (multi-sig)
    function confirmTransaction(uint256 id) external {
        require(signers[msg.sender], "Not a signer");
        require(!transactions[id].executed, "Already executed");
        require(!transactions[id].confirmedBy[msg.sender], "Already confirmed");
        transactions[id].confirmations += 1;
        transactions[id].confirmedBy[msg.sender] = true;
        emit Confirmed(id, msg.sender);
    }

    /// @notice Execute transaction (requires multi-sig)
    function executeTransaction(uint256 id) external payable onlyOwner {
        Transaction storage tx = transactions[id];
        require(!tx.executed, "Already executed");
        require(tx.confirmations >= minSignatures, "Not enough confirmations");
        require(block.timestamp >= tx.eta, "Not ready");
        tx.executed = true;

        (bool success,) = tx.target.call{value: tx.value}(tx.data);
        require(success, "Execution failed");
        emit Executed(id);
    }

    function isConfirmed(uint256 id, address signer) external view returns (bool) {
        return transactions[id].confirmedBy[signer];
    }
}
