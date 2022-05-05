// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface ILinQNFTLockProxy {
    function managerProxyContract() external view returns (address);
}