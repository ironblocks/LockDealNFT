// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "../Builder/BuilderInternal.sol";

/// @title SimpleBuilder contract
/// @notice This contract is used to create mass lock deals(NFTs)
contract SimpleBuilder is ERC721Holder, BuilderInternal {
    constructor(ILockDealNFT _nft) {
        lockDealNFT = _nft;
    }

    /// @notice Build mass pools
    /// @param addressParams[0] - Provider address
    /// @param addressParams[1] - Token address
    /// @param userData - Array of user pools
    /// @param params - Array of params. May be empty if this is DealProvider
    function buildMassPools(
        address[] calldata addressParams,
        Builder calldata userData,
        uint256[] calldata params,
        bytes calldata signature
    ) external notZeroAddress(addressParams[1]) {
        _validParamsLength(addressParams.length, 2);
        require(
            ERC165Checker.supportsInterface(addressParams[0], type(ISimpleProvider).interfaceId),
            "invalid provider type"
        );
        require(userData.userPools.length > 0, "invalid user length");
        uint256 totalAmount = userData.totalAmount;
        _notZeroAmount(totalAmount);
        address token = addressParams[1];
        ISimpleProvider provider = ISimpleProvider(addressParams[0]);
        UserPool calldata firstUserData = userData.userPools[0];
        uint256 length = userData.userPools.length;
        // one time transfer for deacrease number transactions
        uint256[] memory simpleParams = _concatParams(firstUserData.amount, params);
        uint256 poolId = _createFirstNFT(provider, token, firstUserData.user, totalAmount, simpleParams, signature);
        totalAmount -= firstUserData.amount;
        for (uint256 i = 1; i < length; ) {
            UserPool calldata userPool = userData.userPools[i];
            totalAmount -= _createNewNFT(provider, poolId, userPool, simpleParams);
            unchecked {
                ++i;
            }
        }
        assert(totalAmount == 0);
    }
}
