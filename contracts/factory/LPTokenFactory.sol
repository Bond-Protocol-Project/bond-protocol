// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LPTokenERC20} from "../mocks/LPTokenERC20.sol";

contract LPTokenFactory is Ownable {

    address public pool;
    mapping (uint64 poolId => LPTokenERC20) public getToken;
    address[] public tokens;

    modifier onlyPool() {
        require(msg.sender == pool, "Only pool is allowed to call this function");
        _;
    }

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    function createSupplyToken(        
        uint64 _poolId,
        string memory _name,
        string memory _symbol
    ) external onlyPool returns (address tokenAddress) {
        require(pool != address(0), "pool not initialized");
        LPTokenERC20 _token = new LPTokenERC20(pool, _poolId, _name, _symbol);
        getToken[_poolId] = _token;
        tokenAddress = address(_token);
        tokens.push(tokenAddress);
    }

    function initializePool(address _pool) external onlyOwner {
        pool = _pool;
    }

}