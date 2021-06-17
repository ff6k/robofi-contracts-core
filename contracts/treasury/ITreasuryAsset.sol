// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface ITreasuryAsset {

    /**
    @dev Set the address of the fund manager for this treasury asset
    **/
    function setFundManager(address newFundManager) external;

    /**
    @dev Deposits `amount` of original asset, and gets back an equivalent amount of token.
    **/
    function mint(address to, uint256 amount) external;

    /**
    @dev Burns `amount` of sToken to get back original  tokens
     */
    function burn(uint256 amount) external;

    /**
    @dev Registers a DABot at the specified address. This is only called by the fund manager.
     */
    function addBot(address bot) external;

    /**
    @dev Burns `amount` of sToken WITHOUT get back the original tokens (this is for trading loss). 
    Only accept calls from registred DABot.
     */
    function tradeLoss(uint256 amount) external;

    /**
    @dev Locks `amount` of token from the caller's account. An equivalent amount of 
    original asset will be transferred to the fund manager.

    Return the locked balanced of the caller's account.
    **/    
    function lock(uint256 amount) external;

    /**
    @dev Get the locked amounts of sToken for `user`
    **/
    function lockedBalanceOf(address user) external view returns (uint256);

    /**
    @dev Gets `amount` of tocken from the caller account, and decrease the locked balance of `user`. 
    **/
    function unlock(address user, uint256 amount) external;

    event Lock(address indexed account, uint256 amount);
    event Unlock(address indexed caller, uint256 amount, address indexed account);
    event BotAdded(address indexed bot);
    event TradeLoss(address indexed bot, uint256 amount);
    event FundManagerChanged(address indexed fundmanager);
}