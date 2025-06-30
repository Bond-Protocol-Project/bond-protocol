// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract TokenERC721 is
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable
{
    function initialize(
        string memory _name,
        string memory _symbol
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __ERC721URIStorage_init();
        __Ownable_init(msg.sender);
    }

    function safeMint(
        address to,
        uint256 tokenId,
        string memory uri
    ) public onlyOwner {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    function mint(address to, uint256 tokenId) external {
        super._mint(to, tokenId);
    }

    function burn(uint256 tokenId) external {
         super._burn(tokenId);
    }

    // The following functions are overrides required by Solidity.

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
