// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IDABot.sol";
import "../token/PeggedToken.sol";

/**
@dev CertToken is a familiy of ERC20-compliant token which are issued by a DABot
to represent users' staked assets. A DABot could accept several staked assets. Each
staked asset will have a corresponding CertToken. By staking to a DABot, users recieve
an equivalent amount of CertToken. These CertToken tokens are used to claim interests as
well as the staked assets.

The interest of CertToken comes from the trading activities of a DABot. This means the 
interest could be either positve or negative.
 */
contract CertToken is PeggedToken {

    constructor() PeggedToken("", "", IERC20(address(0))) {

    } 

    function init(bytes calldata data) external virtual payable override {
        require(address(asset) == address(0), "CertToken: contract initialized");
        (asset, _owner) = abi.decode(data, (IERC20, address));
    }

    function name() public view override returns(string memory) {
        IDABot bot = IDABot(_owner);
        return string(abi.encodePacked(bot.botname(), " ", IRoboFiToken(address(asset)).symbol(), " Certificate"));
    }

    function symbol() public view override returns(string memory) {
        IDABot bot = IDABot(_owner);
        return string(abi.encodePacked(bot.symbol(), IRoboFiToken(address(asset)).symbol()));
    }

    function decimals() public view override returns (uint8) {
        return IRoboFiToken(address(asset)).decimals();
    }

    function _transferToken(address payor, uint amount) internal override {
        // Do nothing, the token should be transfer from the owner bot.
    }
}