const { assert } = require('chai');
const truffleAssert = require('truffle-assertions');

const PeggedToken = artifacts.require('PeggedToken');
const RoboFiToken = artifacts.require('RoboFiToken')

contract('PeggedTokenTest', async (accounts) => {
    const ACTION_DEPOSIT= 0;
    const ACTION_ADD_REWARD = 1;
    const ACTION_CLAIM_REWARD = 2;
    const ACTION_TRANSFER = 3;
    const ACTION_BURN = 4;

    const admin = accounts[0];
    const alice = accounts[1];
    const bob = accounts[2];
    const charlie = accounts[3];
    const dave = accounts[4];

    const UNIT = 1e6;
    const MAX_CAP = 1e6;

    let usdt;
    let silkUsdt;
    let testData = [
        { it: 'Alice deposits 1000 USDT', action: ACTION_DEPOSIT, account: alice, before: { USDT: 1000, SilkUSDT: 0 }, tx: { inUSDT: 1000 }, after: { USDT: 0, SilkUSDT: 1000 } },
        { it: 'Bob deposits 1000 USDT', action: ACTION_DEPOSIT, account: bob, before: { USDT: 2000, SilkUSDT: 0 }, tx: { inUSDT: 1000 }, after: { USDT: 1000, SilkUSDT: 1000 } },
        { it: 'add reward: 200 USDT', action: ACTION_ADD_REWARD, tx: { inUSDT: 200 } },
        { it: 'Charlie deposits 1000 USDT', action: ACTION_DEPOSIT, account: charlie, before: { USDT: 1000, SilkUSDT: 0 }, tx: { inUSDT: 1000 }, after: { USDT: 0, SilkUSDT: 1000} },
        { it: 'Alice claims rewards', action: ACTION_CLAIM_REWARD, account: alice, before: { USDT: 0, SilkUSDT: 1000 }, after: { USDT: 100, SilkUSDT: 1000 } },
        { it: 'Alice claims rewards', action: ACTION_CLAIM_REWARD, account: alice, before: { USDT: 100, SilkUSDT: 1000 }, after: { USDT: 100, SilkUSDT: 1000 } },
        { it: 'Bob claims rewards', action: ACTION_CLAIM_REWARD, account: bob, before: { USDT: 1000, SilkUSDT: 1000 }, after: { USDT: 1100, SilkUSDT: 1000 } },
        { it: 'add reward: 300', action: ACTION_ADD_REWARD, tx: { inUSDT: 300 } },
        { it: 'Charlies transfers to Dave 500 SilkUSDT', action: ACTION_TRANSFER, account: charlie, before: { USDT: 0, SilkUSDT: 1000 }, tx: { inSilkUSDT: 500 }, after: { USDT: 100, SilkUSDT: 500 },
                                            receiver: dave, receiver_before: { USDT: 0, SilkUSDT: 0 }, receiver_after: { USDT: 0, SilkUSDT: 500 } },
        { it: 'Dave claims rewards', action: ACTION_CLAIM_REWARD, account: dave, before: { USDT: 0, SilkUSDT: 500 }, after: { USDT: 0, SilkUSDT: 500 } },                                            
        { it: 'Charlies claims rewards', action: ACTION_CLAIM_REWARD, account: charlie, before: { USDT: 100, SilkUSDT: 500 }, after: { USDT: 100, SilkUSDT: 500 } },                                            
        { it: 'add reward: 300', action: ACTION_ADD_REWARD, tx: { inUSDT: 300 } },
        { it: 'Dave transfers to Alice 500 SilkUSDT', action: ACTION_TRANSFER, account: dave, before: { USDT: 0, SilkUSDT: 500 }, tx: { inSilkUSDT: 250 }, after: { USDT: 46.874999, SilkUSDT: 250 },
                                            receiver: alice, receiver_before: { USDT: 100, SilkUSDT: 1000 }, receiver_after: { USDT: 100, SilkUSDT: 1250 } },
        { it: 'add reward: 300', action: ACTION_ADD_REWARD, tx: { inUSDT: 300 } },
        { it: 'Dave burns 100 SilkUSDT', action: ACTION_BURN, account: dave, before: { USDT: 46.874999, SilkUSDT: 250 }, tx: { inSilkUSDT: 100 }, after: { USDT: 168.594456, SilkUSDT: 150 } },
        { it: 'Charlies burns 500 SilkUSDT', action: ACTION_BURN, account: charlie, before: { USDT: 100, SilkUSDT: 500 }, tx: { inSilkUSDT: 500 }, after: { USDT: 694.386311, SilkUSDT: 0 } },
        { it: 'Alice burns 1250 SilkUSDT', action: ACTION_BURN, account: alice, before: { USDT: 100, SilkUSDT: 1250 }, tx: { inSilkUSDT: 1250 }, after: { USDT: 1679.369344, SilkUSDT: 0 } },
        { it: 'Bob burns 1000 SilkUSDT', action: ACTION_BURN, account: bob, before: { USDT: 1100, SilkUSDT: 1000 }, tx: { inSilkUSDT: 1000 }, after: { USDT: 2407.649888, SilkUSDT: 0 } },
        { it: 'Dave burns 150 SilkUSDT', action: ACTION_BURN, account: dave, before: { USDT: 168.594456, SilkUSDT: 150 }, tx: { inSilkUSDT: 150 }, after: { USDT: 318.594457, SilkUSDT: 0 } },
    ];

    before(async ()=> {

        usdt = await RoboFiToken.new('Tether', 'USDT', MAX_CAP * UNIT, admin);
        silkUsdt = await PeggedToken.new('SilkUSDT', 'SilkUSDT', usdt.address);

        await usdt.transfer(alice, 1000 * UNIT, { from: admin });
        await usdt.transfer(bob, 2000 * UNIT , { from: admin });
        await usdt.transfer(charlie, 1000 * UNIT, { from: admin });

        await usdt.approve(silkUsdt.address, MAX_CAP * UNIT, { from: alice });
        await usdt.approve(silkUsdt.address, MAX_CAP * UNIT, { from: bob });
        await usdt.approve(silkUsdt.address, MAX_CAP * UNIT, { from: charlie });
        await usdt.approve(silkUsdt.address, MAX_CAP * UNIT, { from: dave });
    });
    
    describe('Test PeggedToken', () => {
        testData.forEach(async (data) => 
            await it(data.it, async () => {
                switch(data.action) {
                    case ACTION_DEPOSIT: await deposit(data);  break;
                    case ACTION_ADD_REWARD: await addReward(data); break;
                    case ACTION_CLAIM_REWARD: await claimReward(data); break;
                    case ACTION_TRANSFER: await transfer(data); break;
                    case ACTION_BURN: await burn(data); break;
                    default: break;
                }
            })
        );
    });

    async function deposit(data) {
        await assertBalance(data.account, data.before, 'before balance');
        await silkUsdt.mint(data.account, data.tx.inUSDT * UNIT, { from: admin });
        await assertBalance(data.account, data.after, 'after balance');

        await showDepositInfo();
    }

    async function burn(data) {
        await assertBalance(data.account, data.before, 'before balance');
        await silkUsdt.burn(data.account, data.tx.inSilkUSDT * UNIT, { from: admin });
        await assertBalance(data.account, data.after, 'after balance');
        await showAccountInfo(data.account, 'Sender');
    }

    async function addReward(data) {
        await usdt.transfer(silkUsdt.address, data.tx.inUSDT * UNIT, { from: admin });
        await showDepositInfo();
    }

    async function showDepositInfo() {
        console.log(`USDT BALANCE silkUSDT ${await usdt.balanceOf(silkUsdt.address) / UNIT}`);
        console.log(`Point Supply silkUSDT ${await silkUsdt.pointSupply() / UNIT}`);
        // console.log(`pointRate: ${await silkUsdt.mulPointRate(1e5)/1e5}`);
    }

    async function showAccountInfo(account, name) {
        let silkUsdtBalance = await silkUsdt.balanceOf(account);
        let pointBalance = await silkUsdt.pointBalanceOf(account);
        console.log(`${name}: USDT ${await usdt.balanceOf(account) / UNIT}, SilkUSDT ${silkUsdtBalance / UNIT}, SilkPoint ${pointBalance / UNIT}, Claimable reward: ${await silkUsdt.getClaimableReward(account) / UNIT}`);
    }

    async function claimReward(data) {
        await assertBalance(data.account, data.before, 'before balance');
        await silkUsdt.claimReward({ from: data.account });
        await assertBalance(data.account, data.after, 'after balance');
        await showDepositInfo();
        await showAccountInfo(data.account, 'Sender');
    }

    async function transfer(data) {
        await assertBalance(data.account, data.before, 'before balance');
        await assertBalance(data.receiver, data.receiver_before, 'receiver before balance');
        await silkUsdt.transfer(data.receiver, data.tx.inSilkUSDT * UNIT, { from: data.account });
        await assertBalance(data.account, data.after, 'after balance');
        await assertBalance(data.receiver, data.receiver_after, 'reciver after balance');
        await showAccountInfo(data.account, 'Sender');
        await showAccountInfo(data.receiver, 'Receiver');
    }

    async function assertBalance(account, balance, message) {
        assert.equal(balance.USDT, await usdt.balanceOf(account) / UNIT, `${message} USDT`);
        assert.equal(balance.SilkUSDT, await silkUsdt.balanceOf(account) / UNIT, `${message} SilkUSDT`);
    }
});