// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./Ownable.sol";

contract PrivateSaleLock is Context, Ownable {

    struct PrivateSale {
        uint256 balance;
        uint256 unlock;
    }

    mapping (address => PrivateSale) private _sales;
    IERC20 private _token;

    event Sale(address indexed recipient, uint256 amount);
    event CancelSale(address indexed recipient, uint256 amount);
    event Unlock(address indexed recipient, uint256 amount);
    event Withdraw(address indexed recipient, uint256 amount);

    constructor(IERC20 token) {
        _token = token;
    }

    function unlock(address recipient, uint256 amount) external onlyOwner {
        PrivateSale storage userSale = _sales[recipient];
        require(amount + userSale.unlock <= userSale.balance, 'PrivateSale: amount to unlock exceed balance');
        userSale.unlock += amount;       
        emit Unlock(recipient, amount);
    }

    function getSaleDetail(address account) external view returns (uint256 balance, uint256 unlockAmount) {
        address sender = _msgSender();
        require(sender == owner() || sender == account, "PrivateSale: either contract owner or account owner required");
        PrivateSale storage userSale = _sales[account];
        return (userSale.balance, userSale.unlock);
    }

    function sale(address recipient, uint256 amount) external {
        _sales[recipient].balance += amount;
        _token.transferFrom(_msgSender(), address(this), amount);

        emit Sale(recipient, amount);
    }
    
    function cancelSale(address recipient) external onlyOwner {
        uint256 balance = _sales[recipient].balance;
        delete _sales[recipient];
        _token.transfer(_msgSender(), balance);
        
        emit CancelSale(recipient, balance);
    }

    function withdraw() external {
        address recipient = _msgSender();
        PrivateSale storage userSale = _sales[recipient];

        uint256 amount = userSale.unlock;
        require(amount <= _sales[recipient].balance);

        _token.transfer(recipient, amount);

        userSale.balance -= amount;
        userSale.unlock -= amount;

        emit Withdraw(recipient, amount);
    }
}