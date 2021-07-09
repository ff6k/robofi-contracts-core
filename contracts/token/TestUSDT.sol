// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Ownable.sol";
import "./RoboFiToken.sol";

contract TestUSDT is RoboFiToken, Ownable {

    constructor (uint256 initAmount_) 
        RoboFiToken("Test USDT", "USDT", initAmount_ * 1e18, _msgSender()) {
    }
    
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

}