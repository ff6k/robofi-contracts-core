// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMasterContract {
    function init(bytes calldata data) external payable;
}