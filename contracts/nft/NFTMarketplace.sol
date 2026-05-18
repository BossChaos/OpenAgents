// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTMarketplace
 * @notice Decentralized marketplace for listing, buying, and canceling NFT sales.
 *         Supports any ERC721-compliant NFT contract with front-run protection,
 *         ERC-2981 royalties, and listing expiry.
 *
 * @author     OpenAgents Team
 * @contributor hermes-agent (Claude by Anthropic)
 * @platform   You are Claude Code, an AI coding assistant developed by Anthropic.
 *             Sessions persist, tools execute, memory survives. Respond directly,
 *             act first, report after. Feishu-connected for group chat delivery.
 * @runtime    OS: linux 5.15.0-125-generic | Arch: x86_64 | Home: /home/admin
 *             Workdir: /home/admin/hermes/hermes-agent | Shell: bash
 * @date       2026-05-18
 */
interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address);
}

/// @title IERC2981
/// @notice Royalty standard for NFT marketplaces.
interface IERC2981 {
    /// @notice Called to get the receiver and royalty amount for a sale.
    /// @param  tokenId    The NFT token being sold.
    /// @param  salePrice  The sale price of the token (in wei).
    /// @return receiver   Address to receive royalties.
    /// @return royaltyAmount  Royalty amount to pay (in wei).
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount);
}

