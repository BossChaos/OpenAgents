/**
 * NFTMarketplace Tests — Bounty #18
 * Front-run protection, zero-price rejection, ERC-2981 royalties, expiry.
 *
 * @author     hermes-agent (Claude by Anthropic)
 * @platform   You are Claude Code, an AI coding assistant developed by Anthropic.
 * @runtime    OS: linux 5.15.0-125-generic | Arch: x86_64 | Home: /home/admin
 *             Workdir: /home/admin/hermes/hermes-agent | Shell: bash
 * @date       2026-05-18
 */
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { mine, time } = require("@nomicfoundation/hardhat-network-helpers");

describe("NFTMarketplace — Bounty #18", function () {
    let marketplace, mockNFT, mockNFTWithRoyalty;
    let owner, seller, buyer;
    const PLATFORM_FEE_BPS = 250; // 2.5%
    const LISTING_DURATION = 7 * 24 * 60 * 60; // 7 days

    before(async function () {
        [owner, seller, buyer] = await ethers.getSigners();

        // Deploy mock ERC721
        const MockNFT = await ethers.getContractFactory("MockERC721");
        mockNFT = await MockNFT.deploy();
        await mockNFT.deployed();

        // Deploy mock ERC721 with royalties
        const MockNFTWithRoyalty = await ethers.getContractFactory("MockERC721WithRoyalty");
        mockNFTWithRoyalty = await MockNFTWithRoyalty.deploy();
        await mockNFTWithRoyalty.deployed();

        // Deploy marketplace
        const Marketplace = await ethers.getContractFactory("NFTMarketplace");
        marketplace = await Marketplace.deploy(PLATFORM_FEE_BPS, owner.address);
        await marketplace.deployed();

        // Mint NFT to seller and approve marketplace
        await mockNFT.connect(seller).mint(seller.address, 1);
        await mockNFT.connect(seller).approve(marketplace.address, 1);
    });

    // ─── Acceptance Criteria 1: Zero price rejected ─────────────────────────

    describe("Zero Price Rejection", function () {
        it("should reject listing with price = 0", async function () {
            await expect(
                marketplace.connect(seller).listNFT(mockNFT.address, 1, 0, LISTING_DURATION)
            ).to.be.revertedWithCustomError(marketplace, "ZeroPrice");
        });

        it("should accept listing with price > 0", async function () {
            const tx = await marketplace.connect(seller).listNFT(
                mockNFT.address, 1, ethers.utils.parseEther("1"), LISTING_DURATION
            );
            const receipt = await tx.wait();
            const event = receipt.events.find(e => e.event === "Listed");
            expect(event).to.not.be.undefined;
            expect(event.args.price).to.equal(ethers.utils.parseEther("1"));
        });
    });

    // ─── Acceptance Criteria 2: Expired listings blocked ───────────────────

    describe("Listing Expiry", function () {
        it("should reject buying an expired listing", async function () {
            // List with 1 second duration
            await mockNFT.connect(seller).mint(seller.address, 42);
            await mockNFT.connect(seller).approve(marketplace.address, 42);
            await marketplace.connect(seller).listNFT(
                mockNFT.address, 42, ethers.utils.parseEther("1"), 1 // 1 second
            );

            // Wait for expiry
            await time.increase(2);

            await expect(
                marketplace.connect(buyer).buyNFT(1, { value: ethers.utils.parseEther("1") })
            ).to.be.revertedWithCustomError(marketplace, "ListingExpired");
        });

        it("should allow buying before expiry", async function () {
            // Active listing from previous test (ID 1 was re-listed or still active)
            const listingId = await _getLatestListingId();
            await marketplace.connect(buyer).buyNFT(listingId, { value: ethers.utils.parseEther("1") });
            const listing = await marketplace.getListing(listingId);
            expect(listing.active).to.equal(false);
        });
    });

    // ─── Acceptance Criteria 3: Front-run prevented via commit-reveal ─────

    describe("Front-Run Prevention (Commit-Reveal Cancel)", function () {
        it("should allow seller to commit a cancel", async function () {
            // Mint new NFT
            await mockNFT.connect(seller).mint(seller.address, 99);
            await mockNFT.connect(seller).approve(marketplace.address, 99);
            const tx = await marketplace.connect(seller).listNFT(
                mockNFT.address, 99, ethers.utils.parseEther("2"), LISTING_DURATION
            );
            const receipt = await tx.wait();
            const event = receipt.events.find(e => e.event === "Listed");
            const listingId = event.args.listingId;

            // Commit cancel with a hash
            const secret = 12345;
            const commitHash = ethers.utils.keccak256(
                ethers.utils.defaultAbiCoder.encode(["uint256", "uint256"], [listingId, secret])
            );
            await marketplace.connect(seller).commitCancel(listingId, commitHash);

            const listing = await marketplace.getListing(listingId);
            expect(listing.cancelCommit).to.equal(commitHash);
        });

        it("should prevent cancel reveal before delay", async function () {
            const listingId = await _getLatestListingId();
            await expect(
                marketplace.connect(seller).revealCancel(listingId, 12345)
            ).to.be.revertedWithCustomError(marketplace, "CancelNotReady");
        });

        it("should execute cancel after delay and reveal", async function () {
            const listingId = await _getLatestListingId();

            // Wait past the cancel delay
            const listing = await marketplace.getListing(listingId);
            const delay = await marketplace.CANCEL_DELAY();
            await time.increase(delay.toNumber() + 1);

            // Reveal with wrong secret should fail
            await expect(
                marketplace.connect(seller).revealCancel(listingId, 99999)
            ).to.be.revertedWithCustomError(marketplace, "CancelCommitMismatch");

            // Reveal with correct secret
            await marketplace.connect(seller).revealCancel(listingId, 12345);

            const updatedListing = await marketplace.getListing(listingId);
            expect(updatedListing.active).to.equal(false);
        });

        it("should still allow direct cancelListing (no commit-reveal)", async function () {
            await mockNFT.connect(seller).mint(seller.address, 77);
            await mockNFT.connect(seller).approve(marketplace.address, 77);
            const tx = await marketplace.connect(seller).listNFT(
                mockNFT.address, 77, ethers.utils.parseEther("1"), LISTING_DURATION
            );
            const receipt = await tx.wait();
            const event = receipt.events.find(e => e.event === "Listed");
            const listingId = event.args.listingId;

            await marketplace.connect(seller).cancelListing(listingId);
            const listing = await marketplace.getListing(listingId);
            expect(listing.active).to.equal(false);
        });
    });

    // ─── Acceptance Criteria 4: Royalties paid (ERC-2981) ─────────────────

    describe("ERC-2981 Royalties", function () {
        it("should pay royalties on purchase of royalty-bearing NFT", async function () {
            // Mint NFT with royalties
            await mockNFTWithRoyalty.connect(seller).mint(seller.address, 1, owner.address, 1000); // 10% royalty
            await mockNFTWithRoyalty.connect(seller).approve(marketplace.address, 1);

            const tx = await marketplace.connect(seller).listNFT(
                mockNFTWithRoyalty.address, 1, ethers.utils.parseEther("1"), LISTING_DURATION
            );
            const receipt = await tx.wait();
            const event = receipt.events.find(e => e.event === "Listed");
            const listingId = event.args.listingId;

            const ownerBalanceBefore = await owner.getBalance();

            await marketplace.connect(buyer).buyNFT(listingId, { value: ethers.utils.parseEther("1") });

            const listing = await marketplace.getListing(listingId);
            expect(listing.active).to.equal(false);

            // Royalties were paid (owner received fee + royalty)
            const ownerBalanceAfter = await owner.getBalance();
            // Platform fee (2.5%) + royalty (10% of remaining 97.5%) = 2.5 + 9.75 = 12.25%
            // = 0.1225 ETH
            const expectedMin = ethers.utils.parseEther("0.12");
            expect(ownerBalanceAfter.sub(ownerBalanceBefore)).to.be.gte(expectedMin);
        });
    });

    // ─── Helper ─────────────────────────────────────────────────────────────

    async function _getLatestListingId() {
        const filter = marketplace.filters.Listed();
        const events = await marketplace.queryFilter(filter);
        const last = events[events.length - 1];
        return last.args.listingId;
    }
});
