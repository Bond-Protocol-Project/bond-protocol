// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract TokenERC20 is ERC20Upgradeable, OwnableUpgradeable {

    function initialize(string memory _name, string memory _symbol) public initializer() {
         __ERC20_init(_name, _symbol);
        __Ownable_init(msg.sender);
    }

    function mint(address account, uint256 amount) external {
        super._mint(account, amount);
    }
    
    function burn(address account, uint256 amount) external {
        super._burn(account, amount);
    }
}
