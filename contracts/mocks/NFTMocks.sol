// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title MockERC721
 * @notice Simple ERC721 for testing NFTMarketplace.
 */
contract MockERC721 is ERC721 {
    uint256 private _tokenIdCounter;

    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }

    function mint(address to, uint256 tokenId, bytes memory) external pure override {
        revert("not implemented");
    }

    function mint(address to, uint256 tokenId, bytes memory, string memory) external pure override {
        revert("not implemented");
    }
}

/**
 * @title MockERC721WithRoyalty
 * @notice ERC721 with ERC-2981 royalties for testing royalty payments.
 */
contract MockERC721WithRoyalty is ERC721 {
    uint256 private _tokenIdCounter;
    uint256 public royaltyBps = 1000; // 10%
    address public royaltyRecipient;

    constructor() ERC721("MockNFTRoyalty", "MNFT") {}

    function mint(address to, uint256 tokenId, address _royaltyRecipient, uint256 _royaltyBps) external {
        royaltyRecipient = _royaltyRecipient;
        royaltyBps = _royaltyBps;
        _safeMint(to, tokenId);
    }

    function mint(address to, uint256 tokenId, bytes memory, string memory) external pure override {
        revert("not implemented");
    }

    // ERC-2981
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        return (royaltyRecipient, (salePrice * royaltyBps) / 10000);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == bytes4(0x2a55205a);
    }
}
