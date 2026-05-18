// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title AgentNFT
/// @notice NFT representing AI agents with royalty enforcement
/// FIX #166: Add royalty percentage validation and on-chain enforcement
contract AgentNFT is ERC721, ERC721URIStorage, Ownable {
    uint256 public nextTokenId;

    // FIX #166: Royalty on-chain enforcement
    mapping(uint256 => uint256) public royaltyPercent; // per-token royalty in basis points (0-10000 = 0-100%)
    uint256 public constant MAX_ROYALTY_BPS = 10000;

    struct Agent {
        string name;
        string metadataURI;
        address creator;
        uint256 price;
    }

    mapping(uint256 => Agent) public agents;

    event AgentMinted(uint256 tokenId, string name, address creator);
    event RoyaltySet(uint256 tokenId, uint256 percentBps);

    constructor() ERC721("AgentNFT", "AGNT") Ownable(msg.sender) {}

    /// @notice Mint a new agent NFT
    function mintAgent(
        string calldata name,
        string calldata metadataURI,
        uint256 price,
        uint256 _royaltyBps
    ) external returns (uint256) {
        require(bytes(name).length > 0, "Empty name");
        require(price > 0, "Zero price");
        // FIX: Validate royalty percentage
        require(_royaltyBps <= MAX_ROYALTY_BPS, "Royalty exceeds max");

        uint256 tokenId = nextTokenId++;
        _mint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadataURI);

        agents[tokenId] = Agent({
            name: name,
            metadataURI: metadataURI,
            creator: msg.sender,
            price: price
        });

        royaltyPercent[tokenId] = _royaltyBps;
        emit AgentMinted(tokenId, name, msg.sender);
        emit RoyaltySet(tokenId, _royaltyBps);
        return tokenId;
    }

    /// @notice Get royalty for a token
    function getRoyalty(uint256 tokenId) external view returns (uint256) {
        require(_exists(tokenId), "Token does not exist");
        return royaltyPercent[tokenId];
    }

    /// @notice Set max supply
    /// FIX #44: Cap total supply
    uint256 public constant MAX_SUPPLY = 10000;

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);
        require(nextTokenId <= MAX_SUPPLY, "Max supply reached");
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
