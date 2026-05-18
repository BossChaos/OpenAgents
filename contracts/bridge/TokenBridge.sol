// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TokenBridge
/// @notice Bridge with replay protection
/// FIX #112: Nonce tracking + destination validation
contract TokenBridge {
    using SafeERC20 for IERC20;

    struct Transfer {
        address recipient;
        address token;
        uint256 amount;
        uint256 destination;
        bool processed;
    }

    mapping(bytes32 => bool) public usedHashes;
    mapping(address => uint256) public nonces;

    event BridgeInitiated(bytes32 indexed hash, address recipient, uint256 destination, uint256 amount);
    event BridgeRelayed(bytes32 indexed hash);

    /// @notice Initiate cross-chain transfer with nonce
    function bridgeTransfer(
        address token,
        uint256 amount,
        uint256 destination,
        uint256 salt
    ) external returns (bytes32) {
        require(destination > 0, "Invalid destination");
        require(amount > 0, "Zero amount");

        uint256 nonce = nonces[msg.sender]++;
        bytes32 hash = keccak256(abi.encodePacked(
            msg.sender, token, amount, destination, nonce, salt, address(this)
        ));

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit BridgeInitiated(hash, msg.sender, destination, amount);
        return hash;
    }

    /// @notice Relay transfer from another chain
    function relayTransfer(
        address recipient,
        address token,
        uint256 amount,
        uint256 sourceChain,
        bytes32 origHash,
        bytes calldata signature
    ) external {
        require(!usedHashes[origHash], "Already used");
        require(_verifySignature(recipient, token, amount, sourceChain, origHash, signature), "Invalid sig");
        require(recipient != address(0), "Zero recipient");

        usedHashes[origHash] = true;
        IERC20(token).safeTransfer(recipient, amount);
        emit BridgeRelayed(origHash);
    }

    function _verifySignature(
        address recipient,
        address token,
        uint256 amount,
        uint256 sourceChain,
        bytes32 hash,
        bytes calldata sig
    ) internal pure returns (bool) {
        bytes32 ethHash = keccak256(abi.encodePacked(recipient, token, amount, sourceChain, hash));
        bytes32 prefixed = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", ethHash));
        (bytes32 r, bytes32 s, uint8 v) = _splitSig(sig);
        return ecrecover(prefixed, v, r, s) != address(0);
    }

    function _splitSig(bytes calldata sig) internal pure returns (bytes32, bytes32, uint8) {
        require(sig.length == 65, "Invalid sig length");
        return (
            bytes32(sig[0:32]),
            bytes32(sig[32:64]),
            uint8(sig[64])
        );
    }
}
