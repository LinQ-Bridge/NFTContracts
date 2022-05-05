// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./../../../libs/common/ZeroCopySource.sol";
import "./../../../libs/common/ZeroCopySink.sol";
import "./../../../libs/utils/Utils.sol";

library ECCUtils {

    struct TxParam {
        bytes txHash; //  source chain txhash
        bytes crossChainId;
        bytes fromContract;
        uint64 toChainId;
        bytes toContract;
        bytes method;
        bytes args;
    }

    struct TxParams {
        bytes32 txHash;
        uint64 fromChainId;
        bytes fromContract;
        uint64 toChainId;
        bytes toContract;
        bytes args;
        bytes toAssetHash;
        bytes toAddress;
        uint256 tokenId;
        bytes tokenURI;
    }

    function deserializeTxParams(bytes memory _txParamsBs) internal pure returns (TxParams memory) {
        TxParams memory txParams;
        uint256 off = 0;
        (txParams.txHash, off) = ZeroCopySource.NextHash(_txParamsBs, off);

        (txParams.fromChainId, off) = ZeroCopySource.NextUint64(_txParamsBs, off);

        (txParams.fromContract, off) = ZeroCopySource.NextVarBytes(_txParamsBs, off);

        (txParams.toChainId, off) = ZeroCopySource.NextUint64(_txParamsBs, off);

        (txParams.toContract, off) = ZeroCopySource.NextVarBytes(_txParamsBs, off);

        (txParams.args, off) = ZeroCopySource.NextVarBytes(_txParamsBs, off);

        return txParams;
    }

    uint constant LINQCHAIN_SIGNATURE_LEN = 65;

    /* @notice              Verify linq network consensus node signature
    *  @param _txBytes      cross chain tx bytes
    *  @param _sigList      consensus node signature list
    *  @param _keepers      addresses corresponding with linq network book keepers' public keys
    *  @param _m            minimum signature number
    *  @return              true or false
    */
    function verifySig(bytes memory _txBytes, bytes memory _sigList, address[] memory _keepers, uint _m) internal pure returns (bool){
        bytes32 hash = keccak256(_txBytes);

        uint sigCount = _sigList.length / LINQCHAIN_SIGNATURE_LEN;
        address[] memory signers = new address[](sigCount);
        bytes32 r;
        bytes32 s;
        uint8 v;
        for (uint j = 0; j < sigCount; j++) {
            r = Utils.bytesToBytes32(Utils.slice(_sigList, j * LINQCHAIN_SIGNATURE_LEN, 32));
            s = Utils.bytesToBytes32(Utils.slice(_sigList, j * LINQCHAIN_SIGNATURE_LEN + 32, 32));
            v = uint8(_sigList[j * LINQCHAIN_SIGNATURE_LEN + 64]) + 27;
            signers[j] = ecrecover(hash, v, r, s);
            require(signers[j] != address(0), "signature invalid!");
        }
        return Utils.containMAddresses(_keepers, signers, _m);
    }
}