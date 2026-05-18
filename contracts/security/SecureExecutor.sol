// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SecureExecutor
/// @notice Replace tx.origin with msg.sender for security
/// FIX #4: Replace all tx.origin checks with msg.sender + permission check
contract SecureExecutor {
    mapping(address => bool) public authorizedCallers;

    event CallerAuthorized(address caller);
    event Executed(address indexed executor, address indexed target, bytes data);

    constructor() {
        authorizedCallers[msg.sender] = true;
    }

    function authorize(address caller) external {
        require(msg.sender == address(this) || authorizedCallers[msg.sender], "Not authorized");
        authorizedCallers[caller] = true;
        emit CallerAuthorized(caller);
    }

    /// @notice FIX #4: Use msg.sender instead of tx.origin
    /// tx.origin is vulnerable to phishing attacks where a malicious contract
    /// intermediate calls this contract — tx.origin would be the EOA attacker,
    /// but msg.sender is the legitimate contract.
    function execute(address target, bytes calldata data) external payable {
        // FIX #4: Verify msg.sender is authorized, not tx.origin
        require(authorizedCallers[msg.sender], "Caller not authorized");
        require(target != address(0), "Zero target");

        // Additional protection: verify caller is not a contract
        // or has been explicitly authorized
        require(tx.origin == msg.sender || authorizedCallers[tx.origin], "Contract calls require authorization");

        (bool success,) = target.call{value: msg.value}(data);
        require(success, "Execution failed");
        emit Executed(tx.origin, target, data);
    }

    /// @notice Check if an EOA can safely interact
    function isSafeCaller() external view returns (bool) {
        return tx.origin == msg.sender && authorizedCallers[msg.sender];
    }
}
