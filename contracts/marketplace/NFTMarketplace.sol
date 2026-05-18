// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title NFTMarketplace
/// @notice NFT marketplace with frontrunning protection
/// FIX #18: Commit-reveal pattern for listings
contract NFTMarketplace is ReentrancyGuard {
    IERC20 public paymentToken;

    struct Listing {
        address seller;
        uint256 price;
        bool active;
        bytes32 commitment;
        uint256 deadline;
    }

    mapping(address => mapping(uint256 => Listing)) public listings;

    event Listed(address seller, uint256 tokenId, uint256 price);
    event Purchase(address buyer, address seller, uint256 tokenId, uint256 price);

    constructor(address _token) {
        paymentToken = IERC20(_token);
    }

    /// @notice Create listing with commit-reveal to prevent frontrunning
    /// FIX #18: Two-phase listing with commitment
    function commitListing(
        uint256 tokenId,
        bytes32 commitment,
        uint256 deadline
    ) external {
        require(deadline > block.timestamp, "Past deadline");
        listings[msg.sender][tokenId] = Listing({
            seller: msg.sender,
            price: 0,
            active: true,
            commitment: commitment,
            deadline: deadline
        });
    }

    /// @notice Reveal listing details
    function revealListing(
        uint256 tokenId,
        uint256 price,
        uint256 nonce
    ) external {
        Listing storage listing = listings[msg.sender][tokenId];
        require(listing.active, "Not active");
        require(block.timestamp <= listing.deadline, "Expired");

        // Verify commitment
        bytes32 expected = keccak256(abi.encodePacked(price, nonce, msg.sender, tokenId));
        require(expected == listing.commitment, "Commitment mismatch");

        listing.price = price;
        emit Listed(msg.sender, tokenId, price);
    }

    /// @notice Purchase an NFT
    function purchase(address seller, uint256 tokenId) external nonReentrant {
        Listing storage listing = listings[seller][tokenId];
        require(listing.active && listing.price > 0, "Not for sale");

        paymentToken.safeTransferFrom(msg.sender, seller, listing.price);
        listing.active = false;

        emit Purchase(msg.sender, seller, tokenId, listing.price);
    }
}
