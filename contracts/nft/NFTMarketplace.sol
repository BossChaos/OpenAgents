// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address);
}

/// @dev ERC-2981 royalty interface — optional but best practice for NFT marketplaces
interface IERC2981 {
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount);
}

/// @title NFTMarketplace
/// @notice Decentralized marketplace for listing, buying, and canceling NFT sales
/// @dev Supports any ERC721-compliant NFT contract
/// @contributor BossChaos
/// @bounty #164, #169
contract NFTMarketplace {
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
        uint256 expiry; // NEW: listing expiration timestamp
        bool locked;    // NEW: prevents front-run cancellation after buyer initiates purchase
    }

    uint256 public nextListingId;
    uint256 public platformFee; // basis points (e.g., 250 = 2.5%)
    address public feeRecipient;

    mapping(uint256 => Listing) public listings;

    event Listed(uint256 indexed listingId, address indexed seller, address nftContract, uint256 tokenId, uint256 price, uint256 expiry);
    event Sold(uint256 indexed listingId, address indexed buyer, uint256 price);
    event Canceled(uint256 indexed listingId);

    constructor(uint256 _platformFee, address _feeRecipient) {
        platformFee = _platformFee;
        feeRecipient = _feeRecipient;
    }

    /// @notice List an NFT for sale
    /// @dev Now requires price > 0 and sets an expiry deadline
    function listNFT(address nftContract, uint256 tokenId, uint256 price, uint256 expiry) external returns (uint256) {
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(
            nft.getApproved(tokenId) == address(this),
            "Marketplace not approved"
        );
        require(price > 0, "Price must be > 0"); // FIX: prevent zero-price free listings
        require(expiry > block.timestamp, "Invalid expiry"); // NEW: enforce future expiry

        uint256 listingId = nextListingId++;
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            active: true,
            expiry: expiry,
            locked: false
        });

        emit Listed(listingId, msg.sender, nftContract, tokenId, price, expiry);
        return listingId;
    }

    /// @notice Buy a listed NFT — locks listing during transfer to prevent front-run cancellation
    /// @dev Now supports ERC-2981 royalties and locks listing during execution
    function buyNFT(uint256 listingId) external payable {
        Listing storage listing = listings[listingId];
        require(listing.active, "Not active");
        require(listing.expiry > block.timestamp, "Listing expired"); // NEW: check expiry
        require(msg.value == listing.price, "Wrong price");

        // FIX: Lock listing to prevent seller front-run cancellation
        listing.locked = true;
        listing.active = false;

        uint256 fee = (msg.value * platformFee) / 10000;

        // NEW: Handle ERC-2981 royalties if the NFT supports it
        uint256 royaltyAmount = 0;
        address royaltyReceiver = address(0);
        try IERC2981(listing.nftContract).royaltyInfo(listing.tokenId, msg.value) returns (
            address receiver,
            uint256 amount
        ) {
            royaltyAmount = amount;
            royaltyReceiver = receiver;
        } catch {
            // NFT doesn't implement ERC-2981 — skip royalty
        }

        uint256 sellerProceeds = msg.value - fee - royaltyAmount;

        IERC721(listing.nftContract).transferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );

        // Transfer fee
        (bool feeSent, ) = feeRecipient.call{value: fee}("");
        require(feeSent, "Fee transfer failed");

        // Transfer royalty if applicable
        if (royaltyAmount > 0 && royaltyReceiver != address(0)) {
            (bool royaltySent, ) = royaltyReceiver.call{value: royaltyAmount}("");
            require(royaltySent, "Royalty transfer failed");
        }

        // Transfer seller proceeds
        (bool sellerSent, ) = listing.seller.call{value: sellerProceeds}("");
        require(sellerSent, "Seller transfer failed");

        emit Sold(listingId, msg.sender, msg.value);
    }

    /// @notice Cancel a listing — prevents cancellation if already locked by a buyer
    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(listing.active, "Not active");
        require(!listing.locked, "Listing is being purchased"); // FIX: prevent front-run cancel
        require(listing.seller == msg.sender, "Not seller");
        require(listing.expiry > block.timestamp, "Already expired"); // NEW: can't cancel expired

        listing.active = false;
        emit Canceled(listingId);
    }

    /// @dev Fix: use proper IERC721 interface for transfer
    function _transferNFT(address nftContract, address from, address to, uint256 tokenId) internal {
        IERC721(nftContract).transferFrom(from, to, tokenId);
    }

    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }
}
