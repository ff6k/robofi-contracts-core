// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../token/RoboFiTokenSnapshot.sol"; 
import "../token/IRoboFiToken.sol";
import "../Ownable.sol";
import "./IDABot.sol";
import "./CertToken.sol";
import "./CertLocker.sol";


abstract contract DABotShare {
    DABotCommon.BotSetting internal _setting;

    string constant ERR_PERMISSION_DENIED = "DABot: permission denied";
    string constant ERR_INVALID_PORTFOLIO_ASSET = "DABot: invalid portfolio asset";
    string constant ERR_INVALID_CERTIFICATE_ASSET = "DABot: invalid certificate asset";
    string constant ERR_PORTFOLIO_FULL = "DABot: portfolio is full";
    string constant ERR_ZERO_CAP = "DABot: cap must be positive";
    string constant ERR_INVALID_CAP = "DABot: cap must be greater than stake and ibo cap";
    string constant ERR_ZERO_WEIGHT = "DABot: weight must positive";
    string constant ERR_INSUFFICIENT_FUND = "DABot: insufficient fund";

    IRoboFiToken public immutable vicsToken;
    IDABotManager public immutable botManager;
    address public immutable voteController;
    address public immutable warmupLocker;
    address public immutable cooldownLocker;
    address public immutable masterContract = address(this);

    constructor( IRoboFiToken vics, 
                IDABotManager manager,
                address warmupMaster,
                address cooldownMaster,
                address voter) {
        vicsToken = vics;
        botManager = manager;
        warmupLocker = warmupMaster;
        cooldownLocker = cooldownMaster;
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
    
    function setStakingTime(uint warmup, uint cooldown, uint unit) external SettingGuard {
        _setting.setStakingTime(warmup, cooldown, unit);
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
    mapping(address => CertLocker[]) internal _warmup;
    mapping(address => CertLocker[]) internal _cooldown;

    event PortfolioUpdated(address indexed asset, address indexed certAsset, uint maxCap, uint weight);
    event AssetRemoved(address indexed asset);   
    event Stake(address indexed asset, address indexed account, address indexed  locker, uint amount);
    event Unstake(address indexed certToken, address indexed account, address indexed  locker, uint amount);

    /**
    @dev Gets the stake amount of a specific account of a stake-able asset.
     */
    function stakeBalanceOf(address account, IRoboFiToken asset) view public returns(uint) {
        return certificateOf(asset).balanceOf(account) 
                + warmupBalanceOf(account, asset);
    }

    /**
    @dev Gets the amount of (warm-up) locked certificate tokens.
     */
    function warmupBalanceOf(address account, IRoboFiToken asset) view public returns(uint) {
        CertLocker[] storage lockers = _warmup[account];
        return _lockedBalance(lockers, address(asset));
    }

    /**
    @dev Gets the amount of certificate tokens in cooldown period.
     */
    function cooldownBalanceOf(address account, CertToken certToken) view public returns(uint) {
        CertLocker[] storage lockers = _cooldown[account];
        return _lockedBalance(lockers, address(certToken.asset()));
    }

    function _lockedBalance(CertLocker[] storage lockers, address asset) view internal returns(uint result) {
        result = 0;
        for (uint i = 0; i < lockers.length; i++) 
            if (address(lockers[i].asset()) == asset)
                result += lockers[i].lockedBalance();
    }

   /**
    @dev Gets detail information of warming-up certificate tokens (for all staked assets).
    */
    function warmupDetails(address account) view public returns(DABotCommon.LockerInfoEx[] memory) {
        CertLocker[] storage lockers = _warmup[account];
        return _lockerInfo(lockers);
    }

    /**
    @dev Gets detail information of cool-down requests (for all certificate tokens)
     */
    function cooldownDetails(address account) view public returns(DABotCommon.LockerInfoEx[] memory) {
        CertLocker[] storage lockers = _cooldown[account];
         return _lockerInfo(lockers);
    }

    function _lockerInfo(CertLocker[] storage lockers) view internal returns(DABotCommon.LockerInfoEx[] memory result) {
        result = new DABotCommon.LockerInfoEx[](lockers.length);
        for (uint i = 0; i < lockers.length; i++) {
            result[i] = lockers[i].detail();
        }
    }

    /**
    @dev Itegrates all lockers of the caller, and try to unlock these lockers if time condition meets.
        The unlocked lockers will be removed from the global `_warmup`.

        The function will return when one of the below conditions meet:
        (1) 20 lockers has been unlocked,
        (2) All lockers have been checked
     */
    function releaseWarmup() public {
        CertLocker[] storage lockers = _warmup[_msgSender()];
        _releaseLocker(lockers);
    }

    function _releaseLocker(CertLocker[] storage lockers) internal {
        uint max = lockers.length < 20 ? lockers.length : 20;
        uint idx = 0;
        for (uint count = 0; count < max && idx < lockers.length;) {
            CertLocker locker = lockers[idx];
            if (!locker.tryUnlock()) {
                idx++;
                locker.finalize(); 
                continue;
            }
            lockers[idx] = lockers[lockers.length - 1];
            lockers.pop();
            count++;
        }
    }

    function releaseCooldown() public {
        CertLocker[] storage lockers = _cooldown[_msgSender()];
        _releaseLocker(lockers);
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
    function assetOf(address certToken) public view returns(IERC20) {
        return CertToken(certToken).asset(); 
    }

    /**
    @dev Retrieves the max stakable amount for the specified asset.

    During IBO, the max stakable amount is bound by the {portfolio[asset].iboCap}.
    After IBO, it is limited by {portfolio[asset].cap}.
     */
    function getMaxStake(IRoboFiToken asset) public view returns(uint) {
        if (block.timestamp < _setting.iboStartTime())
            return 0;

        DABotCommon.PortfolioAsset storage pAsset = _portfolio[asset];

        if (block.timestamp < _setting.iboEndTime())
            return pAsset.iboCap - pAsset.totalStake;

        return pAsset.cap - pAsset.totalStake;
    }

    /**
    @dev Stakes an mount of crypto asset to the bot and get back the certificate token.

    The staking function is only valid after the IBO starts and on ward. Before that calling 
    to this function will be failt.

    When users stake during IBO time, users will immediately get the certificate token. After the
    IBO time, certificate token will be issued after a [warm-up] period.
     */
    function stake(IRoboFiToken asset, uint amount) external virtual {
        if (amount == 0) return;

        DABotCommon.PortfolioAsset storage pAsset = _portfolio[asset];

        require(_setting.iboStartTime() <= block.timestamp, ERR_PERMISSION_DENIED);
        require(address(asset) != address(0), ERR_INVALID_PORTFOLIO_ASSET);
        require(pAsset.certAsset != address(0), ERR_INVALID_PORTFOLIO_ASSET);

        uint maxStakeAmount = getMaxStake(asset);
        require(maxStakeAmount > 0, ERR_PORTFOLIO_FULL);

        uint stakeAmount = amount > maxStakeAmount ? maxStakeAmount : amount;
        _mintCertificate(asset, stakeAmount);        
    }

    /**
    @dev Redeems an amount of certificate token to get back the original asset.

    All unstake requests are denied before ending of IBO.
     */
    function unstake(CertToken certAsset, uint amount) external virtual {
        if (amount == 0) return;
        IERC20 asset = certAsset.asset();
        require(address(asset) != address(0), ERR_INVALID_CERTIFICATE_ASSET);
        require(_setting.iboEndTime() <= block.timestamp, ERR_PERMISSION_DENIED);
        require(certAsset.balanceOf(_msgSender()) >= amount, ERR_INSUFFICIENT_FUND);

        _unstake(_msgSender(), certAsset, amount);
    }

    function _mintCertificate(IRoboFiToken asset, uint amount) internal {
        DABotCommon.PortfolioAsset storage pAsset = _portfolio[asset];
        asset.transferFrom(_msgSender(), address(pAsset.certAsset), amount);
        CertToken token = CertToken(pAsset.certAsset);
        uint duration = _setting.warmupTime() * _setting.getStakingTimeMultiplier();
        
        pAsset.totalStake += amount;
        address locker;

        if (duration == 0) {
            token.mintTo(address(0), _msgSender(), amount);
        } else {
            locker = botManager.factory().deploy(warmupLocker, 
                    abi.encode(address(this), _msgSender(), pAsset.certAsset, block.timestamp, block.timestamp + duration), true);
            _warmup[_msgSender()].push(WarmupLocker(locker));

            token.mintTo(address(0), locker, amount);
        }

        emit Stake(address(asset), _msgSender(), locker, amount);
    }

    function _unstake(address account, CertToken certToken, uint amount) internal virtual {
        uint duration = _setting.cooldownTime() * _setting.getStakingTimeMultiplier(); 

        if (duration == 0) {
            certToken.burn(_msgSender(), amount);
            emit Unstake(address(certToken), account, address(0), amount);
            return;
        }

        address locker = botManager.factory().deploy(cooldownLocker,
                abi.encode(address(this), _msgSender(), address(certToken), block.timestamp, block.timestamp + duration), true);

        _cooldown[account].push(CertLocker(locker));
        certToken.transferFrom(account, locker, amount);

        emit Unstake(address(certToken), account, locker, amount);
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
            require(block.timestamp < _setting.iboStartTime(), ERR_PERMISSION_DENIED);
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
    @dev Calculates the shares (g-tokens) available for purchasing for the specified account.

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
    @dev Returns the value (in VICS) of an amount of shares (g-token). 
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
                address warmupLocker,
                address cooldownLocker,
                address voter) RoboFiToken("", "", 0, _msgSender()) DABotShare(vics, manager, warmupLocker, cooldownLocker, voter) {
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