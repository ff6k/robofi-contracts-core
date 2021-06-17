const { assert } = require('chai');
const truffleAssert = require('truffle-assertions');

const TreasuryAsset = artifacts.require('TreasuryAsset');
const RoboFiToken = artifacts.require('RoboFiToken');

contract('TreasuryAsset', async (accounts) => {
    const admin = accounts[0];
    const fundManager = accounts[1];
    const alice = accounts[2];
    const bob = accounts[3];

    let flcTreasury
    let flc;

    before(async ()=> {
        flc = await RoboFiToken.new('Felice', 'FLC', 1000000000, admin);
        flcTreasury = await TreasuryAsset.new(flc.address, fundManager);

        await flc.transfer(alice, 5000, { from: admin });
    });
    
    describe('Test', () => {
        it('alice mints 2000 FLC to get 2000 sFLC', async () => {
            await flc.approve(flcTreasury.address, 2000, { from: alice });
            await flcTreasury.mint(alice, 2000, { from: alice });
            assert.equal(await flcTreasury.balanceOf(alice), 2000);
        });

        it('alice locks 1000 sFLC', async() => {
            let aliceSFLC = await flcTreasury.balanceOf(alice);
            let aliceFLC = await flc.balanceOf(alice);

            await flcTreasury.lock(1000, { from: alice });

            assert.equal(await flcTreasury.balanceOf(alice), aliceSFLC.toNumber(), "SFLC balance should not be changed after locking");
            assert.equal(await flc.balanceOf(alice), aliceFLC.toNumber(), "FLC balance should not be changed after locking");
            assert.equal(await flcTreasury.lockedBalanceOf(alice), 1000, "locked balance update");
            assert.equal(await flc.balanceOf(fundManager), 1000);
        });

        it('alice should not be able to transfer 1500 sFLC, but 500 sFLC to Bob is ok', async() => {
            truffleAssert.fails(flcTreasury.transfer(bob, 1500, { from: alice }), 
                                                    reason = "TreasuryAsset: amount execeed available balance");

            await flcTreasury.transfer(bob, 500, { from: alice });
            assert.equal(await flcTreasury.balanceOf(alice), 1500);
            assert.equal(await flcTreasury.balanceOf(bob), 500);
        });

        it('unlock 1000 sFLC for alice', async() => {
            await flc.approve(flcTreasury.address, 1000, { from: fundManager });
            await flcTreasury.unlock(alice, 1000, { from: fundManager });

            assert.equal(await flcTreasury.lockedBalanceOf(alice), 0);
            assert.equal(await flc.balanceOf(fundManager), 0);
        });

        it('alice transfers 1000 sFLC to bob, bob burns 1500 sFLC', async() => {
            await flcTreasury.transfer(bob, 1000, {from: alice});

            assert.equal(await flc.balanceOf(bob), 0);
            assert.equal(await flcTreasury.balanceOf(bob), 1500);

            await flcTreasury.burn(1500, { from: bob });

            assert.equal(await flc.balanceOf(bob), 1500);
            assert.equal(await flcTreasury.balanceOf(bob), 0);
            assert.equal(await flcTreasury.totalSupply(), 500);
        });
    });
});