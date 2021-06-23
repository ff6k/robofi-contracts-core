// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../token/PeggedToken.sol";
import "./IDABot.sol";

contract CertToken is PeggedToken {

    constructor() PeggedToken("", "", IERC20(address(0))) {

    } 

    function init(bytes calldata data) external virtual payable override {
        require(address(asset) == address(0), "CertToken: contract initialized");
        (asset, _owner) = abi.decode(data, (IERC20, address));
    }

    function name() public view override returns(string memory) {
        IDABot bot = IDABot(_owner);
        return string(abi.encodePacked(bot.name(), " ", IRoboFiToken(address(asset)).name(), " Certificate"));
    }

    function symbol() public view override returns(string memory) {
        IDABot bot = IDABot(_owner);
        return string(abi.encodePacked(bot.symbol(), IRoboFiToken(address(asset)).symbol()));
    }

    function decimals() public view override returns (uint8) {
        return IRoboFiToken(address(asset)).decimals();
    }

    function _transferToken(address recepient, uint amount) internal override {
        // Do nothing, the token should be transfer from the owner bot.
    }
}