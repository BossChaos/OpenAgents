// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title RandomLottery
/// @notice On-chain lottery using block.prevrandao for randomness
/// @dev Players buy tickets, and a random winner is selected after the round ends
contract RandomLottery {
    address public owner;
    uint256 public ticketPrice;
    uint256 public roundEnd;
    uint256 public currentRound;

    address[] public players;
    mapping(uint256 => address) public roundWinners;

    // FIX: Add minimum participants requirement
    uint256 public constant MIN_PLAYERS = 3;

    event TicketPurchased(address indexed player, uint256 round);
    event RoundStarted(uint256 indexed round, uint256 endTime);
    event WinnerSelected(address indexed winner, uint256 prize, uint256 round);
    event Refunded(address indexed player, uint256 amount, uint256 round);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint256 _ticketPrice) {
        owner = msg.sender;
        ticketPrice = _ticketPrice;
    }

    function startRound(uint256 duration) external onlyOwner {
        require(roundEnd == 0 || block.timestamp > roundEnd, "Round active");
        delete players;
        currentRound++;
        roundEnd = block.timestamp + duration;
        emit RoundStarted(currentRound, roundEnd);
    }

    function buyTicket() external payable {
        require(block.timestamp < roundEnd, "Round ended");
        require(msg.value == ticketPrice, "Wrong ticket price");
        players.push(msg.sender);
        emit TicketPurchased(msg.sender, currentRound);
    }

    function drawWinner() external onlyOwner {
        require(block.timestamp >= roundEnd, "Round not ended");
        // FIX: Require minimum players to proceed with draw
        require(players.length >= MIN_PLAYERS, "Not enough players");

        uint256 randomIndex = uint256(
            keccak256(abi.encodePacked(block.prevrandao, block.timestamp))
        ) % players.length;

        address winner = players[randomIndex];
        roundWinners[currentRound] = currentRound;

        uint256 prize = address(this).balance;
        roundEnd = 0;

        // FIX: Use call with gas limit and handle failure gracefully
        (bool sent, ) = winner.call{value: prize, gas: 50000}("");
        require(sent, "Transfer failed");

        emit WinnerSelected(winner, prize, currentRound);
    }

    // FIX: Add refund mechanism for rounds with insufficient players
    function refund() external {
        require(block.timestamp >= roundEnd, "Round not ended");
        require(players.length > 0 && players.length < MIN_PLAYERS, "Cannot refund");

        // Calculate player's share
        uint256 ticketCount = 0;
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == msg.sender) {
                ticketCount++;
            }
        }
        require(ticketCount > 0, "No tickets purchased by caller");

        uint256 refundAmount = ticketCount * ticketPrice;
        roundEnd = 0; // Reset round so it can be restarted

        (bool sent, ) = msg.sender.call{value: refundAmount, gas: 50000}("");
        require(sent, "Refund failed");

        emit Refunded(msg.sender, refundAmount, currentRound);
    }

    function getPlayers() external view returns (address[] memory) {
        return players;
    }

    function getPoolSize() external view returns (uint256) {
        return address(this).balance;
    }
}
