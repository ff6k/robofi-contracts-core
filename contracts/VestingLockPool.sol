// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./Ownable.sol";

contract VestingLockPool is Context, Ownable {

    struct VestPool {
        uint256 amount;        // the amount that will be released after the vesting period
        uint256 debt;           // the amount that user has withdrawn up till now
        uint256 release_start;  // the start of vesting period
        uint256 release_end;    // the end of vesting period 
        uint256 status;         // pool status: 0 - normal, 1 - canceled
    }

    mapping(address => VestPool) private _pools;
    IERC20 private _asset;

    event PoolCreated(address indexed poolOwner, uint256 amount, uint256 vest_start, uint256 vest_end);
    event PoolCanceled(address indexed poolOwner);
    event PoolWidthaw(address indexed poolOwner, uint256 amount, uint256 remain);
    event EmergencyWithdraw(address indexed poolOwner, uint256 amount, uint256 remain);

    constructor(IERC20 asset) {
        _asset = asset;
    }

    function createPool(address poolOwner, uint256 amount, uint256 vest_start, uint256 vest_end) external onlyOwner {
        VestPool storage pool = _pools[poolOwner];

        require(vest_end > vest_start, "invalid vesting period");
        require(pool.status == 0, "pool is canceled");
        
        _asset.transferFrom(owner(), address(this), amount);

        pool.amount += amount;
        pool.release_start = vest_start;
        pool.release_end = vest_end;

        emit PoolCreated(poolOwner, pool.amount, vest_start, vest_end);
    }
    
    function resetPool(address poolOwner) external onlyOwner {
        VestPool storage pool = _pools[poolOwner];
        require(pool.status == 1, "pool is active");
        
        delete _pools[poolOwner];
    }

    /**
     * @dev cancels a pool and trasfers fund of this pool back to owner address.
     * 
     * this is for emergency purpose only.
     */ 
    function cancelPool(address poolOwner) external onlyOwner {
        VestPool storage pool = _pools[poolOwner];

        require(pool.status == 0, "pool is canceled");

        pool.status = 1;
        _asset.transfer(owner(), pool.amount - pool.debt);

        emit PoolCanceled(poolOwner);
    }

    function availableOf(address poolOwner) public view returns(uint256) {
        VestPool storage pool = _pools[poolOwner];

        if (pool.status == 1 || pool.amount == 0)  
            return 0;

        uint256 moment = block.timestamp < pool.release_end ? block.timestamp : pool.release_end;
        uint256 fund = pool.amount * (moment - pool.release_start) / (pool.release_end - pool.release_start);
        return fund >= pool.debt ? fund - pool.debt : 0;
    }
    
    function poolOf(address poolOwner) external view returns(uint256 balance, uint256 available, uint256 vest_start, uint256 vest_end, uint256 status) {
        VestPool storage pool = _pools[poolOwner];
        
        balance = pool.amount - pool.debt;
        available = availableOf(poolOwner);
        vest_start = pool.release_start;
        vest_end = pool.release_end;
        status = pool.status;
    }

    function withdraw(uint256 amount) external {
        address poolOwner = _msgSender();
        VestPool storage pool = _pools[poolOwner];
        uint256 available = availableOf(poolOwner);

        require(available >= amount, "insufficient fund");
        pool.debt += amount;

        _asset.transfer(poolOwner, amount);

        emit PoolWidthaw(poolOwner, amount, available - amount);
    }
    
    /**
     * @dev allows poolOwner to withdraw fund before vesting period
     * 
     * for emergency usage only.
     */ 
    function emergencyWithdraw(address poolOwner, uint amount) external onlyOwner {
        VestPool storage pool = _pools[poolOwner];
        uint256 balance = pool.amount - pool.debt;
        
        require(balance >= amount, "insufficient fund");
        pool.debt += amount;

        _asset.transfer(poolOwner, amount);

        emit EmergencyWithdraw(poolOwner, amount, balance - amount);
    }
}