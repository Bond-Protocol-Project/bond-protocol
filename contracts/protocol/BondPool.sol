// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBondProtocol} from "../interfaces/IBondProtocol.sol";
import {IBondPool} from "../interfaces/IBondPool.sol";
import {DataTypes} from "../libraries/DataTypes.sol";
import {ILPTokenERC20} from "../interfaces/ILPTokenERC20.sol";
import {ILPTokenFactory} from "../interfaces/ILPTokenFactory.sol";
import {IERC20} from "../interfaces/IERC20.sol";

contract BondPool is IBondPool, ReentrancyGuard {
    //
    // Main contract address users interact with (users interact with the pool from the protocol contract)
    IBondProtocol public immutable protocol;
    // Mapping to store pool data based on pool IDs
    mapping(uint64 poolId => DataTypes.PoolData) private poolData;
    // Mapping to store user data based on user addresses
    mapping(address => DataTypes.UserData) private userData;
    // Liquidity pool token factory address
    address public immutable tokenFactory;

    // Modifier to restrict functions to be called only by the router
    modifier onlyProtocol() {
        require(msg.sender == address(protocol), "Caller must be Router.");
        _;
    }

    // Modifier to restrict functions to be called only by the supply token of a pool
    modifier onlySupplyToken(uint64 _poolId) {
        require(
            msg.sender == getPool(_poolId).supplyToken,
            "Caller must be pool token"
        );
        _;
    }

    /**
     * @dev Constructor initializes the router address.
     * @param _protocol The address of the router contract.
     */
    constructor(address _protocol, address _factory) {
        protocol = IBondProtocol(_protocol);
        tokenFactory = _factory;
    }

    /**
     * @notice Creates a new pool with the specified parameters.
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
    ) external onlyProtocol returns (DataTypes.PoolData memory _pool) {
        require(
            address(poolData[_poolId].underlyingToken) == address(0x0),
            "Pool already created"
        );
        address _supplyToken = ILPTokenFactory(tokenFactory).createSupplyToken(
            _poolId,
            _supplyTokenName,
            _supplyTokenSymbol
        );
        _pool.poolId = _poolId;
        _pool.underlyingToken = _underlyingToken;
        _pool.supplyToken = _supplyToken;
        poolData[_poolId] = _pool;
        return _pool;
    }

    /**
     * @notice Allows a user to supply tokens to the pool and receive supply tokens in return.
     * @param _poolId Pool ID.
     * @param _amount Amount of tokens to supply.
     * @param _onBehalfOf The address on behalf of which the tokens are supplied.
     */
    function supply(
        uint64 _poolId,
        uint256 _amount,
        address _onBehalfOf
    ) external nonReentrant onlyProtocol {
        _updateUserIncentives(_onBehalfOf, _poolId);
        ILPTokenERC20(getPool(_poolId).supplyToken).mint(_onBehalfOf, _amount);
    }

    /**
     * @notice Allows a user to withdraw tokens from the pool by burning supply tokens.
     * @param _poolId Pool ID.
     * @param _amount Amount of tokens to withdraw.
     * @param _onBehalfOf The address on behalf of which the tokens are withdrawn.
     */
    function withdraw(
        uint64 _poolId,
        uint256 _amount,
        address _onBehalfOf
    ) external nonReentrant onlyProtocol {
        require(
            IERC20(getPool(_poolId).underlyingToken).balanceOf(address(this)) >=
                _amount,
            "Not enough token in pool"
        );
        _updateUserIncentives(_onBehalfOf, _poolId);
        ILPTokenERC20(getPool(_poolId).supplyToken).burn(_onBehalfOf, _amount);
        bool _transfer_success = IERC20(getPool(_poolId).underlyingToken)
            .transfer(_onBehalfOf, _amount);
        require(_transfer_success, "Operation failed");
    }

    /**
     * @notice Updates the user's incentives for a specific pool.
     * @param _user User address.
     * @param _poolId Pool ID.
     */
    function updateUserIncentives(
        address _user,
        uint64 _poolId
    ) external nonReentrant onlySupplyToken(_poolId) {
        _updateUserIncentives(_user, _poolId);
    }

    /**
     * @notice Handles the receipt of tokens from the bridge and performs necessary actions.
     * @param _poolId pool ID to handle.
     * @param _fee Fee associated with the transaction.
     */
    function handlePoolIncentive(
        uint64 _poolId,
        uint256 _fee
    )
        external
        nonReentrant
        onlyProtocol
    {
        DataTypes.PoolData memory _pool = getPool(_poolId);
        uint256 _index = (_fee *
            (10 ** ILPTokenERC20(_pool.supplyToken).getDecimals())) /
            (ILPTokenERC20(_pool.supplyToken).totalSupply());
        _pool.currentIndex = _pool.currentIndex + _index;
        _pool.unclaimedProfit = _pool.unclaimedProfit + _fee;
        poolData[_poolId] = _pool;
    }

    /**
     * @dev Internal function to update user incentives for a specific pool.
     * @param _user User address.
     * @param _poolId Pool ID.
     */
    function _updateUserIncentives(address _user, uint64 _poolId) private {
        DataTypes.PoolData memory _pool = getPool(_poolId);
        if (userData[_user].currentPoolIndex < _pool.currentIndex) {
            uint256 _unclaimedUserProfit = ((_pool.currentIndex -
                userData[_user].currentPoolIndex) *
                ILPTokenERC20(_pool.supplyToken).unscaledBalanceOf(_user)) /
                (10 ** ILPTokenERC20(_pool.supplyToken).getDecimals());

            userData[_user].currentPoolIndex = _pool.currentIndex;
            _pool.unclaimedProfit =
                _pool.unclaimedProfit -
                _unclaimedUserProfit;
            poolData[_poolId] = _pool;
            ILPTokenERC20(_pool.supplyToken).mint(_user, _unclaimedUserProfit);
        }
    }

    /**
     * @notice Retrieves user data for a given user address.
     * @param _account User address.
     * @return User data structure.
     */
    function getUserData(
        address _account
    ) external view returns (DataTypes.UserData memory) {
        return userData[_account];
    }

    /**
     * @notice Retrieves pool data for a given pool ID.
     * @param _poolId Pool ID.
     * @return Pool data structure.
     */
    function getPool(
        uint64 _poolId
    ) public view returns (DataTypes.PoolData memory) {
        require(
            poolData[_poolId].underlyingToken != address(0),
            "Invalid pool"
        );
        return poolData[_poolId];
    }

    function getProtocol() external view returns(address) {
        return address(protocol);
    }
}
