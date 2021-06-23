// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../token/IRoboFiToken.sol";
import "../Ownable.sol";
import "../Factory.sol"; 
import "./IDABot.sol"; 

abstract contract BotManagerSetting is Context, Ownable, IDABotManager {
    struct DABotSetting {
        address operatorAddress;
        uint proposalDeposit;   // the amount of VICS a user has to deposit to create new proposalDeposit
        uint8 proposalReward;   // the percentage of proposalDeposit for awarding proposal settlement (for both approved and expired proposals).
                                // the remain part of proposalDeposit will go to operatorAddress.
        uint minCreatorDeposit; // the minimum amount that a bot creator has to deposit to the newly created bot.
    }

    DABotSetting internal _settings;

    constructor() {
        _settings.operatorAddress = _msgSender();
        _settings.proposalDeposit = 100 * 1e18;
        _settings.proposalReward = 70;
        _settings.minCreatorDeposit = 0;
    }

    /**
    @dev Gets the address of the platform operator.
     */
    function operatorAddress() external view override returns(address) {
        return _settings.operatorAddress;
    }
    
    /**
    @dev Gets the deposit amount (in VICS) that a person has to pay to create a proposal.
     */
    function proposalDeposit() external view override returns (uint) {
        return _settings.proposalDeposit;
    }
    
    function proposalReward() external view override returns (uint) {
        return _settings.proposalReward;
    }

    function minCreatorDeposit() external view override returns (uint) {
        return _settings.minCreatorDeposit;
    }
    
    function setOperatorAddress(address account) external onlyOwner {
        _settings.operatorAddress = account;

        emit OperatorAddressChanged(account);
    }
    
    function setProposalDeposit(uint amount) external onlyOwner {
        _settings.proposalDeposit = amount;

        emit ProposalDepositChanged(amount);
    }
    
    function setProposalReward(uint8 percentage) external onlyOwner {
        require(percentage <= 100, "DABotManager: value out of range.");
        _settings.proposalReward = percentage;

        emit ProposalRewardChanged(percentage);
    }

    function setMinCreatorDeposit(uint amount) external onlyOwner {
        _settings.minCreatorDeposit = amount;

        emit MinCreatorDepositChanged(amount);
    }
}

contract DABotManager is BotManagerSetting {

    IDABot[] private _bots;
    address[] private _templates;
    RoboFiFactory public factory;
    IRoboFiToken public vicsToken;
    address public certTokenMaster;

    mapping(address => bool) private _registeredTemplates;

    constructor(RoboFiFactory _factory, address vics, address _certTokenMaster) {
        factory = _factory;
        vicsToken = IRoboFiToken(vics);
        certTokenMaster = _certTokenMaster;
    }
    
    function totalBots() external view returns(uint) {
        return _bots.length;
    }

    /**
    @dev Registers a DABot template (i.e., master contract). Once registered, a bot template will
    never be remove.
     */
    function addTemplate(address template) public {
        require(!_registeredTemplates[template], "DABotManager: template existed");

        _registeredTemplates[template] = true;
        _templates.push(template);

        emit TemplateRegistered(template);
    }

    /**
    @dev Retrieves a list of registered DABot templates.
     */
    function templates() external view returns(address[] memory) {
        return _templates;
    }

    /**
    @dev Determine whether an address is a registered bot template.
     */
    function isRegisteredTemplate(address template) external view returns(bool) {
        return _registeredTemplates[template];
    } 

    /**
    @dev Deploys a bot for a given template.

    params:
        `template`  : address of the master contract containing the logic of the bot
        `name`      : name of the bot
        `setting`   : various settings of the bot. See {IDABot.sol\DABot.BotSetting}
     */
    function deployBot(address template, 
                        string calldata botName, 
                        DABotCommon.BotSetting calldata setting) external returns(uint botId, address bot) {
        require(_registeredTemplates[template], "DABotManager: unregistered template");

        bot = factory.deploy(template, abi.encode(botName, _msgSender(), setting), true);
        vicsToken.transferFrom(_msgSender(), bot, setting.initDeposit); 
        botId = _bots.length;
        _bots.push(IDABot(bot));

        emit BotDeployed(_msgSender(), address(template), botId, bot);
    }
    
    /**
    @dev Deploys a certificate token for a bot's porfolio asset.

    Should only be called internally by a bot.
     */
    function deployBotCertToken(address peggedAsset) external override returns(address token) {
        token = factory.deploy(certTokenMaster, abi.encode(peggedAsset, _msgSender()), false);

        emit CertTokenDeployed(_msgSender(), peggedAsset, token);
    }

    /**
    @dev Queries details information for a list of bot Id.
     */
    function queryBots(uint[] calldata botId) external view returns(DABotCommon.BotDetail[] memory output) {
        output = new DABotCommon.BotDetail[](botId.length);
        for(uint i = 0; i < botId.length; i++) {
            if (botId[i] >= _bots.length) continue;
            IDABot bot = _bots[botId[i]];
            output[i] = bot.botDetails();
            output[i].id = botId[i];
        }
    }

}

