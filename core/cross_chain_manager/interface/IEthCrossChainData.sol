// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

/**
 * @dev Interface of the EthCrossChainData contract, the implementation is in EthCrossChainData.sol
 */
interface IEthCrossChainData {
    function putCurEpochConPubKeyBytes(address[] calldata curEpochPkBytes) external returns (bool);

    function getCurEpochConPubKeyBytes() external view returns (address[] memory);

    function markFromChainTxExist(uint64 fromChainId, bytes32 fromChainTx) external returns (bool);

    function checkIfFromChainTxExist(uint64 fromChainId, bytes32 fromChainTx) external view returns (bool);

    function getEthTxHashIndex() external view returns (uint256);

    function putEthTxHash(bytes32 ethTxHash) external returns (bool);

    function pause() external returns (bool);

    function unpause() external returns (bool);
}