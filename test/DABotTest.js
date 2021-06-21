const { assert } = require('chai');
const truffleAssert = require('truffle-assertions');

const Factory = artifacts.require('RoboFiFactory');
const DABotBase = artifacts.require('DABotBase');
const CEXDABot = artifacts.require('CEXDABot');
const DABotManager = artifacts.require('DABotManager');
const CertToken = artifacts.require('CertToken');
const VICS = artifacts.require('VICSToken');


contract('DABotBaseTest', async (accounts) => {

    const admin = accounts[0];
    let dabot;
    let certtoken;
    let vics;
    let botmanager;
    let factory;
    let cexdabot;

    before(async ()=> {
        vics = await VICS.new(100000000);
        factory = await Factory.new();
        certtoken = await CertToken.new();
        botmanager = await DABotManager.new(factory.address, vics.address, certtoken.address);
        dabot = await DABotBase.new('sample', vics.address, botmanager.address, admin);
        cexdabot = await CEXDABot.new(vics.address, botmanager.address, admin);
        
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

            assert.equal(await dabot.calcOutToken(1000, 100, 0) / 1,  2000);
            assert.equal(await dabot.calcOutToken(1000, 100, 100) / 1, 1980) ;

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

            let tx = await botmanager.deployBot(cexdabot.address, 'Sample', ['0x0FFFFF000FFFFE', 0, 0, 0, 100, 200, 1000000, 500000]);
            let result = tx.logs[1].args;

            console.log(`Bot id: ${result.botId}, @: ${result.bot}`);

            assert.equal(await vics.balanceOf(result.bot), 100);
            // assert.equal(await bot.balanceOf(admin), 200);

            let details = await botmanager.queryBots([result.botId]);
            assert.equal(details[0].initDeposit, 100);
            assert.equal(details[0].initFounderShare, 200);
        });
    });
});