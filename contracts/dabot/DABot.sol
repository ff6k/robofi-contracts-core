// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../token/RoboFiTokenSnapshot.sol"; 
import "../token/IRoboFiToken.sol";
import "../Ownable.sol";
import "./IDABot.sol";
import "./CertToken.sol";


abstract contract DABotShare {
    DABotCommon.BotSetting internal _setting;

    string constant ERR_PERMISSION_DENIED = "DABot: permission denied";
    string constant ERR_INVALID_PORTFOLIO_ASSET = "DABot: invalid portfolio asset";
    string constant ERR_INVALID_CERTIFICATE_ASSET = "DABot: invalid certificate asset";
    string constant ERR_INVALID_STAKE_AMOUNT = "DABot: invalid stake amount";
    string constant ERR_ZERO_CAP = "DABot: cap must be positive";
    string constant ERR_INVALID_CAP = "DABot: cap must be greater than stake and ibo cap";
    string constant ERR_ZERO_WEIGHT = "DABot: weight must positive";

    IRoboFiToken public immutable vicsToken;
    IDABotManager public immutable botManager;
    address public immutable voteController;
    address public immutable masterContract = address(this);

    constructor( IRoboFiToken vics, 
                IDABotManager manager,
                address voter) {
        vicsToken = vics;
        botManager = manager;
        voteController = voter;
    }
}

