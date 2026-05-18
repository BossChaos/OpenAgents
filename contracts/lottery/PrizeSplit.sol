// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PrizeSplit
/// @notice Prize distribution with reentrancy protection, zero-winner guard, rounding
/// @dev Fixes: CEI pattern, zero-winner check, dust remainder handling
contract PrizeSplit {
    address public admin;
    uint256 public totalPrize;
    uint256 public roundId;

    struct Round {
        address[] winners;
        uint256 prizePool;
        bool finalized;
        mapping(address => uint256) shares;
        mapping(address => bool) claimed;
        // FIX: Track total dust remainder for manual claiming
        uint256 dust;
    }

    mapping(uint256 => Round) internal rounds;

    event RoundFunded(uint256 indexed roundId, uint256 amount);
    event RoundFinalized(uint256 indexed roundId, uint256 winnerCount, uint256 dustWei);
    event PrizeClaimed(address indexed winner, uint256 amount, uint256 indexed roundId);
    event DustClaimed(uint256 indexed roundId, uint256 dustWei);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function fundRound() external payable onlyAdmin {
        require(msg.value > 0, "No funds");
        roundId++;
        rounds[roundId].prizePool = msg.value;
        totalPrize += msg.value;
        emit RoundFunded(roundId, msg.value);
    }

    function finalizeRound(uint256 _roundId, address[] calldata winners) external onlyAdmin {
        Round storage round = rounds[_roundId];
        require(!round.finalized, "Already finalized");
        require(round.prizePool > 0, "No prize pool");

        // FIX: Zero-winner guard — revert if no winners
        require(winners.length > 0, "No winners specified");

        // FIX: Dust handling — compute remainder, track it separately
        uint256 sharePerWinner = round.prizePool / winners.length;
        uint256 totalDistributed = sharePerWinner * winners.length;
        uint256 dust = round.prizePool - totalDistributed;
        round.dust = dust;

        // FIX: Check for duplicate winners
        for (uint256 i = 0; i < winners.length; i++) {
            require(round.shares[winners[i]] == 0, "Duplicate winner");
            round.winners.push(winners[i]);
            round.shares[winners[i]] = sharePerWinner;
        }

        round.finalized = true;
        emit RoundFinalized(_roundId, winners.length, dust);
    }

    function claimPrize(uint256 _roundId) external nonReentrant {
        Round storage round = rounds[_roundId];
        require(round.finalized, "Not finalized");
        require(round.shares[msg.sender] > 0, "No share");
        require(!round.claimed[msg.sender], "Already claimed");

        // FIX: Mark claimed BEFORE external call (CEI pattern)
        round.claimed[msg.sender] = true;

        uint256 amount = round.shares[msg.sender];

        // FIX: Reentrancy guard on external call
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Transfer failed");

        emit PrizeClaimed(msg.sender, amount, _roundId);
    }

    // FIX: Allow admin to claim accumulated dust after all winners have claimed
    function claimDust(uint256 _roundId) external onlyAdmin {
        Round storage round = rounds[_roundId];
        require(round.finalized, "Not finalized");
        require(round.dust > 0, "No dust");

        // Check if all winners have claimed
        uint256 claimed = 0;
        for (uint256 i = 0; i < round.winners.length; i++) {
            if (round.claimed[round.winners[i]]) claimed++;
        }
        require(claimed == round.winners.length, "Not all claimed");

        uint256 dustAmount = round.dust;
        round.dust = 0;

        (bool sent, ) = payable(admin).call{value: dustAmount}("");
        require(sent, "Dust transfer failed");

        emit DustClaimed(_roundId, dustAmount);
    }

    function getShare(uint256 _roundId, address winner) external view returns (uint256) {
        return rounds[_roundId].shares[winner];
    }

    function isClaimed(uint256 _roundId, address winner) external view returns (bool) {
        return rounds[_roundId].claimed[winner];
    }

    // FIX: View function for round status
    function getRoundStatus(uint256 _roundId) external view returns (
        uint256 prizePool,
        uint256 winnerCount,
        bool finalized,
        uint256 dust
    ) {
        Round storage round = rounds[_roundId];
        return (round.prizePool, round.winners.length, round.finalized, round.dust);
    }
}

/// @notice Reentrancy guard (minimal implementation)
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}
