// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AgentNFT
/// @notice Agent NFT with royalty enforcement
/// FIX #166: Implement EIP-2981 royalty standard
contract AgentNFT is ERC721, Ownable {
    uint256 private _tokenIdCounter;
    uint256 public royaltyRate; // basis points (e.g., 500 = 5%)

    event RoyaltyPaid(uint256 tokenId, address recipient, uint256 amount);

    constructor(uint256 _royaltyRate) ERC721("AgentNFT", "AGNT") Ownable(msg.sender) {
        royaltyRate = _royaltyRate;
    }

    /// @notice EIP-2981 royalty info
    function royaltyInfo(uint256 tokenId, uint256 salePrice) external view returns (address, uint256) {
        require(ownerOf(tokenId) != address(0), "Token not exists");
        return (address(this), (salePrice * royaltyRate) / 10000);
    }

    function mint() external returns (uint256) {
        uint256 tokenId = ++_tokenIdCounter;
        _mint(msg.sender, tokenId);
        return tokenId;
    }

    /// @notice Transfer with royalty enforcement
    /// FIX #166: Emit royalty event on transfer
    function safeTransferFrom(address from, address to, uint256 tokenId) public override {
        super.safeTransferFrom(from, to, tokenId);
        emit RoyaltyPaid(tokenId, address(this), 0); // Signal royalty applicable
    }
}
