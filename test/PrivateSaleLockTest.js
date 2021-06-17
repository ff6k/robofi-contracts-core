const { assert } = require('chai');
const truffleAssert = require('truffle-assertions');

const VICSTokenContract = artifacts.require('VICSToken')
const PrivateSaleContract = artifacts.require('PrivateSaleLock');


contract('PrivateSaleLock Test', async (accounts) => {
    const admin = accounts[0];
    const alice = accounts[1];

    let privateSale;
    let vics;

    before(async ()=> {
        vics = await VICSTokenContract.new(100000, { from: admin });
        privateSale = await PrivateSaleContract.new(vics.address, { from: admin });

        await vics.approve(privateSale.address, 10000000, { from:admin });
    })

    describe('Test privateSale', ()=> {
        it('Sale to user', async () => {
            await privateSale.sale(alice, 10000, { from: admin });
            await assertSaleDetail(alice, 10000, 0);
            let privateSaleBalance = await vics.balanceOf(privateSale.address);
            assert.equal(privateSaleBalance, 10000);
            await assertSaleDetail(alice, 10000, 0);
        });

        it('valid unlock', async ()=> {
            await privateSale.unlock(alice, 5000, { from: admin});
            await assertSaleDetail(alice, 10000, 5000);
        });

        it('invalid unlock', async() => {
            truffleAssert.fails(privateSale.unlock(alice, 6000, { from: admin}), reason = 'PrivateSale: amount to unlock exceed ');
            await assertSaleDetail(alice, 10000, 5000);
        });

        it('withdraw', async () => {
            await privateSale.withdraw({ from: alice });

            let vicsAmount = await vics.balanceOf(alice);
            assert.equal(vicsAmount, 5000);

            await assertSaleDetail(alice, 5000, 0);
        });
    })

    async function assertSaleDetail(account, balance, available) {
        result = await privateSale.getSaleDetail(account)
        assert.equal(result[0], balance);
        assert.equal(result[1], available);
    }

});