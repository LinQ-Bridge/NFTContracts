// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

/**
 * @dev Interface of upgradableECCM to make ECCM be upgradable, the implementation is in UpgradableECCM.sol
 */
interface IUpgradableECCM {
    function pause() external returns (bool);

    function unpause() external returns (bool);

    function paused() external view returns (bool);

    function upgradeToNew(address) external returns (bool);

    function isOwner() external view returns (bool);

    function setChainId(uint64 _newChainId) external returns (bool);
}
