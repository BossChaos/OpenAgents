// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AgentNFT
/// @notice ERC721-style NFT for AI agents with metadata URI support
/// @dev Simplified ERC721 implementation with max supply and proper validation
contract AgentNFT {
    string public name;
    string public symbol;
    string public baseURI;
    address public owner;

    // FIX: Add max supply to prevent infinite minting
    uint256 public constant MAX_SUPPLY = 10_000;
    uint256 private _nextTokenId;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(uint256 => string) private _tokenURIs;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event MetadataUpdated(uint256 indexed tokenId, string uri);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(string memory _name, string memory _symbol, string memory _baseURI) {
        name = _name;
        symbol = _symbol;
        baseURI = _baseURI;
        owner = msg.sender;
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0), "Token does not exist");
        return tokenOwner;
    }

    function balanceOf(address account) external view returns (uint256) {
        require(account != address(0), "Zero address");
        return _balances[account];
    }

    function mint(address to, string calldata uri) external onlyOwner returns (uint256) {
        // FIX: Enforce max supply cap
        require(_nextTokenId < MAX_SUPPLY, "Max supply reached");
        // FIX: Reject zero address to prevent burnt-on-mint tokens
        require(to != address(0), "Mint to zero address");

        uint256 tokenId = _nextTokenId++;
        _owners[tokenId] = to;
        _balances[to]++;
        _tokenURIs[tokenId] = uri;

        emit Transfer(address(0), to, tokenId);
        return tokenId;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        // FIX: Revert for non-existent tokens instead of returning empty string
        require(_owners[tokenId] != address(0), "Token does not exist");
        string memory _uri = _tokenURIs[tokenId];
        if (bytes(_uri).length > 0) {
            return _uri;
        }
        return string(abi.encodePacked(baseURI, _toString(tokenId)));
    }

    function approve(address to, uint256 tokenId) external {
        require(_owners[tokenId] == msg.sender, "Not token owner");
        _tokenApprovals[tokenId] = to;
        emit Approval(msg.sender, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        require(operator != msg.sender, "Self-approval");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_owners[tokenId] != address(0), "Token does not exist");
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner_, address operator) external view returns (bool) {
        return _operatorApprovals[owner_][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_owners[tokenId] == from, "Not token owner");
        require(
            msg.sender == from || _tokenApprovals[tokenId] == msg.sender || _operatorApprovals[from][msg.sender],
            "Not approved"
        );
        require(to != address(0), "Transfer to zero");

        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
        delete _tokenApprovals[tokenId];

        emit Transfer(from, to, tokenId);
    }

    function setBaseURI(string calldata _baseURI) external onlyOwner {
        baseURI = _baseURI;
    }

    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
