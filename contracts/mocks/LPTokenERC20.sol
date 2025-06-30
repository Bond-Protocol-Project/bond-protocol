// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IBondPool} from "../interfaces/IBondPool.sol";
import {ILPTokenERC20} from "../interfaces/ILPTokenERC20.sol";
import {DataTypes} from "../libraries/DataTypes.sol";

/**
 * @title LPTokenERC20
 * @dev ERC20 token representing ownership in a liquidity pool.
 */
contract LPTokenERC20 is ERC20, ERC20Permit {
    // Pool contract that owns this lp token
    IBondPool public immutable pool;
    // ID of the pool that this lp token is linked with
    uint64 public poolId;

    /**
     * @dev Modifier to restrict functions to be called only by the associated pool contract.
     */
    modifier onlyPool() {
        require(
            msg.sender == address(pool),
            "Unauthorized: Only pool can access this function"
        );
        _;
    }

    /**
     * @dev Constructor initializes the LPTokenERC20 with the specified parameters.
     * @param _pool Address of the associated pool contract.
     * @param _poolId Pool ID.
     * @param _name Name of the token.
     * @param _symbol Symbol of the token.
     */
    constructor(
        address _pool,
        uint64 _poolId,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) ERC20Permit(_symbol) {
        pool = IBondPool(_pool);
        poolId = _poolId;
    }

    /**
     * @dev Retrieves the number of decimals used by the token.
     * @return The number of decimals.
     */
    function getDecimals() external view returns (uint8) {
        return decimals();
    }

    /**
     * @dev Overrides the total supply to include unclaimed profits from the pool.
     */
    function totalSupply() public view override returns (uint256) {
        return super.totalSupply() + getPool().unclaimedProfit;
    }

    /**
     * @dev Overrides the balanceOf function to include incentives for the user.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return
            super.balanceOf(account) +
            (((getPool().currentIndex -
                pool.getUserData(account).currentPoolIndex) *
                super.balanceOf(account)) / 10 ** decimals());
    }

    /**
     * @dev returns the balanceOf function without incentives for the user.
     */
    function unscaledBalanceOf(address account) public view returns (uint256) {
        return super.balanceOf(account);
    }

    /**
     * @dev Overrides the transferFrom function to update user incentives before transferring tokens.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override returns (bool) {
        pool.updateUserIncentives(from, poolId);
        pool.updateUserIncentives(to, poolId);
        bool success = super.transferFrom(from, to, value);
        require(success, "Operation failed");
        return success;
    }

    /**
     * @dev Overrides the transfer function to update user incentives before transferring tokens.
     */
    function transfer(
        address to,
        uint256 value
    ) public override returns (bool) {
        pool.updateUserIncentives(msg.sender, poolId);
        pool.updateUserIncentives(to, poolId);
        bool success = super.transfer(to, value);
        require(success, "Operation failed");
        return success;
    }

    /**
     * @dev Allows the pool contract to mint new tokens.
     * @param to The account to which tokens will be minted.
     * @param value The amount of tokens to mint.
     */
    function mint(address to, uint256 value) external onlyPool {
        _mint(to, value);
    }

    /**
     * @dev Allows the pool contract to burn tokens.
     * @param account The account from which tokens will be burned.
     * @param value The amount of tokens to burn.
     */
    function burn(address account, uint256 value) external onlyPool {
        _burn(account, value);
    }

    /**
     * @dev Internal function to get pool data based on the pool ID.
     * @return Pool data structure.
     */
    function getPool() internal view returns (DataTypes.PoolData memory) {
        return pool.getPool(poolId);
    }
}
