// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DelayVaultState.sol";
import "../util/CalcUtils.sol";

contract DelayVaultProvider is DelayVaultState {
    using CalcUtils for uint256;

    constructor(address _token, ILockDealNFT _nftContract, ProviderData[] memory _providersData) {
        require(address(_token) != address(0x0), "invalid address");
        require(address(_nftContract) != address(0x0), "invalid address");
        require(_providersData.length <= 255, "too many providers");
        name = "DelayVaultProvider";
        Token = _token;
        lockDealNFT = _nftContract;
        typesCount = uint8(_providersData.length);
        uint256 limit = _providersData[0].limit;
        for (uint8 i = 0; i < typesCount; i++) {
            ProviderData memory item = _providersData[i];
            limit = _handleItem(i, limit, item);
        }
        TypeToProviderData[typesCount - 1].limit = type(uint256).max; //the last one is the max, token supply is out of the scope
    }

    function _handleItem(uint8 index, uint256 lastLimit, ProviderData memory item) internal returns (uint256 limit) {
        require(address(item.provider) != address(0x0), "invalid address");
        require(item.provider.currentParamsTargetLenght() == item.params.length + 1, "invalid params length");
        if (index > 0) {
            limit = item.limit;
            require(limit >= lastLimit, "limit must be bigger or equal than the previous on");
        }
        TypeToProviderData[index] = item;
    }

    function withdraw(uint256 tokenId) external override onlyNFT returns (uint256 withdrawnAmount, bool isFinal) {
        uint8 theType = PoolToType[tokenId];
        address owner = LastPoolOwner[tokenId];
        uint256 newPoolId = nftContract.mintForProvider(owner, TypeToProviderData[theType].provider);
        uint256[] memory params = _getWithdrawPoolParams(tokenId, theType);
        TypeToProviderData[theType].provider.registerPool(newPoolId, params);
        isFinal = true;
        withdrawnAmount = poolIdToAmount[tokenId] = 0;
        UserToTotalAmount[owner][theType] -= params[0];
        //This need to make a new pool without transfering the token, the pool data is taken from the settings
    }

    function split(uint256 oldPoolId, uint256 newPoolId, uint256 ratio) external override onlyNFT {
        address oldOwner = LastPoolOwner[oldPoolId];
        address newOwner = nftContract.ownerOf(newPoolId);
        uint256 amount = poolIdToAmount[oldPoolId].calcAmount(ratio);
        poolIdToAmount[oldPoolId] -= amount;
        poolIdToAmount[newPoolId] = amount;
        PoolToType[newPoolId] = PoolToType[oldPoolId];
        if (newOwner != oldOwner) {
            _handleTransfer(oldOwner, newOwner, oldPoolId);
        }
    }

    function registerPool(uint256 poolId, uint256[] calldata params) public override onlyProvider {
        uint8 theType = uint8(params[1]);
        uint256 amount = params[0];
        address owner = nftContract.ownerOf(poolId);
        uint256 newAmount = UserToTotalAmount[owner][theType] + amount;
        require(newAmount <= TypeToProviderData[theType].limit, "limit exceeded");
        require(PoolToType[poolId] == 0, "pool already registered");
        require(params.length == 2, "invalid params length");
        PoolToType[poolId] = theType;
        UserToTotalAmount[owner][theType] = newAmount;
        poolIdToAmount[poolId] = amount;
    }

    function getParams(uint256 poolId) external view override returns (uint256[] memory params) {
        params = new uint256[](2);
        params[0] = poolIdToAmount[poolId];
        params[1] = uint256(PoolToType[poolId]);
    }

    function getWithdrawableAmount(uint256 poolId) external view override returns (uint256 withdrawalAmount) {
        withdrawalAmount = poolIdToAmount[poolId];
    }

    function upgradeType(uint256 PoolId, uint8 newType) external {
        require(nftContract.poolIdToProvider(PoolId) == this, "need to be THIS provider");
        require(PoolToType[PoolId] != 0, "pool not registered");
        require(msg.sender == nftContract.ownerOf(PoolId), "only the Owner can upgrade the type");
        require(newType > PoolToType[PoolId], "new type must be bigger than the old one");
        require(newType <= typesCount, "new type must be smaller than the types count");
        PoolToType[PoolId] = newType;
    }

    function createNewDelayVault(uint256[] calldata params) external returns (uint256 PoolId) {
        uint256 amount = params[0];
        uint8 theType = uint8(params[1]);
        require(theType <= typesCount, "invalid type");
        require(amount > 0, "amount must be bigger than 0");
        PoolId = nftContract.mintAndTransfer(msg.sender, Token, msg.sender, amount, this);
        registerPool(PoolId, params);
    }

    function getLeftAmount(address owner, uint8 theType) external view returns (uint256) {
        return TypeToProviderData[theType].limit - UserToTotalAmount[owner][theType];
    }
}
