// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title BridgeValidator
/// @notice Validator management for cross-chain bridge
/// FIX #61: Prevent validators from self-adding
contract BridgeValidator is Ownable {
    mapping(address => bool) public validators;
    address[] public validatorList;
    uint256 public requiredConfirmations;

    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event ConfirmationRequired(uint256 newRequired);

    constructor(uint256 _requiredConfirmations) Ownable(msg.sender) {
        require(_requiredConfirmations > 0, "Zero confirmations");
        requiredConfirmations = _requiredConfirmations;
    }

    /// @notice Add a new validator (owner only)
    /// FIX #61: Only owner can add validators
    function addValidator(address validator) external onlyOwner {
        require(validator != address(0), "Zero address");
        require(!validators[validator], "Already validator");

        validators[validator] = true;
        validatorList.push(validator);
        emit ValidatorAdded(validator);
    }

    /// @notice Remove a validator (owner only)
    function removeValidator(address validator) external onlyOwner {
        require(validators[validator], "Not validator");

        validators[validator] = false;
        for (uint256 i = 0; i < validatorList.length; i++) {
            if (validatorList[i] == validator) {
                validatorList[i] = validatorList[validatorList.length - 1];
                validatorList.pop();
                break;
            }
        }
        emit ValidatorRemoved(validator);
    }

    function setRequiredConfirmations(uint256 _required) external onlyOwner {
        require(_required > 0 && _required <= validatorList.length, "Invalid count");
        requiredConfirmations = _required;
        emit ConfirmationRequired(_required);
    }

    function getValidatorCount() external view returns (uint256) {
        return validatorList.length;
    }

    function isValidValidator(address addr) external view returns (bool) {
        return validators[addr];
    }
}