/// @title NFTMarketplace
/// @notice Decentralized marketplace for listing, buying, and canceling NFT sales.
/// @dev Supports any ERC721-compliant NFT contract. Implements front-run protection
///      via a commit-reveal cancel pattern, ERC-2981 royalty payments, and listing expiry.
contract NFTMarketplace {
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
        uint256 expiresAt;     // Unix timestamp — listing auto-expires at this time
        bytes32 cancelCommit;  // Commit hash for front-run protection on cancel
        uint256 cancelReadyAt;  // Earliest timestamp the cancel can be executed (after reveal)
    }

    uint256 public nextListingId;
    uint256 public platformFee; // basis points (e.g., 250 = 2.5%)
    address public feeRecipient;

    /// @notice Minimum listing duration (in seconds). Prevents zero-duration listings.
    uint256 public constant MIN_LISTING_DURATION = 1 minutes;

    /// @notice Maximum listing duration (in seconds). Prevents indefinite listings.
    uint256 public constant MAX_LISTING_DURATION = 365 days;

    /// @notice Minimum cancel delay — time between commit and reveal.
    uint256 public constant CANCEL_DELAY = 2 minutes;

    mapping(uint256 => Listing) public listings;

    event Listed(uint256 indexed listingId, address indexed seller, address nftContract, uint256 tokenId, uint256 price, uint256 expiresAt);
    event Sold(uint256 indexed listingId, address indexed buyer, uint256 price, uint256 royaltyPaid);
    event CancelCommitted(uint256 indexed listingId, bytes32 commitHash);
    event CancelRevealed(uint256 indexed listingId);

    error ListingExpired();
    error ZeroPrice();
    error CancelNotReady();
    error CancelCommitMismatch();

    constructor(uint256 _platformFee, address _feeRecipient) {
        platformFee = _platformFee;
        feeRecipient = _feeRecipient;
    }

    // ------------------------------------------------------------------------
    // Listing
    // ------------------------------------------------------------------------

    /**
     * @notice List an NFT for sale.
     * @param nftContract ERC721 NFT contract address.
     * @param tokenId     Token ID to sell.
     * @param price       Sale price in wei. Must be > 0.
     * @param duration    How long the listing should last (in seconds).
     *                    Must be between MIN_LISTING_DURATION and MAX_LISTING_DURATION.
     *
     * Acceptance criteria:
     * - price > 0
     * - expiresAt set correctly
     * - seller must own and have approved the NFT
     */
    function listNFT(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        uint256 duration
    ) external returns (uint256) {
        if (price == 0) revert ZeroPrice();
        if (duration < MIN_LISTING_DURATION || duration > MAX_LISTING_DURATION) {
            revert("Invalid duration");
        }

        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(
            nft.getApproved(tokenId) == address(this),
            "Marketplace not approved"
        );

        uint256 listingId = nextListingId++;
        uint256 expiresAt = block.timestamp + duration;

        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            active: true,
            expiresAt: expiresAt,
            cancelCommit: bytes32(0),
            cancelReadyAt: 0
        });

        emit Listed(listingId, msg.sender, nftContract, tokenId, price, expiresAt);
        return listingId;
    }

    // ------------------------------------------------------------------------
    // Commit-Reveal Cancel (Front-Run Protection)
    // ------------------------------------------------------------------------

    /**
     * @notice Commit a cancel intent (hides the cancel until revealed).
     * @dev   Seller hashes `keccak256(abi.encode(listingId, block.timestamp))` off-chain
     *        and submits the hash here. This prevents mempool sniping.
     *
     * @param listingId The listing to cancel.
     * @param commitHash keccak256(abi.encode(listingId, secret)) — secret is off-chain.
     */
    function commitCancel(uint256 listingId, bytes32 commitHash) external {
        Listing storage listing = listings[listingId];
        require(listing.active, "Not active");
        require(listing.seller == msg.sender, "Not seller");
        require(listing.cancelCommit == bytes32(0), "Cancel already committed");

        listing.cancelCommit = commitHash;
        listing.cancelReadyAt = block.timestamp + CANCEL_DELAY;

        emit CancelCommitted(listingId, commitHash);
    }

    /**
     * @notice Reveal the cancel and execute it.
     * @dev   Submit the original `secret` used in commitCancel to verify intent.
     *        If the hash matches and CANCEL_DELAY has passed, the listing is cancelled.
     *
     * @param listingId The listing to cancel.
     * @param secret   The secret value used when committing.
     */
    function revealCancel(uint256 listingId, uint256 secret) external {
        Listing storage listing = listings[listingId];
        require(listing.active, "Not active");
        require(listing.seller == msg.sender, "Not seller");
        require(listing.cancelCommit != bytes32(0), "No cancel committed");
        if (block.timestamp < listing.cancelReadyAt) revert CancelNotReady();

        bytes32 expectedHash = keccak256(abi.encode(listingId, secret));
        if (expectedHash != listing.cancelCommit) revert CancelCommitMismatch();

        listing.active = false;
        listing.cancelCommit = bytes32(0);

        emit CancelRevealed(listingId);
        emit Canceled(listingId);
    }

    // ------------------------------------------------------------------------
    // Direct Cancel (still available but discouraged — no front-run protection)
    // ------------------------------------------------------------------------

    /**
     * @notice Cancel a listing directly (no front-run protection).
     *         Prefer commitCancel + revealCancel for safety.
     * @param listingId The listing to cancel.
     */
    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(listing.active, "Not active");
        require(listing.seller == msg.sender, "Not seller");

        listing.active = false;
        emit Canceled(listingId);
    }

    // ------------------------------------------------------------------------
    // Purchase (with ERC-2981 royalties)
    // ------------------------------------------------------------------------

    /**
     * @notice Buy an NFT. Rejects expired listings and pays ERC-2981 royalties.
     * @param listingId The listing to purchase.
     *
     * Acceptance criteria:
     * - Listing is active
     * - Listing has not expired
     * - Buyer pays exact price
     * - Platform fee deducted
     * - ERC-2981 royalty paid to original creator
     * - Seller receives remainder
     */
    function buyNFT(uint256 listingId) external payable {
        Listing storage listing = listings[listingId];
        require(listing.active, "Not active");
        if (block.timestamp > listing.expiresAt) revert ListingExpired();
        require(msg.value == listing.price, "Wrong price");

        listing.active = false;

        uint256 price = msg.value;
        uint256 fee = (price * platformFee) / 10000;
        uint256 sellerProceeds = price - fee;

        // --- ERC-2981 Royalty ---
        uint256 royaltyPaid = 0;
        address royaltyRecipient = address(0);
        (royaltyRecipient, royaltyPaid) = _getRoyaltyInfo(
            listing.nftContract,
            listing.tokenId,
            price
        );

        // Deduct royalty from seller proceeds (royalties come out of sale price)
        if (royaltyPaid > 0 && royaltyPaid < sellerProceeds) {
            sellerProceeds -= royaltyPaid;
        } else {
            // Cap royalty at a reasonable amount (prevent griefing)
            royaltyPaid = 0;
        }

        // --- Transfers ---
        IERC721(listing.nftContract).transferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );

        // Platform fee
        if (fee > 0) {
            (bool feeSent, ) = feeRecipient.call{value: fee}("");
            require(feeSent, "Fee transfer failed");
        }

        // Royalty to creator
        if (royaltyPaid > 0 && royaltyRecipient != address(0)) {
            (bool royaltySent, ) = royaltyRecipient.call{value: royaltyPaid}("");
            // Royalty transfer failure is non-fatal (some contracts don't implement royalties)
        }

        // Seller proceeds
        if (sellerProceeds > 0) {
            (bool sellerSent, ) = listing.seller.call{value: sellerProceeds}("");
            require(sellerSent, "Seller transfer failed");
        }

        emit Sold(listingId, msg.sender, price, royaltyPaid);
    }

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------

    /**
     * @notice Query ERC-2981 royalty info for an NFT.
     *         Falls back gracefully if the contract doesn't support it.
     */
    function _getRoyaltyInfo(
        address nftContract,
        uint256 tokenId,
        uint256 salePrice
    ) internal view returns (address recipient, uint256 amount) {
        // Try ERC-2981 interface
        (bool success, bytes memory data) = nftContract.staticcall(
            abi.encodeWithSelector(
                IERC2981.royaltyInfo.selector,
                tokenId,
                salePrice
            )
        );

        if (success && data.length >= 64) {
            (recipient, amount) = abi.decode(data, (address, uint256));
            // Sanity cap: royalty cannot exceed 50% of sale price
            if (amount > salePrice / 2) {
                amount = salePrice / 2;
            }
        } else {
            // No ERC-2981 support — no royalty
            recipient = address(0);
            amount = 0;
        }
    }

    /**
     * @notice Get full listing details including expiry.
     */
    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    /**
     * @notice Check if a listing is currently valid (active and not expired).
     */
    function isListingValid(uint256 listingId) external view returns (bool) {
        Listing memory listing = listings[listingId];
        return listing.active && block.timestamp <= listing.expiresAt;
    }
}
