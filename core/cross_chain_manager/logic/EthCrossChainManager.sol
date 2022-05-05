// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./../../../libs/lifecycle/Pausable.sol";
import "./../../../libs/math/SafeMath.sol";
import "./../../../libs/common/ZeroCopySource.sol";
import "./../../../libs/common/ZeroCopySink.sol";
import "./../../../libs/utils/Utils.sol";
import "./../libs/EthCrossChainUtils.sol";
import "./../interface/IEthCrossChainManager.sol";
import "./../interface/IEthCrossChainData.sol";
import "./../../../libs/ownership/Ownable.sol";

contract EthCrossChainManager is IEthCrossChainManager, Pausable, Ownable {
    using SafeMath for uint256;

    event InitGenesisBlockEvent(address[] pubKeyList);
    event ChangeBookKeeperEvent(address[] pubKeyList);
    event CrossChainEvent(address indexed sender, bytes txId, address proxyOrAssetContract, uint64 toChainId, bytes toContract, bytes rawdata);
    event VerifyHeaderAndExecuteTxEvent(uint64 fromChainID, bytes toContract, bytes fromChainTxHash);

    address public EthCrossChainDataAddress;
    address public LockProxyContract;
    uint64 public chainId;

    constructor(address _eccd, address _lpc, uint64 _chainId) public {
        EthCrossChainDataAddress = _eccd;
        LockProxyContract = _lpc;
        chainId = _chainId;
    }

    modifier onlyLockProxyContract() {
        require(_msgSender() == LockProxyContract, "msgSender is not LinQNFTLockProxy");
        _;
    }

    /* @notice              sync linq network genesis block header to smart contrat
    *  @dev                 this function can only be called once, nextbookkeeper of rawHeader can't be empty
    *  @param rawHeader     linq network genesis block raw header or raw Header including switching consensus peers info
    *  @return              true or false
    */
    function initGenesisBlock(address[] memory pubKeyList) public returns (bool) {
        // Load Ethereum cross chain data contract
        IEthCrossChainData eccd = IEthCrossChainData(EthCrossChainDataAddress);

        // Make sure the contract has not been initialized before
        require(eccd.getCurEpochConPubKeyBytes().length == 0, "EthCrossChainData contract has already been initialized!");

        require(eccd.putCurEpochConPubKeyBytes(pubKeyList), "Save linq network current epoch book keepers to Data contract failed!");

        // Emit the event
        emit InitGenesisBlockEvent(pubKeyList);
        return true;
    }

    /* @notice              change linq network consensus book keeper
    *  @param rawHeader     linq network change book keeper block raw header
    *  @param pubKeyList    linq network consensus nodes public key list
    *  @param sigList       linq network consensus nodes signature list
    *  @return              true or false
    */
    //    function changeBookKeeper(bytes memory rawHeader, address[] memory pubKeyList, bytes memory sigList) public returns(bool) {
    function changeBookKeeper(address[] memory pubKeyList) public onlyOwner returns (bool) {
        IEthCrossChainData eccd = IEthCrossChainData(EthCrossChainDataAddress);

        require(eccd.putCurEpochConPubKeyBytes(pubKeyList), "Save linq network book keepers bytes to Data contract failed!");

        // Fire the change book keeper event
        emit ChangeBookKeeperEvent(pubKeyList);

        return true;
    }


    /* @notice              ERC721 token cross chain to other blockchain.
    *                       this function push tx event to blockchain
    *  @param toChainId     Target chain id
    *  @param toContract    Target smart contract address in target block chain
    *  @param txData        Transaction data for target chain, include to_address, amount
    *  @return              true or false
    */
    function crossChain(uint64 toChainId, bytes calldata toContract, bytes calldata method, bytes calldata txData) whenNotPaused external override onlyLockProxyContract returns (bool) {
        // Load Ethereum cross chain data contract
        IEthCrossChainData eccd = IEthCrossChainData(EthCrossChainDataAddress);

        // To help differentiate two txs, the ethTxHashIndex is increasing automatically
        uint256 txHashIndex = eccd.getEthTxHashIndex();

        // Convert the uint256 into bytes
        bytes memory paramTxHash = Utils.uint256ToBytes(txHashIndex);

        // Construct the makeTxParam, and put the hash info storage, to help provide proof of tx existence
        bytes memory rawParam = abi.encodePacked(ZeroCopySink.WriteVarBytes(paramTxHash),
            ZeroCopySink.WriteVarBytes(abi.encodePacked(sha256(abi.encodePacked(address(this), paramTxHash)))),
            ZeroCopySink.WriteVarBytes(Utils.addressToBytes(msg.sender)),
            ZeroCopySink.WriteUint64(toChainId),
            ZeroCopySink.WriteVarBytes(toContract),
            ZeroCopySink.WriteVarBytes(method),
            ZeroCopySink.WriteVarBytes(txData)
        );

        // Must save it in the storage to be included in the proof to be verified.
        require(eccd.putEthTxHash(keccak256(rawParam)), "Save ethTxHash by index to Data contract failed!");

        // Fire the cross chain event denoting there is a cross chain request from Ethereum network to other public chains through linq network network
        emit CrossChainEvent(tx.origin, paramTxHash, msg.sender, toChainId, toContract, rawParam);
        return true;
    }

    /* @notice              Verify txBytes signature and execute cross chain tx
    *  @param txBytes       Tx serialized bytes
    *  @param txSig         The signature of txBytes by keepers
    *  @return              true or false
    */
    function verifySigAndExecuteTx(bytes memory txBytes, bytes memory txSig) whenNotPaused public returns (bool){
        // Load ehereum cross chain data contract
        IEthCrossChainData eccd = IEthCrossChainData(EthCrossChainDataAddress);

        // Get stored consensus public key bytes of current linq network epoch and deserialize linq network consensus public key bytes to address[]
        address[] memory keepers = eccd.getCurEpochConPubKeyBytes();

        uint n = keepers.length;
        require(ECCUtils.verifySig(txBytes, txSig, keepers, n - (n - 1) / 3), "Verify signature failed!");

        // Deserialize txBytes to txParams
        ECCUtils.TxParams memory txParams = ECCUtils.deserializeTxParams(txBytes);
        require(!eccd.checkIfFromChainTxExist(txParams.fromChainId, txParams.txHash), "the transaction has been executed!");
        require(eccd.markFromChainTxExist(txParams.fromChainId, txParams.txHash), "Save crosschain tx exist failed!");

        // Ethereum ChainId is 2, we need to check the transaction is for Ethereum network
        require(txParams.toChainId == chainId, "This Tx is not aiming at Ethereum network!");

        // Obtain the targeting contract, so that Ethereum cross chain manager contract can trigger the executation of cross chain tx on Ethereum side
        address toContract = Utils.bytesToAddress(txParams.toContract);

        //TODO: check this part to make sure we commit the next line when doing local net UT test
        require(_executeCrossChainTx(toContract, abi.encodePacked('unlock'), txParams.args, txParams.fromContract, txParams.fromChainId), "Execute CrossChain Tx failed!");

        // Fire the cross chain event denoting the executation of cross chain tx is successful,
        // and this tx is coming from other public chains to current Ethereum network
        emit VerifyHeaderAndExecuteTxEvent(txParams.fromChainId, txParams.toContract, abi.encodePacked(txParams.txHash));

        return true;
    }

    /* @notice                  Dynamically invoke the targeting contract, and trigger executation of cross chain tx on Ethereum side
    *  @param _toContract       The targeting contract that will be invoked by the Ethereum Cross Chain Manager contract
    *  @param _method           At which method will be invoked within the targeting contract
    *  @param _args             The parameter that will be passed into the targeting contract
    *  @param _fromContractAddr From chain smart contract address
    *  @param _fromChainId      Indicate from which chain current cross chain tx comes 
    *  @return                  true or false
    */
    function _executeCrossChainTx(address _toContract, bytes memory _method, bytes memory _args, bytes memory _fromContractAddr, uint64 _fromChainId) internal returns (bool){
        // Ensure the targeting contract gonna be invoked is indeed a contract rather than a normal account address
        require(Utils.isContract(_toContract), "The passed in address is not a contract!");
        bytes memory returnData;
        bool success;

        // The returnData will be bytes32, the last byte must be 01;
        (success, returnData) = _toContract.call(abi.encodePacked(bytes4(keccak256(abi.encodePacked(_method, "(bytes,bytes,uint64)"))), abi.encode(_args, _fromContractAddr, _fromChainId)));

        // Ensure the executation is successful
        require(success == true, "EthCrossChain call business contract failed");

        // Ensure the returned value is true
        require(returnData.length != 0, "No return value from business contract!");
        (bool res,) = ZeroCopySource.NextBool(returnData, 31);
        require(res == true, "EthCrossChain call business contract return is not true");

        return true;
    }

    function pause() onlyOwner whenNotPaused public returns (bool) {
        _pause();
        return true;
    }

    function unpause() onlyOwner whenPaused public returns (bool) {
        _unpause();
        return true;
    }
}