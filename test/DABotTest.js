const { assert } = require('chai');
var BN = require('bn.js');
const truffleAssert = require('truffle-assertions');
const { ERC20_CONTRACT_ABI } = require('./erc20');

const Factory = artifacts.require('RoboFiFactory');
const RoboFiToken = artifacts.require('RoboFiToken');
const DABotBase = artifacts.require('DABotBase');
const CEXDABot = artifacts.require('CEXDABot');
const DABotManager = artifacts.require('DABotManager');
const CertToken = artifacts.require('CertToken');
const Locker = artifacts.require('CertLocker');
const VICS = artifacts.require('VICSToken');


contract('DABotBaseTest', async (accounts) => {

    const admin = accounts[0];
    const alice = accounts[1];

    let dabot;
    let certtoken;
    let vics;
    let botmanager;
    let factory;
    let cexdabot;
    let locker;
    let usdt;

    before(async ()=> {
        vics = await VICS.new(100000000);
        factory = await Factory.new();
        certtoken = await CertToken.new();
        botmanager = await DABotManager.new(factory.address, vics.address, certtoken.address);
        locker = await Locker.new();
        dabot = await DABotBase.new('sample', vics.address, botmanager.address, locker.address, admin);
        cexdabot = dabot; // await CEXDABot.new(vics.address, botmanager.address, admin);
        usdt = await RoboFiToken.new("USDT", "USDT", 10000000, admin);
        bnb = await RoboFiToken.new("BNB", "BNB", 1000000, admin);


        await botmanager.addTemplate(cexdabot.address);

        await vics.approve(dabot.address, 100000000, { from: admin });
        await vics.approve(botmanager.address, 10000000, { from: admin });
    });

    describe('DABotBase Test', () => {
        it('Get/set bot setting', async() => {

            await dabot.renounceOwnership();
            let data = web3.eth.abi.encodeParameters
                            (['string', 'address', 'uint64', 'uint16', 'uint32', 'uint144', 'uint', 'uint', 'uint', 'uint'],
                            ['sample', admin, '0x0FFFFF000FFFFE', 0, 0, 0, 100, 200, 1000000, 500000]);
            await dabot.init(data);

            await dabot.setStakingTime(20, 30);
            await dabot.setPricePolicy(150, 50);
            await dabot.setProfitSharing(200);            

            await dabot.setIBOTime(10, 100);

            let detail = await dabot.botDetails();
            assert.equal(detail.iboStartTime, 10);
            assert.equal(detail.iboEndTime, 100);
            assert.equal(detail.warmup, 20);
            assert.equal(detail.cooldown, 30);
            assert.equal(detail.priceMul, 150);
            assert.equal(detail.commissionFee, 50);
            assert.equal(detail.profitSharing, 200);
            assert.equal(detail.initDeposit, 100);
            assert.equal(detail.initFounderShare, 200);

            // assert.equal(await vics.balanceOf(dabot.address), 100);
            assert.equal(await dabot.balanceOf(admin), 200);
        });

        it('Deploy new bot', async() => {

            let tx = await botmanager.deployBot(cexdabot.address, 'Sample', [
                        new BN(1627201595 /*2021-07-25*/, 10).shln(32).ior(1624609595 /*2021-06-25 */)  /* iboTime */, 
                        0 /* stakingtime */, 
                        0 /* price policy */, 
                        0 /* profit sharing */, 
                        100 /* init deposit */, 
                        200 /* founder share */, 
                        10000 /* gtoken: max cap */, 
                        5000 /* supply for IBO */]);

            let result = tx.logs[1].args;

            console.log(`Bot id: ${result.botId}, @: ${result.bot}`);

            assert.equal(await vics.balanceOf(result.bot), 100);
            // assert.equal(await bot.balanceOf(admin), 200);

            let details = await botmanager.queryBots([result.botId]);
            assert.equal(details[0].initDeposit, 100);
            assert.equal(details[0].initFounderShare, 200);
        });

        it('Add/remove porfolio asset', async() => {
            let bot = await CEXDABot.new(vics.address, botmanager.address, locker.address, admin);
            await bot.renounceOwnership();

            let iboStart = new Date();
            let iboEnd = new Date();

            iboStart.setHours(iboStart.getHours() + 1);
            iboEnd.setMonth(iboEnd.getMonth() + 1);
            let iboTime = new BN(Math.trunc(iboEnd.getTime()/1000), 10).shln(32).add(new BN(Math.trunc(iboStart.getTime()/1000), 10));

            let data = web3.eth.abi.encodeParameters
                            (['string', 'address', 'uint64', 'uint16', 'uint32', 'uint144', 'uint', 'uint', 'uint', 'uint'],
                            ['sample', admin, iboTime, 0, 0, 0, 100, 200, 10000, 5000]);
            console.log('initialize bot');
            await bot.init(data);

            console.log('update portfolio');
            await bot.updatePortfolio(usdt.address, 2000, 1000, 50);

            console.log("validate porfolio");
            let portfolio = await bot.portfolio();
            let cert = portfolio[0];

            assert.equal(cert.info.cap, 2000);
            assert.equal(cert.info.iboCap, 1000);
            assert.equal(cert.info.weight, 50);

            await bot.removeAsset(usdt.address);

            portfolio = await bot.portfolio();
            assert.equal(portfolio.length, 0);
        });

        it('Stake/unstake', async() => {
            let iboStart = new Date();
            let iboEnd = new Date();

            iboStart.setHours(iboStart.getHours() + 1);
            iboEnd.setMonth(iboEnd.getMonth() + 1);
            let iboTime = new BN(Math.trunc(iboEnd.getTime()/1000), 10).shln(32).add(new BN(Math.trunc(iboStart.getTime()/1000), 10));

            let tx = await botmanager.deployBot(cexdabot.address, 'Sample', [
                iboTime, /* iboTime */, 
                0 /* stakingtime */, 
                0 /* price policy */, 
                0 /* profit sharing */, 
                100 /* init deposit */, 
                200 /* founder share */, 
                10000 /* gtoken: max cap */, 
                5000 /* supply for IBO */]);

            let result = tx.logs[1].args;

            console.log(`Bot id: ${result.botId}, @: ${result.bot}`);

            let bot = await CEXDABot.at(result.bot);

            await bot.updatePortfolio(usdt.address, 2000 /* max cap */, 1000 /* ibo cap */, 50);
            let portfolio = await bot.portfolio();

            assert.equal(portfolio.length, 1);
            console.log(`Certasset: ${portfolio[0].info.certAsset}`);
            let botusdt = await CertToken.at(portfolio[0].info.certAsset);

            truffleAssert.fails(bot.stake(usdt.address, 1000), message = "DABot: permission denied");
            assert.equal(await bot.availableSharesFor(admin), 0, "0 share available before IBO");

            iboStart.setHours(iboStart.getHours() - 2);
            await bot.setIBOTime(Math.trunc(iboStart.getTime() / 1000), Math.trunc(iboEnd.getTime() / 1000)); 

            console.log("Update IBO time");

            // transfer usdt to alice
            await usdt.transfer(alice, 500, { from: admin });

            await usdt.approve(bot.address, 10000, { from: alice });
            await bot.stake(usdt.address, 500, { from: alice });

            assert.equal(await bot.stakeBalanceOf(alice, usdt.address), 500, "wrong usdt stake balance");
            assert.equal(await bot.availableSharesFor(alice), 2500, "wrong purchasable g-token");
            assert.equal(await botusdt.balanceOf(alice), 500, "wrong usdt certificate balance");
        });
    });
});