const { assert } = require('chai');
const truffleAssert = require('truffle-assertions');

const BN = require('BN.js');
const RewardManager = artifacts.require('BotCreatorRewardManager');
const VICS = artifacts.require('VICSToken');
const MockContract = artifacts.require("MockContract")

contract('RewardManager', async (accounts) => {
    const admin = accounts[0];
    const alice = accounts[2];
    const bob = accounts[3];
    let vics;
    let rewards;
    let bot;
    let bot2;

    before(async () => {
        vics = await VICS.new(100000000);
        rewards = await RewardManager.new(vics.address);

        bot = await MockContract.new();
        await bot.givenAnyReturnAddress(alice);

        bot2 = await MockContract.new();
        await bot2.givenAnyReturnAddress(bob);

        await vics.transfer(rewards.address, 100000000);
    });

    describe("approve application", function() {
        it("create application (non bot creator)", async function() {
             await truffleAssert.fails(rewards.createApplication(bot.address), message = "RewardManager: caller must be bot creator");
        });

        it("create application (bot creator)", async function() {
            await rewards.createApplication(bot.address, { from: alice });
            let app = await rewards.applicationOf(bot.address);

            assert.equal(app.receiver, alice);
            assert.equal(app.amount, 0);
            assert.equal(app.status, 0);
        });

        it("create application proposal (non approver)", async function() {
            assert.equal(await rewards.isApprover(alice), 0);
            await truffleAssert.fails(rewards.createProposal(bot.address, 100000, { from: alice }), message = "RewardManager: permission denied");
        });

        it("create application proposal (single approval)", async function() {
            assert.equal(await rewards.numApproverPerApplication(), 1);

            await rewards.createProposal(bot.address, 100000);
            let app = await rewards.applicationOf(bot.address);

            assert.equal(app.status, 3);
            assert.equal(await vics.balanceOf(alice), 100000);
        });

        it("re-create approved application", async function() {
            await truffleAssert.fails(rewards.createApplication(bot.address, { from: alice }), message = "RewardManager: application has been processed");
        });

        it("re-propose approved application", async function() {
            let app = await rewards.applicationOf(bot.address);
            assert.equal(app.status, 3);
            await truffleAssert.fails(rewards.createProposal(bot.address, 10000), message = "RewardManager: invalid application status");
        });
    });

    describe("delete/cancel application", function() {
        it("delete application (non owner)", async function() {
            let app = await rewards.applicationOf(bot.address);
            assert.notEqual(app.receiver, 0);

            await truffleAssert.fails(rewards.deleteApplication(bot.address, { from: alice }), message = "Ownable: caller is not the owner");
        });

        it("delete application (owner)", async function() {
            await rewards.deleteApplication(bot.address);

            let app = await rewards.applicationOf(bot.address);
            assert.equal(app.status, 0);
            assert.equal(app.receiver, 0);
            assert.equal(app.amount, 0);
        });

        it("cancel application (bot owner)", async function() {
            await rewards.createApplication(bot.address, { from: alice });
            await rewards.cancelApplication(bot.address, { from: alice });

            let app = await rewards.applicationOf(bot.address);
            assert.equal(app.status, 1);
            assert.equal(app.receiver, alice);
        });

        it("propose canceled application", async function() {
            await truffleAssert.fails(rewards.createProposal(bot.address, 10000), message = "RewardManager: invalid application status");
        });
    });

    describe("appove application (multi-signers)", function() {
        it("add approver (non owner)", async function() {
            await truffleAssert.fails(rewards.updateApprovers([alice], 1, { from: alice }), message = "Ownable: caller is not the owner");
        });

        it("add approver (owner)", async function() {
            await rewards.updateApprovers([bob], 1);
            await rewards.setApproverPerApplication(2);

            assert.equal(await rewards.isApprover(bob), 1);
            assert.equal(await rewards.numApproverPerApplication(), 2);
        });

        it("duplicated approver", async function() {
            await rewards.createApplication(bot.address, { from: alice });
            await rewards.createProposal(bot.address, 100000);
            await truffleAssert.fails(rewards.approveApplication(bot.address), message = "RewardManager: duplicated approver");
        });

        it("approve application (non approver)", async function() {
            await truffleAssert.fails(rewards.approveApplication(bot.address, { from: alice }), message = "RewardManager: permission denied");
        });

        it("approve application (2nd approver)", async function() {
            let balance = (await vics.balanceOf(alice)).add(new BN(100000));
            await rewards.approveApplication(bot.address, { from: bob });

            let app = await rewards.applicationOf(bot.address);
            assert.equal(app.status, 3 /* approved */);
            assert.equal(await vics.balanceOf(alice), balance.toString());
        })
    });

    describe("reject application", function() {
        it("reject application", async function() {
            await rewards.createApplication(bot2.address, { from: bob });

            let app = await rewards.applicationOf(bot2.address);
            assert.equal(app.status, 0 /* new */);
            assert.equal(app.receiver, bob);

            await rewards.rejectApplication(bot2.address);
            app = await rewards.applicationOf(bot2.address);
            assert.equal(app.status, 4 /* rejected */);
        });

        it("re-create rejected application", async function() {
            await truffleAssert.fails(rewards.createApplication(bot2.address, { from: bob }), message = "RewardManager: application has been processed");
        });

        it("propose rejected application", async function() {
            await truffleAssert.fails(rewards.createProposal(bot2.address, 10000), message = "RewardManager: invalid application status");
        });
    });

    describe("emergency", function() {
        it("emergency withdraw", async function() {
            let balance = (await vics.balanceOf(admin))
                          .add(await vics.balanceOf(rewards.address));
            await rewards.emergencyWithdraw();
            assert.equal(await vics.balanceOf(admin), balance.toString());
            assert.equal(await vics.balanceOf(rewards.address), 0)
        });
    })

});