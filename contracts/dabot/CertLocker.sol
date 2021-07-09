// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./CertToken.sol";
import "./IDABot.sol";


abstract contract CertLocker is IMasterContract {

    DABotCommon.LockerInfo internal _info;

    function init(bytes calldata data) external virtual payable override {
        require(address(_info.owner) == address(0), "Locker: locker initialized");
        (_info) = abi.decode(data, (DABotCommon.LockerInfo));
    }

    function lockedBalance() public view returns(uint) {
        return CertToken(_info.token).balanceOf(address(this));
    }

    function asset() external view returns(IERC20) {
        return CertToken(_info.token).asset();
    }

    function owner() external view returns(address) {
        return _info.owner;
    }

    function detail() public view returns(DABotCommon.LockerInfoEx memory result) {
        result.locker = address(this);
        result.info = _info;
        result.amount = CertToken(_info.token).balanceOf(address(this));
        result.asset = address(CertToken(_info.token).asset());
        result.reward = _getReward();
    }

    function _getReward() internal view virtual returns(uint256);

    function unlockable() public view returns(bool) {
        return block.timestamp >= _info.release_at;
    }

    /**
    @dev Tries to unlock this locker if the time condition meets, otherise skipping the action.
     */
    function tryUnlock() public returns(bool) {
        require(msg.sender == address(_info.bot), "Locker: Permission denial");
        if (!unlockable()) 
            return false;
        _unlock();  
        return true;
    }

    function _unlock() internal virtual;

    function finalize() external payable {
        require(msg.sender == address(_info.bot), "Locker: Permission denial");
        selfdestruct(payable(_info.owner));
    }
}

/**
@dev This contract provides support for staking warmup feature. 
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
contract WarmupLocker is CertLocker {

    event Release(IDABot bot, address indexed owner, address certtoken, uint256 amount, uint256 reward);

    function _getReward() internal view override returns(uint256) {
        return block.timestamp < _info.release_at ? 0 :
                         CertToken(_info.token).getClaimableReward(address(this)) * (block.timestamp - _info.release_at) / (block.timestamp - _info.created_at);
    }

    function _unlock() internal override {

        CertToken token = CertToken(_info.token);
        
        require(_info.token != address(0), "CertToken: null token address");
        require(address(token.asset()) != address(0), "CertToken: null asset address");

        token.claimReward();
        IERC20 peggedAsset = token.asset();
        uint256 amount = token.balanceOf(address(this));
        uint256 rewards = peggedAsset.balanceOf(address(this));
        token.transfer(_info.owner, amount);
        uint256 entitledRewards = _getReward();
        if (rewards > 0) {
            require(rewards >= entitledRewards, "Actual rewards is less than entitled rewards");
            if (entitledRewards > 0) peggedAsset.transfer(_info.owner, entitledRewards);
            if (rewards - entitledRewards > 0) peggedAsset.transfer(_info.token, rewards - entitledRewards);
        }
        emit Release(_info.bot, _info.owner, _info.token, amount, entitledRewards);
    }
}


contract CooldownLocker is CertLocker {

    event Release(IDABot bot, address indexed owner, address certtoken, uint256 penalty);

    function _getReward() internal view override returns(uint256) {
        return CertToken(_info.token).getClaimableReward(address(this)) * 10 / 100;
    }

    function _unlock() internal override {
        CertToken token = CertToken(_info.token);
        uint256 penalty = token.getClaimableReward(address(this)) * 90 / 100;
        token.burn(token.balanceOf(address(this))); 

        IERC20 peggedAsset = token.asset();
        
        peggedAsset.transfer(address(token), penalty);
        peggedAsset.transfer(_info.owner, peggedAsset.balanceOf(address(this)));

        emit Release(_info.bot, _info.owner, _info.token, penalty);
    }
}