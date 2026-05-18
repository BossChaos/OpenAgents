// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TokenBridge
/// @notice Cross-chain token bridge with multi-validator signature verification.
/// @dev Users lock tokens on the source chain and claim on the destination chain
///      after a quorum of validators sign the transfer message.
contract TokenBridge is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Transfer {
        address token;
        address sender;
        address recipient;
        uint256 amount;
        bool claimed;
        uint256 nonce;
        uint256 chainId;
    }

    address public admin;
    uint256 public requiredSignatures;
    uint256 public currentChainId;
    uint256 private _nonceCounter;
    mapping(address => bool) public isValidator;
    mapping(bytes32 => Transfer) public transfers;
    mapping(bytes32 => bool) public processedHashes;

    event TokensLocked(bytes32 indexed transferId, address token, address sender, address recipient, uint256 amount, uint256 nonce);
    event TokensClaimed(bytes32 indexed transferId, address token, address recipient, uint256 amount);
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Bridge: not admin");
        _;
    }

    constructor(uint256 _requiredSignatures, uint256 _chainId) {
        admin = msg.sender;
        requiredSignatures = _requiredSignatures;
        currentChainId = _chainId;
    }

    /// @notice Lock tokens on the source chain to initiate a cross-chain transfer.
    function lock(address token, address recipient, uint256 amount) external nonReentrant {
        require(amount > 0, "Bridge: zero amount");
        require(recipient != address(0), "Bridge: zero recipient");

        // FIX: Include chainId and nonce to prevent cross-chain replay and transferId collisions
        uint256 nonce = _nonceCounter++;
        bytes32 transferId = keccak256(abi.encodePacked(currentChainId, nonce, token, msg.sender, recipient, amount));

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        transfers[transferId] = Transfer({
            token: token,
            sender: msg.sender,
            recipient: recipient,
            amount: amount,
            claimed: false,
            nonce: nonce,
            chainId: currentChainId
        });

        emit TokensLocked(transferId, token, msg.sender, recipient, amount, nonce);
    }

    /// @notice Claim bridged tokens on the destination chain with validator signatures.
    function claim(
        address token,
        address recipient,
        uint256 amount,
        bytes[] calldata signatures
    ) external nonReentrant {
        // FIX: Include chainId in the message hash to prevent cross-chain replay
        bytes32 messageHash = keccak256(abi.encodePacked(currentChainId, token, recipient, amount, block.chainid));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));

        require(!processedHashes[messageHash], "Bridge: already processed");
        require(signatures.length >= requiredSignatures, "Bridge: insufficient sigs");

        uint256 validSigs = 0;
        address lastSigner = address(0);
        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = _recover(ethSignedHash, signatures[i]);
            // FIX: Reject ecrecover failures that return address(0)
            require(signer != address(0), "Bridge: invalid signature");
            require(signer > lastSigner, "Bridge: duplicate or unordered sig");
            lastSigner = signer;
            if (isValidator[signer]) {
                validSigs++;
            }
        }

        require(validSigs >= requiredSignatures, "Bridge: not enough valid sigs");
        processedHashes[messageHash] = true;

        IERC20(token).safeTransfer(recipient, amount);
        emit TokensClaimed(messageHash, token, recipient, amount);
    }

    function addValidator(address validator) external onlyAdmin {
        require(validator != address(0), "Bridge: zero address");
        isValidator[validator] = true;
        emit ValidatorAdded(validator);
    }

    function removeValidator(address validator) external onlyAdmin {
        isValidator[validator] = false;
        emit ValidatorRemoved(validator);
    }

    function _recover(bytes32 hash, bytes memory sig) internal pure returns (address) {
        require(sig.length == 65, "Bridge: invalid sig length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        return ecrecover(hash, v, r, s);
    }
}
