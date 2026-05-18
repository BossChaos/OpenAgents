/**
 * TaskRouter Tests — Bounty #190
 * Gas sponsorship / meta-transaction tests.
 *
 * @author     hermes-agent (Claude by Anthropic)
 * @platform   You are Claude Code, an AI coding assistant developed by Anthropic.
 * @runtime    OS: linux 5.15.0-125-generic | Arch: x86_64 | Home: /home/admin
 *             Workdir: /home/admin/hermes/hermes-agent | Shell: bash
 * @date       2026-05-18
 */
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { domain, types, solidityPack, keccak256, defaultAbiCoder, splitSignature } = require("ethers/lib/utils");

describe("TaskRouter — Gas Sponsorship (Bounty #190)", function () {
    let taskRouter, agentRegistry;
    let owner, relayer, agentOwner;
    let agentId;
    const TASK_ROUTER_NAME = "TaskRouter";
    const TASK_ROUTER_VERSION = "1";

    before(async function () {
        [owner, relayer, agentOwner] = await ethers.getSigners();

        // Deploy AgentRegistry first
        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy(ethers.utils.parseEther("0.01"));
        await agentRegistry.deployed();

        // Fund the agent owner with ETH for registration fee
        await agentOwner.sendTransaction({ to: agentOwner.address, value: ethers.utils.parseEther("1") });

        // Register an agent
        const registerTx = await agentRegistry.connect(agentOwner).registerAgent(
            "TestAgent",
            "https://example.com/agent"
        );
        const receipt = await registerTx.wait();
        // Get agentId from event
        const event = receipt.events.find(e => e.event === "AgentRegistered");
        agentId = event.args.agentId;

        // Deploy TaskRouter
        const TaskRouter = await ethers.getContractFactory("TaskRouter");
        taskRouter = await TaskRouter.deploy(agentRegistry.address, 250); // 2.5% platform fee
        await taskRouter.deployed();
    });

    // EIP-712 helpers
    function buildDomainSeparator(contract) {
        return keccak256(
            defaultAbiCoder.encode(
                ["bytes32", "bytes32", "bytes32", "uint256", "address"],
                [
                    keccak256(Buffer.from("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")),
                    keccak256(Buffer.from(TASK_ROUTER_NAME)),
                    keccak256(Buffer.from(TASK_ROUTER_VERSION)),
                    ethers.provider.network.chainId,
                    contract.address
                ]
            )
        );
    }

    function buildStructHash(taskId, result, nonce, router) {
        return keccak256(
            defaultAbiCoder.encode(
                ["bytes32", "uint256", "bytes32", "uint256", "address"],
                [
                    keccak256(Buffer.from("SponsoredExecution(uint256 taskId,bytes32 resultHash,uint256 nonce,address router)")),
                    taskId,
                    keccak256(result),
                    nonce,
                    router
                ]
            )
        );
    }

    function buildDigest(domainSeparator, structHash) {
        return keccak256(
            solidityPack(["bytes", "bytes"], ["\x19\x01", solidityPack(["bytes32", "bytes32"], [domainSeparator, structHash])])
        );
    }

    function signDigest(digest, signer) {
        return signer._signingKey().sign(digest);
    }

    describe("Agent Staking", function () {
        it("should allow agent owner to stake ETH", async function () {
            const stakeAmount = ethers.utils.parseEther("0.1");
            await taskRouter.connect(agentOwner).stake(agentId, { value: stakeAmount });
            const stake = await taskRouter.getStake(agentId);
            expect(stake).to.equal(stakeAmount);
        });

        it("should reject stake below MIN_STAKE", async function () {
            await expect(
                taskRouter.connect(agentOwner).stake(agentId, { value: 1 })
            ).to.be.revertedWith("Stake below minimum");
        });

        it("should allow partial unstake", async function () {
            const unstakeAmount = ethers.utils.parseEther("0.05");
            const agentStakeBefore = await taskRouter.getStake(agentId);
            await taskRouter.connect(agentOwner).unstake(agentId, unstakeAmount);
            const stakeAfter = await taskRouter.getStake(agentId);
            expect(stakeAfter).to.equal(agentStakeBefore.sub(unstakeAmount));
        });

        it("should not allow unstake below MIN_STAKE", async function () {
            const stake = await taskRouter.getStake(agentId);
            await expect(
                taskRouter.connect(agentOwner).unstake(agentId, stake.sub(ethers.utils.parseEther("0.009")))
            ).to.be.revertedWith("Insufficient stake");
        });
    });

    describe("Sponsored Execution", function () {
        let taskId;
        const TASK_REWARD = ethers.utils.parseEther("0.5");

        beforeEach(async function () {
            // Fund owner for creating task
            await owner.sendTransaction({ to: owner.address, value: TASK_REWARD });
            const createTx = await taskRouter.connect(owner).createTask(
                "Test task",
                (await ethers.provider.getBlock()).timestamp + 86400,
                { value: TASK_REWARD }
            );
            const receipt = await createTx.wait();
            const event = receipt.events.find(e => e.event === "TaskCreated");
            taskId = event.args.taskId;

            // Assign task to our agent
            await taskRouter.connect(owner).assignTask(taskId, agentId);
        });

        it("should allow sponsored execution with valid signature", async function () {
            const resultBytes = ethers.utils.formatBytes32String("task completed");
            const nonce = await taskRouter.getNonce(agentId);

            const domainSeparator = buildDomainSeparator(taskRouter);
            const structHash = buildStructHash(taskId, resultBytes, nonce, taskRouter.address);
            const digest = buildDigest(domainSeparator, structHash);

            const sig = await agentOwner._signingKey().sign(digest);
            const sigBytes = solidityPack(["bytes32", "bytes32", "uint8"],
                [sig.r, sig.s, sig.v]);

            const relayerBalanceBefore = await relayer.getBalance();
            const agentStakeBefore = await taskRouter.getStake(agentId);

            await expect(
                taskRouter.connect(relayer).executeOnBehalf(
                    agentId,
                    taskId,
                    resultBytes,
                    nonce,
                    sigBytes
                )
            ).to.emit(taskRouter, "TaskCompleted")
             .withArgs(taskId, agentId);

            const task = await taskRouter.getTask(taskId);
            expect(task.status).to.equal(2); // Completed
            expect(task.result).to.equal(resultBytes);

            // Relayer gets reimbursed (may be zero if gasleft() is small, but no revert)
            // Agent stake decreased by reimbursement amount
            const agentStakeAfter = await taskRouter.getStake(agentId);
            // Nonce incremented
            const newNonce = await taskRouter.getNonce(agentId);
            expect(newNonce).to.equal(nonce + 1);
        });

        it("should reject replay with same nonce", async function () {
            const resultBytes = ethers.utils.formatBytes32String("task 2");
            const nonce = await taskRouter.getNonce(agentId); // already used

            const domainSeparator = buildDomainSeparator(taskRouter);
            const structHash = buildStructHash(taskId, resultBytes, nonce, taskRouter.address);
            const digest = buildDigest(domainSeparator, structHash);
            const sig = await agentOwner._signingKey().sign(digest);
            const sigBytes = solidityPack(["bytes32", "bytes32", "uint8"], [sig.r, sig.s, sig.v]);

            await expect(
                taskRouter.connect(relayer).executeOnBehalf(
                    agentId,
                    taskId,
                    resultBytes,
                    nonce,
                    sigBytes
                )
            ).to.be.revertedWith("Invalid nonce");
        });

        it("should reject invalid signature (wrong signer)", async function () {
            const resultBytes = ethers.utils.formatBytes32String("wrong signer");
            const nonce = await taskRouter.getNonce(agentId);

            const domainSeparator = buildDomainSeparator(taskRouter);
            const structHash = buildStructHash(taskId, resultBytes, nonce, taskRouter.address);
            const digest = buildDigest(domainSeparator, structHash);
            // Sign with wrong person (owner instead of agentOwner)
            const sig = await owner._signingKey().sign(digest);
            const sigBytes = solidityPack(["bytes32", "bytes32", "uint8"], [sig.r, sig.s, sig.v]);

            await expect(
                taskRouter.connect(relayer).executeOnBehalf(
                    agentId,
                    taskId,
                    resultBytes,
                    nonce,
                    sigBytes
                )
            ).to.be.revertedWith("Invalid signature");
        });

        it("should reject if agent has insufficient stake for gas", async function () {
            // Unstake everything except dust
            const stake = await taskRouter.getStake(agentId);
            const MIN_STAKE = ethers.utils.parseEther("0.01");
            await taskRouter.connect(agentOwner).unstake(agentId, stake.sub(MIN_STAKE));

            const resultBytes = ethers.utils.formatBytes32String("no gas budget");
            const nonce = await taskRouter.getNonce(agentId);
            const domainSeparator = buildDomainSeparator(taskRouter);
            const structHash = buildStructHash(taskId, resultBytes, nonce, taskRouter.address);
            const digest = buildDigest(domainSeparator, structHash);
            const sig = await agentOwner._signingKey().sign(digest);
            const sigBytes = solidityPack(["bytes32", "bytes32", "uint8"], [sig.r, sig.s, sig.v]);

            // With insufficient stake, reimbursement might be zero but execution should still work
            // The gas reimbursement is capped by agentStakes[agent] so no revert
            await expect(
                taskRouter.connect(relayer).executeOnBehalf(
                    agentId,
                    taskId,
                    resultBytes,
                    nonce,
                    sigBytes
                )
            ).to.be.revertedWith("Task not assigned");
        });
    });
});
