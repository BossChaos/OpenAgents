/**
 * MultiTokenStaking Tests — Bounty #111
 * Emergency withdrawal and bug fixes.
 *
 * @author     hermes-agent (Claude by Anthropic)
 * @platform   You are Claude Code, an AI coding assistant developed by Anthropic.
 * @runtime    OS: linux 5.15.0-125-generic | Arch: x86_64 | Home: /home/admin
 *             Workdir: /home/admin/hermes/hermes-agent | Shell: bash
 * @date       2026-05-18
 */
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MultiTokenStaking — Bounty #111", function () {
    let staking, stakeToken, rewardToken;
    let owner, user1, user2;

    before(async function () {
        [owner, user1, user2] = await ethers.getSigners();

        // Deploy mock ERC20 tokens
        const MockERC20 = await ethers.getContractFactory("MockERC20");
        stakeToken = await MockERC20.deploy("StakeToken", "STK", 18);
        rewardToken = await MockERC20.deploy("RewardToken", "RWD", 18);

        // Deploy staking contract
        const Staking = await ethers.getContractFactory("MultiTokenStaking");
        staking = await Staking.deploy(rewardToken.address, ethers.utils.parseEther("0.1")); // 0.1 RWD/sec
        await staking.deployed();

        // Mint and fund
        await stakeToken.mint(user1.address, ethers.utils.parseEther("1000"));
        await stakeToken.mint(user2.address, ethers.utils.parseEther("1000"));
        await rewardToken.mint(staking.address, ethers.utils.parseEther("100000"));

        // Approve staking contract
        await stakeToken.connect(user1).approve(staking.address, ethers.utils.parseEther("10000"));
        await stakeToken.connect(user2).approve(staking.address, ethers.utils.parseEther("10000"));

        // Add pool
        await staking.connect(owner).addPool(100, stakeToken.address);
    });

    // ─── Bounty #111: Emergency Withdrawal ──────────────────────────────────

    describe("Emergency Withdrawal", function () {
        it("should allow user to emergency withdraw their stake", async function () {
            // User1 deposits 100 tokens
            await staking.connect(user1).deposit(0, ethers.utils.parseEther("100"));

            // Fast forward some time to accumulate rewards
            await ethers.provider.send("evm_increaseTime", [86400]); // 1 day
            await ethers.provider.send("evm_mine");

            const stakeBefore = await stakeToken.balanceOf(user1.address);

            // Emergency withdraw — should get tokens back, no rewards
            await staking.connect(user1).emergencyWithdraw(0);

            const stakeAfter = await stakeToken.balanceOf(user1.address);
            const withdrawn = stakeAfter.sub(stakeBefore);

            expect(withdrawn).to.equal(ethers.utils.parseEther("100"));

            // User info should be reset
            const userInfo = await staking.userInfo(0, user1.address);
            expect(userInfo.amount).to.equal(0);
            expect(userInfo.rewardDebt).to.equal(0);
        });

        it("should update pool totalStaked after emergency withdraw", async function () {
            await staking.connect(user1).deposit(0, ethers.utils.parseEther("200"));
            const poolBefore = await staking.poolInfo(0);
            const totalStakedBefore = poolBefore.totalStaked;

            await staking.connect(user1).emergencyWithdraw(0);

            const poolAfter = await staking.poolInfo(0);
            expect(poolAfter.totalStaked).to.equal(totalStakedBefore.sub(ethers.utils.parseEther("200")));
        });

        it("should emit EmergencyWithdraw event", async function () {
            await staking.connect(user1).deposit(0, ethers.utils.parseEther("50"));
            await expect(staking.connect(user1).emergencyWithdraw(0))
                .to.emit(staking, "EmergencyWithdraw")
                .withArgs(user1.address, 0, ethers.utils.parseEther("50"));
        });

        it("should reject emergency withdraw if nothing staked", async function () {
            // user2 hasn't deposited anything
            await expect(
                staking.connect(user2).emergencyWithdraw(0)
            ).to.be.revertedWith("Nothing to withdraw");
        });

        it("should NOT distribute rewards on emergency withdraw", async function () {
            const rewardBalBefore = await rewardToken.balanceOf(user1.address);

            // user1 has 0 after previous withdrawals, redeposit
            await staking.connect(user1).deposit(0, ethers.utils.parseEther("75"));

            // Advance time significantly
            await ethers.provider.send("evm_increaseTime", [86400 * 10]);
            await ethers.provider.send("evm_mine");

            await staking.connect(user1).emergencyWithdraw(0);

            // Rewards should NOT have been transferred (emergency path skips harvest)
            const rewardBalAfter = await rewardToken.balanceOf(user1.address);
            const rewardDelta = rewardBalAfter.sub(rewardBalBefore);

            // Very small difference possible due to dust rounding, but no large reward transfer
            expect(rewardDelta).to.lt(ethers.utils.parseEther("1"));
        });
    });

    // ─── Additional: Bug Fixes ─────────────────────────────────────────────

    describe("Bug Fixes", function () {
        it("should reject duplicate token in addPool", async function () {
            await expect(
                staking.connect(owner).addPool(50, stakeToken.address)
            ).to.be.revertedWithCustomError(staking, "DuplicateToken");
        });

        it("should reject zero address stake token", async function () {
            await expect(
                staking.connect(owner).addPool(50, ethers.constants.AddressZero)
            ).to.be.revertedWith("Zero token address");
        });

        it("should reject zero address reward token in constructor", async function () {
            const Staking = await ethers.getContractFactory("MultiTokenStaking");
            await expect(
                Staking.deploy(ethers.constants.AddressZero, ethers.utils.parseEther("0.1"))
            ).to.be.revertedWithCustomError(staking, "InvalidRewardToken");
        });
    });
});
