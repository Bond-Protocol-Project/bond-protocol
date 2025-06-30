// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

/**
 * @title DataTypes
 * @dev Library defining common data structures used in protocol contracts.
 */
library DataTypes {
    /**
     * @dev Data structure representing intent destination data to be called by
     *      account in destination chain.
     */
    struct IntentDstData {
        address target;
        uint256 value;
        bytes data;
    }

    /**
     * @dev Data structure representing information about an intent.
     */
    struct IntentData {
        address sender;
        uint64 initChainSenderNonce;
        uint64 initChainId;
        uint64 poolId;
        uint64[] srcChainIds;
        uint256[] srcAmounts;
        uint64 dstChainId;
        bytes dstDatas; // IntentDstData[]
        uint256 expires;
    }

    /**
     * @dev Data structure representing a message used in cross-chain bridging.
     */
    struct BridgeData {
        bytes32 intentId; // protocol bridge message data
        bytes intentData; // bridged protocol intent information
    }

    /**
     * @dev Data structure representing a message used in cross-chain bridging.
     */
    struct BridgeMsgData {
        bool isBatch;
        bytes bridgeData; // bridge data information
    }

    /**
     * @dev Data structure representing information about a liquidity pool.
     */
    struct PoolData {
        uint64 poolId; // Unique identifier for the pool.
        address underlyingToken; // Address of the underlying token for the pool.
        address supplyToken; // Address of the supply token for the pool.
        uint256 unclaimedProfit; // Accumulated unclaimed profit in the pool.
        uint256 currentIndex; // Current index used for incentive calculations.
        // uint256 lastUpdateTimestamp; // Timestamp of the last update.
    }

    /**
     * @dev Data structure representing information about a user's interaction with a pool.
     */
    struct UserData {
        uint256 currentPoolIndex; // User's current index in the pool.
        // uint256 lastUpdateTimestamp; // Timestamp of the last update.
    }
    
    // BELOW TYPES ARE NOT BEING USED FOR NOW

    /**
     * @dev enum representing intent token type.
     */
    enum IntentTokenType {
        ERC20,
        ERC1155,
        ERC721
    }

    /**
     * @dev Data structure representing information about the chain.
     */
    struct ChainData {
        address protocolAddress;
        uint64 ccipChainselector;
        uint32 subnetId;
        address middlewareAddress;
    }
}
