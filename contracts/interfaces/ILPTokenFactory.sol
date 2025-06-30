// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILPTokenFactory {
    function createSupplyToken(
        uint64 _poolId,
        string memory _name,
        string memory _symbol
    ) external returns (address tokenAddress);
}
