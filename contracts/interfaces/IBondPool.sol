// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DataTypes} from "../libraries/DataTypes.sol";

/**
 * @title IPool
 * @dev Interface of the liquidity pool contract.
 */
interface IBondPool {
    /**
     * @dev Creates a new liquidity pool with the specified parameters, also create the lp token for the pool.
     * @param _poolId Pool ID.
     * @param _underlyingToken Address of the underlying token.
     * @param _supplyTokenName Name of the supply token.
     * @param _supplyTokenSymbol Symbol of the supply token.
     */
    function createPool(
        uint64 _poolId,
        address _underlyingToken,
        string memory _supplyTokenName,
        string memory _supplyTokenSymbol
    ) external returns (DataTypes.PoolData memory _pool);

    /**
     * @dev Allows a user to supply tokens to the pool and receive supply tokens in return.
     * @param _poolId Pool ID.
     * @param _amount Amount of tokens to supply.
     * @param _onBehalfOf The address on behalf of which the tokens are supplied.
     */
    function supply(
        uint64 _poolId,
        uint256 _amount,
        address _onBehalfOf
    ) external;

    /**
     * @dev Allows a user to withdraw tokens from the pool.
     * @param _poolId Pool ID.
     * @param _amount Amount of tokens to withdraw.
     * @param _onBehalfOf The address on behalf of which the tokens are withdrawn.
     */
    function withdraw(
        uint64 _poolId,
        uint256 _amount,
        address _onBehalfOf
    ) external;

    /**
     * @notice Handles the receipt of tokens from the bridge and performs necessary actions.
     * @param _poolId Destination pool ID.
     * @param _fee Fee associated with the transaction.
     */
    function handlePoolIncentive(uint64 _poolId, uint256 _fee) external;

    /**
     * @dev Updates user incentives for a specific pool.
     * @param _user User address.
     * @param _poolId Pool ID.
     */
    function updateUserIncentives(address _user, uint64 _poolId) external;

    /**
     * @dev Retrieves data for a specific pool.
     * @param _poolId Pool ID.
     * @return _pool Pool data structure.
     */
    function getPool(
        uint64 _poolId
    ) external view returns (DataTypes.PoolData memory _pool);

    /**
     * @dev Retrieves user data for a specific account.
     * @param _account User address.
     * @return _user User data structure.
     */
    function getUserData(
        address _account
    ) external view returns (DataTypes.UserData memory _user);
}
