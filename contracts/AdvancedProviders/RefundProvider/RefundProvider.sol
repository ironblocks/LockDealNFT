// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../../ERC165/Refundble.sol";
import "./RefundState.sol";

contract RefundProvider is RefundState, IERC721Receiver {
    constructor(ILockDealNFT nftContract, address provider) {
        require(address(nftContract) != address(0x0) && provider != address(0x0), "invalid address");
        lockDealNFT = nftContract;
        collateralProvider = CollateralProvider(provider);
        name = "RefundProvider";
    }

    ///@dev refund implementation
    function onERC721Received(
        address provider,
        address user,
        uint256 poolId,
        bytes calldata
    ) external override returns (bytes4) {
        require(msg.sender == address(lockDealNFT), "invalid nft contract");
        if (provider == user) {
            uint256 collateralPoolId = poolIdToCollateralId[poolId];
            require(collateralProvider.poolIdToTime(collateralPoolId) > block.timestamp, "too late");
            ISimpleProvider dealProvider = collateralProvider.provider();
            uint256 userDataPoolId = poolId + 1;
            // user withdraws his tokens and will receives refund
            uint256 amount = dealProvider.getParams(userDataPoolId)[0];
            (uint256 withdrawnAmount, ) = dealProvider.withdraw(userDataPoolId, amount);
            collateralProvider.handleRefund(collateralPoolId, user, withdrawnAmount);
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    ///@param addresses[0] = owner
    ///@param addresses[1] = token
    ///@param addresses[2] = main coin
    ///@param addresses[3] = provider
    ///@param params[0] = tokenLeftAmount
    ///@param params[params.length - 2] = refundMainCoinAmount
    ///@param params[params.length - 1] = refund finish time
    function createNewRefundPool(
        address[] calldata addresses,
        uint256[] calldata params,
        bytes calldata tokenSignature,
        bytes calldata mainCoinSignature
    ) external returns (uint256 poolId) {
        _validAddressLength(addresses.length, 4);
        _validProviderInterface(IProvider(addresses[3]), Refundble._INTERFACE_ID_REFUNDABLE);
        uint256 paramsLength = params.length;
        require(paramsLength > 2, "invalid params length");
        IProvider provider = IProvider(addresses[3]);
        // create new refund pool | Owner User
        poolId = lockDealNFT.mintForProvider(addresses[0], this);

        // Hold token (data) | Owner Refund Provider
        uint256 dataPoolID = lockDealNFT.safeMintAndTransfer(
            address(this),
            addresses[1],
            msg.sender,
            params[0],
            provider,
            tokenSignature
        );
        provider.registerPool(dataPoolID, params);

        // Hold main coin | Project Owner
        uint256 collateralPoolId = lockDealNFT.safeMintAndTransfer(
            msg.sender,
            addresses[2],
            msg.sender,
            params[paramsLength - 2],
            collateralProvider,
            mainCoinSignature
        );
        collateralProvider.registerPool(collateralPoolId, params);
        lockDealNFT.cloneVaultId(collateralPoolId + 2, dataPoolID); // clone token data to sub-collateral poolId
        // save refund data
        uint256[] memory refundRegisterParams = new uint256[](currentParamsTargetLenght());
        refundRegisterParams[0] = collateralPoolId;
        _registerPool(poolId, refundRegisterParams);
    }

    ///@param params[0] = collateralId
    function registerPool(
        uint256 poolId,
        uint256[] calldata params
    ) public override onlyProvider validProviderId(poolId) validProviderAssociation(params[0], collateralProvider) {
        require(lockDealNFT.ownerOf(poolId + 1) == address(this), "Must Own poolId+1");
        _registerPool(poolId, params);
    }

    function _registerPool(
        uint256 poolId,
        uint256[] memory params
    ) internal validParamsLength(params.length, currentParamsTargetLenght()) {
        poolIdToCollateralId[poolId] = params[0];
        emit UpdateParams(poolId, params);
    }

    ///@dev split tokens and main coins into new pools
    function split(uint256 poolId, uint256 newPoolId, uint256 ratio) external onlyNFT {
        uint256[] memory params = new uint256[](currentParamsTargetLenght());
        params[0] = poolIdToCollateralId[poolId];
        _registerPool(newPoolId, params);
        uint256 userPoolId = poolId + 1;
        lockDealNFT.safeTransferFrom(address(this), address(lockDealNFT), userPoolId, abi.encode(ratio));
    }

    ///@dev user withdraws his tokens
    function withdraw(uint256 poolId) public override onlyNFT returns (uint256 amountToBeWithdrawed, bool isFinal) {
        uint256 userDataPoolId = poolId + 1;
        IProvider provider = lockDealNFT.poolIdToProvider(userDataPoolId);
        amountToBeWithdrawed = provider.getWithdrawableAmount(userDataPoolId);
        if (collateralProvider.poolIdToTime(poolIdToCollateralId[poolId]) >= block.timestamp) {
            collateralProvider.handleWithdraw(poolIdToCollateralId[poolId], amountToBeWithdrawed);
        }
        isFinal = provider.getParams(userDataPoolId)[0] == amountToBeWithdrawed;
    }
}