abstract contract DABotSetting is DABotShare {

    using DABotCommon for DABotCommon.BotSetting;
    
    /**
    @dev Ensure the modification of bot settings to comply with the following rule:

    Before the IBO time, bot owner could freely change the bot setting.
    After the IBO has started, bot settings must be changed via the voting protocol.
     */
    modifier SettingGuard() {
        require(settable(msg.sender), ERR_PERMISSION_DENIED);
        _;
    }

    function settable(address) view internal virtual returns(bool);

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

abstract contract DABotStaking is DABotShare, Context, Ownable {
    using DABotCommon for DABotCommon.BotSetting;

    IRoboFiToken[] internal _assets; 
    mapping(IRoboFiToken => DABotCommon.PortfolioAsset) internal _portfolio;

    event PortfolioUpdated(address indexed asset, address indexed certAsset, uint maxCap, uint weight);
    event AssetRemoved(address indexed asset);   
    event Stake(address indexed asset, address indexed account, uint amount);

    /**
    @dev Gets the stake amount of a specific account of a stake-able asset.
     */
    function stakeBalanceOf(address account, IRoboFiToken asset) view public returns(uint) {
        // TODO: to consider stake in warming up
        return certificateOf(asset).balanceOf(account);
    }

    /**
    @dev Gets the address of the certification token contract for the specified asset.
     */
    function certificateOf(IRoboFiToken asset) public view returns(CertToken) {
        return CertToken(_portfolio[asset].certAsset);
    }

    /**
    @dev Get the crypto asset corresponding to the specified certificate token.
     */
    function assetOf(address certToken) public view returns(IRoboFiToken) {
        for (uint8 i = 0; i < _assets.length; i++)
            if (_portfolio[_assets[i]].certAsset == certToken) return _assets[i];

        return IRoboFiToken(address(0));
    }

    /**
    @dev Stakes an mount of crypto asset to the bot and get back the certificate token.

    The staking function is only valid after the IBO starts and on ward. Before that calling 
    to this function will be failt.

    When users stake during IBO time, users will immediately get the certificate token. After the
    IBO time, certificate token will be issued after a [warm-up] period.

    TODO: support warm-up feature to release token 
     */
    function stake(IRoboFiToken asset, uint amount) external virtual {
        require(_setting.iboStartTime() <= block.timestamp, ERR_PERMISSION_DENIED);
        require(address(asset) != address(0), ERR_INVALID_PORTFOLIO_ASSET);

        DABotCommon.PortfolioAsset storage pAsset = _portfolio[asset];
        require(pAsset.certAsset != address(0), ERR_INVALID_PORTFOLIO_ASSET);
        
        uint stakeAmount = (pAsset.totalStake + amount) > pAsset.cap ? pAsset.cap - pAsset.totalStake : amount;
        require(stakeAmount > 0, ERR_INVALID_STAKE_AMOUNT);

        _mintCertificate(asset, stakeAmount);

        emit Stake(address(asset), _msgSender(), stakeAmount);
    }

    /**
    @dev Redeems an amount of certificate token to get back the original asset.

    TODO: support cool-down feature to release asset.
     */
    function unstake(CertToken certAsset, uint amount) external virtual {
        IRoboFiToken asset = assetOf(address(certAsset));
        require(address(asset) != address(0), ERR_INVALID_CERTIFICATE_ASSET);

        certAsset.burn(_msgSender(), amount);
    }

    function _mintCertificate(IRoboFiToken asset, uint amount) internal {
        DABotCommon.PortfolioAsset storage pAsset = _portfolio[asset];
        asset.transferFrom(_msgSender(), address(pAsset.certAsset), amount);

        CertToken token = CertToken(pAsset.certAsset);
        // TODO: to implement warm-up feature
        token.mint(_msgSender(), amount);
        pAsset.totalStake += amount;
    }

    /**
    @dev Adds (or updates) a stake-able asset in the portfolio. 
     */
    function updatePortfolio(IRoboFiToken asset, uint maxCap, uint iboCap, uint weight) external onlyOwner {
        _updatePortfolio(asset, maxCap, iboCap, weight);
    }

    /**
    @dev Removes an asset from the bot's porfolio. 

    It requires that none is currently staking to this asset. Otherwise, the transaction fails.
     */
    function removeAsset(IRoboFiToken asset) public onlyOwner {
        _removeAsset(asset);
    }

    /**
    @dev Adds (or updates) a stake-able asset in the portfolio. 
     */
    function _updatePortfolio(IRoboFiToken asset, uint maxCap, uint iboCap, uint weight) internal {
        require(address(asset) != address(0), ERR_INVALID_PORTFOLIO_ASSET);

        DABotCommon.PortfolioAsset storage pAsset = _portfolio[asset];

        if (address(pAsset.certAsset) == address(0)) {
            require(block.timestamp < _setting.iboStartTime(), "");
            require(maxCap > 0, ERR_ZERO_CAP);
            require(weight > 0, ERR_ZERO_WEIGHT);
            pAsset.certAsset = botManager.deployBotCertToken(address(asset));
            _assets.push(asset);
        }

        if (maxCap > 0) pAsset.cap = maxCap;
        if (iboCap > 0) pAsset.iboCap = iboCap;
        if (weight > 0) pAsset.weight = weight;

        require((pAsset.cap >= pAsset.totalStake) && (pAsset.cap >= pAsset.iboCap), ERR_INVALID_CAP);
        
        emit PortfolioUpdated(address(asset), address(pAsset.certAsset), maxCap, weight);
    }

    function _removeAsset(IRoboFiToken asset) internal {
        require(address(asset) != address(0), "DABot: null asset");
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
}

abstract contract DABotGovernance is DABotShare, DABotStaking, RoboFiTokenSnapshot {
    using DABotCommon for DABotCommon.BotSetting;

   

    /**
    @dev Calculates the shares available for purchasing for the specified account.

    During the IBO time, the amount of available shares for purchasing is derived from
    the staked asset (refer to the Concept Paper for details). 
    
    After IBO, the availalbe amount equals to the uncirculated amount of goveranance tokens.
     */
    function availableSharesFor(address account) view public virtual returns(uint) {
        if (block.timestamp < _setting.iboStartTime()) return 0;
        if (block.timestamp > _setting.iboEndTime()) return _setting.maxShare - totalSupply();

        uint totalWeight = 0;
        uint totalPoint = 0;
        for (uint i = 0; i < _assets.length; i ++) {
            IRoboFiToken asset = _assets[i];
            DABotCommon.PortfolioAsset storage pAsset = _portfolio[asset];
            totalPoint += stakeBalanceOf(account, asset) * pAsset.weight / pAsset.iboCap;
            totalWeight += pAsset.weight;
        }

        return _setting.iboShare * totalPoint / totalWeight;
    }

    /**
    @dev Returns the value (in VICS) of an amount of shares. 
    The returned value depends on the amount of circulated bot's share tokens, and the amount
    of deposited VICS inside the bot.
     */
    function shareValue(uint amount) view public returns (uint) {
        return amount * vicsToken.balanceOf(address(this)) / totalSupply();
    }

    /**
    @dev Deposits an amount of VICS to the bot and get the equivalent governance token (i.e., Bots' shares).

    
     */
    function deposit(uint vicsAmount) public virtual {
        _deposit(_msgSender(), vicsAmount);
    }

    function _deposit(address account, uint vicsAmount) internal virtual {
        uint fee;
        uint shares;
        uint payment;
        (payment, shares, fee) = calcOutShares(account, vicsAmount);
        vicsToken.transferFrom(account, botManager.taxAddress(), fee); 
        vicsToken.transferFrom(account, address(this), payment);
        _mint(account, shares);
    }

     /**
    @dev Calculates the ouput government tokens, given the input VICS amount. 

    The function returns three outputs:
        * shares: the output governenent tokens that could be purchased with the given input
                  VICS amount, and other constraints (i.e., IBO time, stake amount.)
        * payment: the amount of VICS (without fee) will be deposited to the bot.
        * fee: the commission fee to transfer to the operator address 

     */
    function calcOutShares(address account, uint vicsAmount) view public virtual returns(uint payment, uint shares, uint fee) {
        uint priceMultipler = 100; 
        uint commission = 0;
        if (block.timestamp >= _setting.iboEndTime()) {
            priceMultipler = _setting.priceMultiplier();
            commission = _setting.commission();
        }
        uint outAmount = (10000 - commission) * vicsAmount *  _setting.initFounderShare / priceMultipler / _setting.initDeposit / 100; 
        uint maxAmount = availableSharesFor(account);

        if (outAmount <= maxAmount) {
            shares = outAmount;
            fee = vicsAmount * commission / 10000; 
            payment = vicsAmount - fee;
        } else {
            shares = maxAmount;
            payment = maxAmount * _setting.initDeposit * priceMultipler / _setting.initFounderShare / 100;
            fee = payment * commission / (1000 - commission);
        }
    }

    /**
    @dev Burns the bot's shares to get back VICS. The amount of returned VICS is proportional of amount
    of circulated bot's shares and deposited VICS.
     */
    function redeem(uint amount) public virtual {
        _redeem(_msgSender(), amount);
    }

    function _redeem(address account, uint amount) internal virtual {
        uint value = shareValue(amount);
        _burn(account, amount);
        vicsToken.transfer(account, value);
    }
}

/**
@dev Base contract module for a DABot.
 */
contract DABotBase is DABotSetting, DABotGovernance {

    using DABotCommon for DABotCommon.BotSetting;

    string private _botname;

    constructor(string memory templateName, 
                IRoboFiToken vics, 
                IDABotManager manager,
                address voter) RoboFiToken("", "", 0, _msgSender()) DABotShare(vics, manager, voter) {
        _botname = templateName;
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

    function settable(address account) view internal override returns(bool) {
        if (block.timestamp > _setting.iboStartTime())
            return (account == voteController);
        return(account == owner());
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


}