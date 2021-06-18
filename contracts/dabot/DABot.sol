// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../token/RoboFiTokenSnapshot.sol"; 
import "../token/IRoboFiToken.sol";
import "../Ownable.sol";
import "./IDABot.sol";
import "./CertToken.sol";

abstract contract DABotSetting {
    using DABotCommon for DABotCommon.BotSetting;
}

/**
@dev Base contract module for a DABot.
 */
contract DABotBase is RoboFiTokenSnapshot, Ownable {

    using DABotCommon for DABotCommon.BotSetting;

    string constant PERMISSION_DENIED = "DABot: permission denied";

    string private _botname;
    DABotCommon.BotSetting private _setting;
    IRoboFiToken[] _assets; 
    mapping(IRoboFiToken => DABotCommon.PortfolioAsset) private _portfolio;

    address public immutable voteController; 
    IRoboFiToken public immutable vicsToken;
    IDABotManager public immutable botManager;
    address public immutable masterContract = address(this);

    event PortfolioUpdated(address indexed asset, address indexed certAsset, uint maxCap, uint weight);
    event AssetRemoved(address indexed asset);
    

    /**
    @dev Ensure the modification of bot settings to comply with the following rule:

    Before the IBO time, bot owner could freely change the bot setting.
    After the IBO has started, bot settings must be changed via the voting protocol.
     */
    modifier SettingGuard() {
        if (block.timestamp > _setting.iboStartTime())
            require(_msgSender() == voteController, PERMISSION_DENIED);
        else 
            require(_msgSender() == owner(), PERMISSION_DENIED);
        _;
    }

    constructor(string memory templateName, 
                IRoboFiToken vics, 
                IDABotManager manager,
                address voter) RoboFiToken("", "", 0, _msgSender()) {
        _botname = templateName;
        vicsToken = vics;
        botManager = manager;
        voteController = voter;
    }

    /**
    @dev Initializes this bot instance. Should be called internally from a factory.
     */
    function init(bytes calldata data) external virtual payable override {
        require(owner() == address(0), "DABot: bot has been initialized");
        address holder;
        (_botname, holder, _setting) = abi.decode(data, (string, address, DABotCommon.BotSetting));

        require(_setting.iboEndTime() > _setting.iboStartTime(), "DABot: IBO end time is less than start time");
        require(_setting.initDeposit >= botManager.minCreatorDeposit(), "DABot: insufficient deposit");
        require(_setting.initFounderShare > 0, "DABot: positive founder share required");
        require(_setting.maxShare >= _setting.initFounderShare + _setting.iboShare, "DABot: insufficient max share");

        _transferOwnership(holder);
        _mint(holder, _setting.initFounderShare);
    }

    function symbol() public view override returns(string memory) {
        return string(abi.encodePacked(_botname, "GToken"));
    }

    function name() public view override returns(string memory) {
        return string(abi.encodePacked(_botname, ' ', "Governance Token"));
    }

    function botname() view external virtual returns(string memory) {
        return _botname;
    }

    /**
    @dev Reads the version of this contract.
     */
    function version() pure external virtual returns(string memory) {
        return "1.0";
    }

    /**
    @dev Retrieves the detailed information of this DABot. 
     */
    function botDetails() view external returns(DABotCommon.BotDetail memory output) {
        output.botAddress = address(this);
        output.masterContract = masterContract;
        output.name = _botname;
        output.templateName = IDABot(masterContract).botname();
        output.templateVersion = IDABot(masterContract).version();
        output.iboStartTime = _setting.iboStartTime();
        output.iboEndTime = _setting.iboEndTime();
        output.warmup = _setting.warmupTime();
        output.cooldown = _setting.cooldownTime();
        output.priceMul = _setting.priceMultiplier();
        output.commissionFee = _setting.commission();
        output.profitSharing = _setting.profitSharing;
        output.initDeposit = _setting.initDeposit;
        output.initFounderShare = _setting.initFounderShare;
        output.maxShare = _setting.maxShare;
        output.iboShare = _setting.iboShare;
        output.circulatedShare = totalSupply();
        output.userShare = balanceOf(_msgSender());
        output.portfolio = portfolio();
    }

    /**
    @dev Gets the stake amount of a specific account of a stake-able asset.
     */
    function stakeBalanceOf(address /*account*/, IRoboFiToken /*asset*/) pure public returns(uint) {
        return 0;
    }

    /**
    @dev Gets the address of the certification token contract for the specified asset.
     */
    function certifiateOf(IRoboFiToken asset) public view returns(address) {
        return _portfolio[asset].certAsset;
    }

    /**
    @dev Adds (or updates) a stake-able asset in the portfolio. 
     */
    function updatePortfolio(IRoboFiToken asset, uint maxCap, uint iboCap, uint weight) external onlyOwner {
        require(address(asset) != address(0), "DABot: null portfolio asset");
        require(maxCap >= _portfolio[asset].totalStake, "DABot: new cap less than staked amount");

        DABotCommon.PortfolioAsset storage pAsset = _portfolio[asset];

        if (address(pAsset.certAsset) == address(0)) {
            require(maxCap > 0, "DABot: positive maxCap required");
            require(weight > 0, "DABot: positive weight required");
            pAsset.certAsset = botManager.deployBotCertToken(address(asset));
        }

        if (maxCap > 0) pAsset.cap = maxCap;
        if (iboCap > 0) pAsset.iboCap = iboCap;
        if (weight > 0) pAsset.weight = weight;

        require(pAsset.cap >= pAsset.iboCap, "DABot: max cap is less than ibo cap");
        
        emit PortfolioUpdated(address(asset), address(pAsset.certAsset), maxCap, weight);
    }

    /**
    @dev Removes an asset from the bot's porfolio. 

    It requires that none is currently staking to this asset. Otherwise, the transaction fails.
     */
    function removeAsset(IRoboFiToken asset) public onlyOwner {
        require(address(asset) != address(0), "DABot: null asset");
        _removeAsset(asset);
    }

    function _removeAsset(IRoboFiToken asset) internal {
        uint i = 0;
        while (i < _assets.length && _assets[i] != asset) i++;
        require(i < _assets.length, "DABot: asset not found");
        CertToken(_portfolio[asset].certAsset).finalize();
        delete _portfolio[asset];
        _assets[i] = _assets[_assets.length - 1];
        _assets.pop();

        emit AssetRemoved(address(asset));
    }

    /**
    @dev Retrieves the porfolio of this DABot, including stake amount of the caller for each asset.
     */
    function portfolio() view public returns(DABotCommon.UserPortfolioAsset[] memory output) {
        output = new DABotCommon.UserPortfolioAsset[](_assets.length);
        for(uint i = 0; i < _assets.length; i++) {
            output[i].asset = address(_assets[i]);
            output[i].info = _portfolio[_assets[i]];
            output[i].userStake = stakeBalanceOf(_msgSender(), _assets[i]);
        }
    }

    /**
    @dev Calculate the ouput government tokens, given the input VICS amount.
     */
    function calcOutToken(uint vicsAmount, uint priceMul, uint commission) view public returns(uint) {
        uint multiplier = 100; 
        if (block.timestamp >= _setting.iboEndTime())
            multiplier = _setting.priceMultiplier();
        return (10000 - commission) * vicsAmount *  _setting.initFounderShare / priceMul  /  _setting.initDeposit / 100;
    }

    /**
    @dev Retrieves the IBO period of this bot.
     */
    function iboTime() view external returns(uint startTime, uint endTime) {
        startTime = _setting.iboStartTime();
        endTime = _setting.iboEndTime();
    }

    /**
    @dev Retrieves the staking settings of this bot, including the warm-up and cool-down time.
     */
    function stakingTime() view external returns(uint warmup, uint cooldown) {
        warmup = _setting.warmupTime();
        cooldown = _setting.cooldownTime();
    }

    /**
    @dev Retrieves the pricing policy of this bot, including the after-IBO price multiplier and commission.
     */
    function pricePolicy() view external returns(uint priceMul, uint commission) {
        priceMul = _setting.priceMultiplier();
        commission = _setting.commission();
    }

    /**
    @dev Retrieves the profit sharing scheme of this bot.
     */
    function profitSharing() view external returns(uint144) {
        return _setting.profitSharing;
    }

    function setIBOTime(uint startTime, uint endTime) external SettingGuard {
        _setting.setIboTime(startTime, endTime);
    }
    
    function setStakingTime(uint warmup, uint cooldown) external SettingGuard {
        _setting.setStakingTime(warmup, cooldown);
    }

    function setPricePolicy(uint priceMul, uint commission) external SettingGuard {
        _setting.setPricePolicy(priceMul, commission);
    }

    function setProfitSharing(uint sharingScheme) external SettingGuard {
        _setting.setProfitShare(sharingScheme);
    }
}