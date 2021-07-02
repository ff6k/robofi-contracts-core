// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./CertToken.sol";
import "./IDABot.sol";

/**
@dev This contract provides support for staking warm-up feature. 
When users stake into a DABot, user will not immediately receive the certificate token.
Instead, these tokens will be locked inside an instance of this contract for a predefined
period, the warm-up period. 

During the warm-up period, certificate tokens will not generate any reward, no matter rewards
are added to the DABot or not. After the warm-up period, users can claim these tokens to 
their wallet.

If users do not claim tokens after warm-up period, the tokens are still kept securedly inside
the contract. Locked tokens will also entitle to receive rewards. When users claim the tokens, 
rewards will be distributed automatically to users' wallet. 
 */
contract CertLocker is IMasterContract {

    struct LockerInfo {
        IDABot bot;             // the DABOT which creates this locker.
        address owner;          // the locker owner, who is albe to unlock and get tokens after the specified release time.
        CertToken token;        // the contract of the certificate token.
        uint64 created_at;      // the moment when locker is created.
        uint64 release_at;      // the monent when locker could be unlock. 
    }

    struct LockerInfoEx {
        LockerInfo info;
        uint256 amount;         // the locked amount of cert token within this locker.
        uint256 reward;         // the accumulated rewards
        address asset;          // the stake asset beyond the certificated token
    }

    LockerInfo private _info;

    event Unlock(IDABot bot, address indexed owner, CertToken token, uint256 amount, uint256 reward);

    function init(bytes calldata data) external virtual payable override {
        require(address(_info.owner) == address(0), "CertLocker: locker initialized");
        (_info) = abi.decode(data, (LockerInfo));
    }

    function lockedBalance() public view returns(uint) {
        return _info.token.balanceOf(address(this));
    }

    function getInfo() public view returns(LockerInfoEx memory result) {
        result.info = _info;
        result.amount = _info.token.balanceOf(address(this));
        result.asset = address(_info.token.asset());
        result.reward = _getReward();
    }

    function _getReward() internal view returns(uint256) {
        return block.timestamp < _info.release_at ? 0 :
                         _info.token.getClaimableReward(address(this)) * (block.timestamp - _info.release_at) / (block.timestamp - _info.created_at);
    }

    function unlock() public {
        require(block.timestamp >= _info.release_at, "Token is locked");

        _info.token.claimReward();
        IERC20 asset = _info.token.asset();
        uint256 amount = _info.token.balanceOf(address(this));
        uint256 rewards = asset.balanceOf(address(this));
        _info.token.transfer(_info.owner, amount);
        uint256 entitledRewards = _getReward();
        if (rewards > 0) {
            require(rewards >= entitledRewards, "Actual rewards is less than entitled rewards");
            if (entitledRewards > 0) asset.transfer(_info.owner, entitledRewards);
            if (rewards - entitledRewards > 0) asset.transfer(address(_info.token), rewards - entitledRewards);
        }

        emit Unlock(_info.bot, _info.owner, _info.token, amount, entitledRewards);

        selfdestruct(payable(_info.owner));
    }
}