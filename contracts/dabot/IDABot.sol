// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Factory.sol";

library DABotCommon {

    enum ProfitableActors { BOT_CREATOR, GOVERNANCE_USER, STAKE_USER, ROBOFI_GAME }
   
    struct PortfolioAsset {
        address certAsset;    // the certificate asset to return to stake-users
        uint256 cap;            // the maximum stake amount for this asset (bot-lifetime).
        uint256 weight;         // preference weight for this asset. Use to calculate the max purchasable amount of governance tokens.
        uint256 iboCap;         // the maximum stake amount for this asset within the IBO.
        uint256 totalStake;     // the total stake of all users.
    }

    struct UserPortfolioAsset {
        address asset;
        PortfolioAsset info;
        uint256 userStake;
    }

    struct BotSetting {             // for saving storage, the meta-fields of a bot are encoded into a single uint256 byte slot.
        uint64 iboTime;             // 32 bit low: iboStartTime (unix timestamp), 
                                    // 32 bit high: iboEndTime (unix timestamp)
        uint16 stakingTime;         // 8 bit low: warm-up time, 
                                    // 8 bit high: cool-down time
        uint32 pricePolicy;         // 16 bit low: price multiplier (fixed point, 2 digits for decimal)
                                    // 16 bit high: commission fee in percentage (fixed point, 2 digit for decimal)
        uint144 profitSharing;      // packed of 16bit profit sharing: bot-creator, gov-user, stake-user, and robofi-game
        uint initDeposit;           // the intial deposit (in VICS) of bot-creator
        uint initFounderShare;      // the intial shares (i.e., governance token) distributed to bot-creator
        uint maxShare;              // max cap of gtoken supply
        uint iboShare;              // max supply of gtoken for IBO. Constraint: maxShare >= iboShare + initFounderShare
    }

    struct BotDetail { // represents a detail information of a bot, merely use for bot infomation query
        uint id;                    // the unique id of a bot within its manager.
                                    // note: this id only has value when calling {DABotManager.queryBots}
        address botAddress;         // the contract address of the bot.
        address masterContract;     // reference to the master contract of a bot contract.
                                    // in most cases, a bot contract is a proxy to a master contract.
                                    // particular settings of a bot are stored in the bot contracts.
        string name;                // get the bot name.
        address template;           // the address of the master contract which defines the behaviors of this bot.
        string templateName;        // the template name.
        string templateVersion;     // the template version.
        uint iboStartTime;          // the time when IBO starts (unix second timestamp)
        uint iboEndTime;            // the time when IBO ends (unix second timestamp)
        uint warmup;                // the duration (in days) for which the staking profit starts counting
        uint cooldown;              // the duration (in days) for which users could claim back their stake after submiting the redeem request.
        uint priceMul;              // the price multiplier to calculate the price per gtoken (based on the IBO price).
        uint commissionFee;         // the commission fee when buying gtoken after IBO time.
        uint initDeposit;           
        uint initFounderShare;
        uint144 profitSharing;
        uint maxShare;              // max supply of governance token.
        uint circulatedShare;       // the current supply of governance token.
        uint iboShare;              // the max supply of gtoken for IBO.
        uint userShare;             // the amount of governance token in the caller's balance.
        UserPortfolioAsset[] portfolio;
    }

    function iboStartTime(BotSetting storage info) view internal returns(uint) {
        return info.iboTime & 0xFFFFFFFF;
    }

    function iboEndTime(BotSetting storage info) view internal returns(uint) {
        return info.iboTime >> 32;
    }

    function setIboTime(BotSetting storage info, uint start, uint end) internal {
        require(start < end, "invalid ibo start/end time");
        info.iboTime = uint64((end << 32) | start);
    }

    function warmupTime(BotSetting storage info) view internal returns(uint) {
        return info.stakingTime & 0xFF;
    }

    function cooldownTime(BotSetting storage info) view internal returns(uint) {
        return info.stakingTime >> 8;
    }

    function setStakingTime(BotSetting storage info, uint warmup, uint cooldown) internal {
        info.stakingTime = uint16((cooldown << 8) | warmup);
    }

    function priceMultiplier(BotSetting storage info) view internal returns(uint) {
        return info.pricePolicy & 0xFFFF;
    }

    function commission(BotSetting storage info) view internal returns(uint) {
        return info.pricePolicy >> 16;
    }

    function setPricePolicy(BotSetting storage info, uint _priceMul, uint _commission) internal {
        info.pricePolicy = uint32((_commission << 16) | _priceMul);
    }

    function profitShare(BotSetting storage info, ProfitableActors actor) view internal returns(uint) {
        return (info.profitSharing >> uint(actor) * 16) & 0xFFFF;
    }

    function setProfitShare(BotSetting storage info, uint sharingScheme) internal {
        info.profitSharing = uint144(sharingScheme);
    }
}

/**
@dev The generic interface of a DABot.
 */
interface IDABot {
    
    function botname() view external returns(string memory);
    function name() view external returns(string memory);
    function symbol() view external returns(string memory);
    function version() view external returns(string memory);

    /**
    @dev Retrieves the detail infromation of this DABot.

    Note: all fields of {DABotCommon.BotDetail} are filled, except {id} which is filled 
    by only the DABotManager.
     */
    function botDetails() view external returns(DABotCommon.BotDetail memory);

}


interface IDABotManager {
    
    function factory() external view returns(RoboFiFactory);

    /**
    @dev Gets the address to receive tax.
     */
    function taxAddress() external view returns (address);

    /**
    @dev Gets the address of the platform operator.
     */
    function operatorAddress() external view returns (address);

    /**
    @dev Gets the deposit amount (in VICS) that a person has to pay to create a proposal.
         When a proposal is settled (either approved or rejected), the account who submits or 
         clean the proposal will be awarded a portion of the deposit. The remain will go to operator addresss.

         See {proposalReward()}.
     */
    function proposalDeposit() external view returns (uint);
    
    /**
    @dev Gets the the percentage of proposalDeposit for awarding proposal settlement (for both approved and expired proposals).
         the remain part of proposalDeposit will go to operatorAddress.
     */
    function proposalReward() external view returns (uint);

    /**
    @dev Gets the minimum amount of VICS that a bot creator has to deposit to his newly created bot.
     */
    function minCreatorDeposit() external view returns(uint);

    function deployBotCertToken(address peggedAsset) external returns(address);

    event OperatorAddressChanged(address indexed account);
    event TaxAddressChanged(address indexed account);
    event ProposalDepositChanged(uint value);
    event ProposalRewardChanged(uint value);
    event MinCreatorDepositChanged(uint value);
    event BotDeployed(address indexed creator, address indexed template, uint botId, address indexed bot);
    event CertTokenDeployed(address indexed bot, address indexed asset, address indexed certtoken);
    event TemplateRegistered(address indexed template);
}

