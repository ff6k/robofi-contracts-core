// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./RoboFiToken.sol";

/**
@dev Prepresent a token which is pegged by another asset. To mint a pegged token, users have
to deposit an amount of asset. At any time, users could get back the deposited asset by 
burning the pegged tokens. Pegged token is a kind of interest-beared token, which means 
that over time each minted pegged token could have higher value than the orginal deposited 
assets. However, it could suffer a loss, i.e., negative interest.

PeggedToken is used as the base of certificate token issued by DABot. Users stake their 
asset to the bot and get back certificate token. If the trading (done by DABot operators)
gets profit, holders of certificate token will get positive interest pro-rata to their 
staked amount. On the other hand, if the trading gets loss, certificate token holders 
will suffer the trading loss, also pro-rata to their staked amount.
 */
contract PeggedToken is RoboFiToken {

    IERC20 public asset;
    uint public pointSupply;

    address internal _owner;        // only token owner could mint and burn the token. 
                                    // in most cases, the token owner is the DABot, not human.
                                    
    mapping(address => uint) private _pointBalances;

    modifier onlyOwner() {
        require(_msgSender() == _owner, "PeggedToken: permission denied");
        _;
    }

    event Mint(address indexed recepient, uint256 amount, uint256 point);
    event ClaimReward(address indexed sender, uint256 rewards, uint256 point);

    constructor(string memory name, string memory symbol, IERC20 peggedAsset) RoboFiToken(name, symbol, 0, _msgSender()) {
        asset = peggedAsset;
        _owner = _msgSender();
    }

    function init(bytes calldata data) external virtual payable override {
        require(address(asset) == address(0), "PeggedToken: contract initialized");
        (_name, _symbol, asset, _owner) = abi.decode(data, (string, string, IERC20, address));
        asset.approve(_owner, type(uint256).max);
    }

    function finalize() external onlyOwner {
        require(totalSupply() == 0, "PeggedToken: need to burn all tokens first");

        selfdestruct(payable(_owner));
    }

    function mulPointRate(uint256 value) internal view returns (uint256) {
        return pointSupply == 0 ? value : (value * asset.balanceOf(address(this)) / pointSupply);
    }

    function divPointRate(uint256 value) internal view returns (uint256) {
        return pointSupply == 0 ? value: (value * pointSupply / asset.balanceOf(address(this)));
    } 

    function pointBalanceOf(address sender) external view returns (uint256) {
        return _pointBalances[sender];
    }

    function mint(address recepient, uint amount) external onlyOwner payable returns (uint256) {
        return _mint(recepient, recepient, amount);
    }

    function mintTo(address payor, address recepient, uint amount) external onlyOwner payable returns(uint256) {
        return _mint(payor, recepient, amount);
    }

    function _mint(address payor, address recepient, uint amount) internal returns(uint256 mintedPoint) {
        mintedPoint = divPointRate(amount);
        _transferToken(payor, amount);
        super._mint(recepient, amount);
        _pointBalances[recepient] += mintedPoint;
        pointSupply += mintedPoint;

        emit Mint(recepient, amount, mintedPoint);
    }

    function _transferToken(address payor, uint amount) internal virtual {
        if (payor != address(0))
            asset.transferFrom(payor, address(this), amount);
    }

    function burn(address account, uint amount) external onlyOwner {
        _burn(account, amount);
    }

    function burn(uint amount) external {
        _burn(_msgSender(), amount);
    }

    function claimReward() external returns(uint) {
        return _claimReward(_msgSender());
    }

    function claimRewardFor(address account) external onlyOwner returns(uint) {
        return _claimReward(account);
    }

    function _claimReward(address account) internal returns(uint reward) {
        reward = getClaimableReward(account);
        if (reward == 0)
            return 0;

        uint256 newPointBalance = divPointRate(balanceOf(account));
        uint256 diffPointBalance = _pointBalances[account] - newPointBalance;

        _pointBalances[account] = newPointBalance;
        pointSupply -= diffPointBalance;

        asset.transfer(account, reward);

        emit ClaimReward(account, reward, newPointBalance);
    }

    function getClaimableReward(address reciever) public view returns(uint) {
        uint256 pointValue = mulPointRate(_pointBalances[reciever]);
        uint256 balance = balanceOf(reciever);
        return pointValue >= balance ? pointValue - balance : 0;
    }

    function _beforeTokenTransfer(address sender, address, uint256) internal override {
        if (sender != address(0))
            _claimReward(sender);
    }

    function _afterTokenTransfer(address sender, address recipient, uint256 amount) internal override {
        uint256 point = amount * _pointBalances[sender] / (balanceOf(sender) + amount);

        _pointBalances[sender] -= point;

        if (recipient != address(0)) { // transfer point
            _pointBalances[recipient] += point;
        } else { // burn point
            pointSupply -= point;
            asset.transfer(sender, amount);
        }
    }
}