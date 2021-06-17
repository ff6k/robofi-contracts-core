// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Ownable.sol";
import "../token/RoboFiToken.sol";
import "./ITreasuryAsset.sol";

contract TreasuryAsset is RoboFiToken, Ownable, ITreasuryAsset {

    IRoboFiToken public asset;
    address public fundManager;

    mapping(address => uint256) private _lockedBalance;
    mapping(address => bool) private _bots;

    constructor(IRoboFiToken baseAsset_, 
                address fundManager_) RoboFiToken("", "", 0, address(0)) {
        require(fundManager_ != address(0), "TreasuryAsset: fund manager is empty");
        fundManager = fundManager_;
        asset = baseAsset_;
    }

    /// @notice Serves as the constructor for clones, as clones can't have a regular constructor
    /// @dev `data` is abi encoded in the format: (IRoboFiToken baseasset, address fundmanager, address owner)
    function init(bytes calldata data) public payable override {
        require(address(asset) == address(0), "TreasuryAsset: contract initialized");
        address _owner;
        (asset, fundManager, _owner) = abi.decode(data, (IRoboFiToken, address, address));
        _transferOwnership(_owner);
    }

    function symbol() public view override returns(string memory) {
        return string(abi.encodePacked("s", asset.symbol()));
    }

    function name() public view override returns(string memory) {
        return string(abi.encodePacked("RoboFi Stakable ", asset.name()));
    }

    function decimals() public view override returns (uint8) {
        return asset.decimals();
    }

    /**
    @dev Set the address of the fund manager for this treasury asset
    **/
    function setFundManager(address newFundManager) external onlyOwner override {
        fundManager = newFundManager;
        emit FundManagerChanged(fundManager);
    }

    /**
    @dev Deposits `amount` of original asset, and gets back an equivalent amount of token.
    **/
    function mint(address to, uint256 amount) public virtual override {
        require(amount > 0, "Treasury: zero amount");

        asset.transferFrom(_msgSender(), address(this), amount);
        _mint(to, amount);
    }

    /**
    @dev Registers a DABot at the specified address. This is only called by the fund manager.
     */
    function addBot(address bot) external onlyOwner override {
        require(bot != address(0), "Treasury: empty bot address");
        _bots[bot] = true;
        emit BotAdded(bot);
    }

    /**
    @dev Burns `amount` of sToken WITHOUT get back the original tokens (this is for trading loss). 
    Only accept calls from registred DABot.
     */
    function tradeLoss(uint256 amount) external override {
        address bot = _msgSender();
        require(_bots[bot], "Treasury: permission denied");
        _internalBurn(bot, amount);
        emit TradeLoss(bot, amount);
    }

    /**
    @dev Locks `amount` of token from the caller's account (caller). An equivalent amount of 
    original asset will transfer to the fund manager.
    **/    
    function lock(uint256 amount) public virtual override {
        if (amount == 0) return;
        
        address _caller = _msgSender();
        require(_lockedBalance[_caller] + amount <= balanceOf(_caller), "Treasury: insufficient balance to lock");

        _lockedBalance[_caller] += amount;
        asset.transfer(fundManager, amount);

        emit Lock(_caller, amount);
    }

    /**
    @dev Get the locked amounts of sToken for `user`
    **/
    function lockedBalanceOf(address account) public view virtual override returns (uint256) {
        return _lockedBalance[account];
    }

    /**
    @dev Gets `amount` of tocken from the caller account, and decrease the locked balance of `receipient`. 
    **/
    function unlock(address receipient, uint256 amount) public virtual override {
        uint256 _amount = _lockedBalance[receipient] > amount ? amount : _lockedBalance[receipient];

        _lockedBalance[receipient] -= _amount;
        asset.transferFrom(_msgSender(), address(this), _amount);

        emit Unlock(_msgSender(), _amount, receipient);
    }

    /**
    @dev Burns `amount` of sToken to get back original  tokens
     */
    function burn(uint256 amount) public virtual override {
        address _caller = _msgSender();
        _burn(_caller, amount);
        asset.transfer(_caller, amount);
    }

    function _beforeTokenTransfer(address from, address, uint256 amount) internal virtual override {
        if (from == address(0)) // do nothing for minting
            return;
        uint256 _available = balanceOf(from) - _lockedBalance[from];
        require(_available >= amount, "Treasury: amount execeed available balance");
    }
}