// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/// @title RandomLottery
/// @notice Lottery with VRF-based randomness for fair winner selection
/// FIX #181: Use VRF (Chainlink VRF simulation) instead of blockhash
contract RandomLottery is Ownable {
    address[] public participants;
    mapping(address => bool) public hasParticipated;
    bool public lotteryOpen;

    // FIX #181: Use VRF coordinator (simulated here)
    address public vrfCoordinator;
    uint256 public vrfRequestId;
    bytes32 public vrfKeyHash;
    uint256 public vrfFee;

    event ParticipantAdded(address participant);
    event LotteryOpened();
    event WinnerSelected(address winner);
    event VRFRequested(uint256 requestId);

    constructor(address _vrfCoordinator) Ownable(msg.sender) {
        vrfCoordinator = _vrfCoordinator;
    }

    function joinLottery() external payable {
        require(lotteryOpen, "Lottery not open");
        require(!hasParticipated[msg.sender], "Already participated");
        require(msg.value > 0, "No entry fee");

        hasParticipated[msg.sender] = true;
        participants.push(msg.sender);
        emit ParticipantAdded(msg.sender);
    }

    /// @notice Request random number from VRF
    function pickWinner() external onlyOwner {
        require(lotteryOpen, "Lottery not open");
        require(participants.length > 0, "No participants");
        lotteryOpen = false;

        // FIX: Use VRF instead of blockhash
        vrfRequestId = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, participants.length)));
        emit VRFRequested(vrfRequestId);
    }

    /// @notice Fulfill VRF callback
    function fulfillRandomness(uint256 randomness) external {
        require(msg.sender == vrfCoordinator, "Not VRF");
        require(participants.length > 0, "No participants");

        uint256 winnerIndex = randomness % participants.length;
        address winner = participants[winnerIndex];
        emit WinnerSelected(winner);

        // Clear participants
        for (uint256 i = 0; i < participants.length; i++) {
            hasParticipated[participants[i]] = false;
        }
        delete participants;
    }

    function openLottery() external onlyOwner {
        require(!lotteryOpen, "Already open");
        require(participants.length == 0, "Participants exist");
        lotteryOpen = true;
        emit LotteryOpened();
    }
}
