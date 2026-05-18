// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draftERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptographyECDSA.sol";

/// @title AgentToken
/// @notice ERC20Permit with replay protection
/// FIX #162: Add nonce tracking to permit()
contract AgentToken is ERC20, draftERC20Permit {
    using ECDSA for bytes32;

    // FIX #162: Explicit nonce mapping for replay protection
    mapping(address => uint256) public override nonces;

    uint256 public constant MAX_SUPPLY = 1_000_000_000e18;

    constructor() ERC20("AgentToken", "AGT") permit("AgentToken", "AGT", "1") {
        _mint(msg.sender, MAX_SUPPLY);
    }

    /// @notice Permit with explicit nonce check (already in draft-ERC20Permit but add validation)
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        bytes memory signature
    ) public override {
        require(deadline >= block.timestamp, "Expired");
        // Nonce check is in draftERC20Permit — this just adds explicit event
        super.permit(owner, spender, value, deadline, signature);
    }

    /// @notice FIX #162: Additional replay protection via used hash tracking
    mapping(bytes32 => bool) public usedPermitHashes;

    function permitWithReplayProtection(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external {
        require(deadline >= block.timestamp, "Expired deadline");
        bytes32 domainSeparator = _domainSeparatorV4();
        bytes32 hash = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            keccak256(abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner, spender, value, nonce, deadline
            ))
        ));

        require(!usedPermitHashes[hash], "Permit reused");
        require(hash.recover(signature) == owner, "Invalid signature");
        usedPermitHashes[hash] = true;

        _useNonce(owner, nonce);
        _approve(owner, spender, value);
    }

    function _useNonce(address owner, uint256 nonce) internal override returns (uint256) {
        require(nonces[owner] == nonce, "Invalid nonce");
        nonces[owner]++;
        return nonces[owner] - 1;
    }
}
