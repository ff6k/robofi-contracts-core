# Treasury 

Treasury acts as a token bridge in the ecosystem, which mirrors crypto token to sToken required by some DABots (like SilkBot).
Treasury maintains 1:1 conversion rate: 1 input token will be mirrored by 1 corresponding sToken. And when 1 sToken is burnt (i.e., redeem), exactly 1 correpsonding token will be returned to the caller's account.

Treasury is a collection of TreasuryAsset contracts. Each TreasuryAsset contract will manage the deposit and redeem of a single crypto asset. For example, we have:
* USDTTreasuryAsset: accepts depositing of USDT to issue sUSDT, and burning sUSDT to get back USDT.
* ETHTreasuryAsset: accepts depositing of ETH to issue sETH, and buring sETH to get back ETH.


## Workflows

### Mint sToken (from ERC20/BEP20 token to sToken)
* Alice wants to mint 100 sUSDT from 100 USDT.
* Alice calls `Tether.Approve(address(TreasuryUSDT), 100)` to allow contract TreasuryUSDT to withdraw 100 USDT from her account.
* Alice calls `TreasuryUSDT.mint(address(Alice), 100)`.
* TreasuryUSDT withdraws 100 USDT from Alice's account, mints 100 sUSDT token to the address of Alice.

### Lock/unlock sToken
`Lock sToken` is an operation to prevent transfering/redeeming sToken of a DABot, and release the pegged assets to the pre-defined fund manager.
This is to allow the fund manager to get the pegged crypto assets and assign a trader (or groups of traders) to generate profit.
The released pegged assets are managed by the fund manager. Traders are able to trade on these assets but cannot withdraw them out of the fund manager's account.

The master/sub accounts introduced by Binance is a perfect example for that. For example, the pegged crypto assets are transfered to the master account managed by the fund manager.
The fund manager transfers assets to one or more sub-accounts, which are tradeable by traders. However, traders cannot withdraw assets from their sub-accounts.
The fund manager at any time could transfer crypto assets in (or out) his sub-accounts.

To lock sToken of a DABot, 
* Charlie is the bot creator of SilkBot
* He wants to lock 1000 sUSDT from the SilkBot for trading.
* He calls `SilkBot.lock(address(TreasuryUSDT), 1000)`
* SilkBot calls `TreasuryUSDT.lock(1000)`
* TreasuryUSDT updates the lock balance of SilkBot, and transfers 1000 USDT to the fund manager's address.
