// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./../../../libs/ownership/Ownable.sol";
import "./../../../libs/lifecycle/Pausable.sol";
import "./../interface/IEthCrossChainData.sol";

contract EthCrossChainData is IEthCrossChainData, Ownable, Pausable {
    /*
     Ethereum cross chain tx hash indexed by the automatically increased index.
     This map exists for the reason that linq network can verify the existence of
     cross chain request tx coming from Ethereum
    */
    mapping(uint256 => bytes32) public EthToLinQTxHashMap;
    // This index records the current Map length
    uint256 public EthToLinQTxHashIndex;

    /* 
     When linq network switches the consensus epoch book keepers, the consensus peers public keys of linq network should be
     changed into no-compressed version so that solidity smart contract can convert it to address type and 
     verify the signature derived from linq network account signature.
     ConKeepersPkBytes means Consensus book Keepers Public Key Bytes
    */
    address[] public ConKeepersPkBytes;

    // Record the from chain txs that have been processed
    mapping(uint64 => mapping(bytes32 => bool)) FromChainTxExist;

    // Store Consensus book Keepers Public Key Bytes
    function putCurEpochConPubKeyBytes(address[] memory curEpochPkBytes) public override whenNotPaused onlyOwner returns (bool) {
        ConKeepersPkBytes = curEpochPkBytes;
        return true;
    }

    // Get Consensus book Keepers Public Key Bytes
    function getCurEpochConPubKeyBytes() public override view returns (address[] memory) {
        return ConKeepersPkBytes;
    }

    // Mark from chain tx fromChainTx as exist or processed
    function markFromChainTxExist(uint64 fromChainId, bytes32 fromChainTx) public override whenNotPaused onlyOwner returns (bool) {
        FromChainTxExist[fromChainId][fromChainTx] = true;
        return true;
    }

    // Check if from chain tx fromChainTx has been processed before
    function checkIfFromChainTxExist(uint64 fromChainId, bytes32 fromChainTx) public override view returns (bool) {
        return FromChainTxExist[fromChainId][fromChainTx];
    }

    // Get current recorded index of cross chain txs requesting from Ethereum to other public chains
    // in order to help cross chain manager contract differenciate two cross chain tx requests
    function getEthTxHashIndex() public override view returns (uint256) {
        return EthToLinQTxHashIndex;
    }

    // Store Ethereum cross chain tx hash, increase the index record by 1
    function putEthTxHash(bytes32 ethTxHash) public override whenNotPaused onlyOwner returns (bool) {
        EthToLinQTxHashMap[EthToLinQTxHashIndex] = ethTxHash;
        EthToLinQTxHashIndex = EthToLinQTxHashIndex + 1;
        return true;
    }

    function pause() onlyOwner whenNotPaused public override returns (bool) {
        _pause();
        return true;
    }

    function unpause() onlyOwner whenPaused public override returns (bool) {
        _unpause();
        return true;
    }
}