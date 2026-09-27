// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @title BatchNFT
/// @notice Gas-optimised ERC-721 with ERC721A-style batch minting.
/// @dev Storage model:
///      - Token ids are sequential, starting at 1. `_nextTokenId` is the id the next mint receives.
///      - `_packed[id]` holds `owner (160 bits) | startTimestamp (64 bits, shifted left by 160)`.
///        A mint of `quantity` tokens writes exactly one slot, at the first id of the batch. Every
///        other id in the batch is left at zero and implicitly belongs to the nearest written slot
///        below it. Because a batch is at most `MAX_BATCH` tokens, `ownerOf` walks back at most
///        `MAX_BATCH - 1` slots.
///      - A transfer writes the moved token's slot. If the next id exists and its slot is still
///        empty, that slot is filled with the previous slot data (previous owner and original start
///        timestamp), so the remainder of the batch keeps its owner.
///      - There is no burn, so a zero slot always means "inherit from below", never "destroyed".
///      No receiver callback is run on mint. `safeTransferFrom` runs `onERC721Received`.
contract BatchNFT is IERC721, IERC721Metadata {
    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    /// @notice Highest token id that can ever be minted.
    uint256 public constant MAX_SUPPLY = 10_000;
    /// @notice Largest number of tokens a single `mint` call may create.
    uint256 public constant MAX_BATCH = 20;
    /// @notice First token id.
    uint256 public constant START_TOKEN_ID = 1;

    uint256 private constant _BITMASK_ADDRESS = (1 << 160) - 1;
    uint256 private constant _BITPOS_START_TIMESTAMP = 160;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error InvalidQuantity(uint256 quantity);
    error MaxSupplyExceeded(uint256 requested, uint256 remaining);
    error NonexistentToken(uint256 tokenId);
    error InvalidReceiver(address receiver);
    error InvalidOperator(address operator);
    error IncorrectOwner(address sender, uint256 tokenId, address owner);
    error InsufficientApproval(address operator, uint256 tokenId);
    error InvalidApprover(address approver);
    error TransferToNonERC721Receiver(address receiver);

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    string private _name;
    string private _symbol;
    string private _baseTokenURI;

    /// @dev Next token id to be minted. Starts at `START_TOKEN_ID`.
    uint256 private _nextTokenId = START_TOKEN_ID;

    /// @dev Packed ownership: bits [0..159] owner, bits [160..223] start timestamp.
    mapping(uint256 tokenId => uint256 packed) private _packed;

    mapping(address owner => uint256 balance) private _balances;
    mapping(uint256 tokenId => address approved) private _tokenApprovals;
    mapping(address owner => mapping(address operator => bool approved)) private _operatorApprovals;

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    /// @param name_ Collection name.
    /// @param symbol_ Collection symbol.
    /// @param baseTokenURI_ Fixed prefix; `tokenURI(id)` returns `baseTokenURI_ ++ decimal(id)`.
    constructor(string memory name_, string memory symbol_, string memory baseTokenURI_) {
        _name = name_;
        _symbol = symbol_;
        _baseTokenURI = baseTokenURI_;
    }

    // ---------------------------------------------------------------------
    // Minting
    // ---------------------------------------------------------------------

    /// @notice Mint `quantity` consecutive tokens to the caller. Free, public, no receiver callback.
    /// @dev Writes a single ownership slot for the whole batch and emits one Transfer per id.
    /// @param quantity Number of tokens to mint, between 1 and `MAX_BATCH` inclusive.
    function mint(uint256 quantity) external {
        if (quantity == 0 || quantity > MAX_BATCH) revert InvalidQuantity(quantity);

        uint256 startId = _nextTokenId;
        uint256 remaining = MAX_SUPPLY + START_TOKEN_ID - startId;
        if (quantity > remaining) revert MaxSupplyExceeded(quantity, remaining);

        address to = msg.sender;
        _packed[startId] = _pack(to, block.timestamp);

        unchecked {
            _balances[to] += quantity;
            uint256 endId = startId + quantity;
            for (uint256 id = startId; id < endId; ++id) {
                emit Transfer(address(0), to, id);
            }
            _nextTokenId = endId;
        }
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice Number of tokens minted so far.
    function totalSupply() external view returns (uint256) {
        unchecked {
            return _nextTokenId - START_TOKEN_ID;
        }
    }

    /// @inheritdoc IERC721Metadata
    function name() external view returns (string memory) {
        return _name;
    }

    /// @inheritdoc IERC721Metadata
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IERC721Metadata
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (!_exists(tokenId)) revert NonexistentToken(tokenId);
        return string.concat(_baseTokenURI, _toString(tokenId));
    }

    /// @inheritdoc IERC721
    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert InvalidReceiver(address(0));
        return _balances[owner];
    }

    /// @inheritdoc IERC721
    function ownerOf(uint256 tokenId) public view returns (address) {
        return address(uint160(_packedOwnershipOf(tokenId)));
    }

    /// @notice Owner and mint timestamp of `tokenId`, resolved through the batch walk.
    function ownershipOf(uint256 tokenId) external view returns (address owner, uint64 startTimestamp) {
        uint256 packed = _packedOwnershipOf(tokenId);
        owner = address(uint160(packed));
        startTimestamp = uint64(packed >> _BITPOS_START_TIMESTAMP);
    }

    /// @notice Raw slot contents for `tokenId` with no walk. Both values are zero if the slot was never written.
    function rawOwnershipSlot(uint256 tokenId) external view returns (address owner, uint64 startTimestamp) {
        uint256 packed = _packed[tokenId];
        owner = address(uint160(packed));
        startTimestamp = uint64(packed >> _BITPOS_START_TIMESTAMP);
    }

    /// @inheritdoc IERC721
    function getApproved(uint256 tokenId) public view returns (address) {
        if (!_exists(tokenId)) revert NonexistentToken(tokenId);
        return _tokenApprovals[tokenId];
    }

    /// @inheritdoc IERC721
    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC721Metadata).interfaceId;
    }

    // ---------------------------------------------------------------------
    // Approvals
    // ---------------------------------------------------------------------

    /// @inheritdoc IERC721
    function approve(address to, uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        if (msg.sender != owner && !isApprovedForAll(owner, msg.sender)) revert InvalidApprover(msg.sender);
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    /// @inheritdoc IERC721
    function setApprovalForAll(address operator, bool approved) external {
        if (operator == address(0)) revert InvalidOperator(address(0));
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    // ---------------------------------------------------------------------
    // Transfers
    // ---------------------------------------------------------------------

    /// @inheritdoc IERC721
    function transferFrom(address from, address to, uint256 tokenId) public {
        _transfer(from, to, tokenId);
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    /// @inheritdoc IERC721
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        _transfer(from, to, tokenId);
        _checkOnERC721Received(from, to, tokenId, data);
    }

    // ---------------------------------------------------------------------
    // Internals
    // ---------------------------------------------------------------------

    function _exists(uint256 tokenId) private view returns (bool) {
        return tokenId >= START_TOKEN_ID && tokenId < _nextTokenId;
    }

    function _pack(address owner, uint256 timestamp) private pure returns (uint256) {
        return uint256(uint160(owner)) | (uint256(uint64(timestamp)) << _BITPOS_START_TIMESTAMP);
    }

    /// @dev Walks back from `tokenId` to the nearest written slot. Reverts for ids outside [1, minted].
    function _packedOwnershipOf(uint256 tokenId) private view returns (uint256 packed) {
        if (!_exists(tokenId)) revert NonexistentToken(tokenId);
        unchecked {
            uint256 current = tokenId;
            packed = _packed[current];
            // Every batch writes its first slot, and a batch has at most MAX_BATCH ids, so this loop
            // terminates after at most MAX_BATCH - 1 iterations without leaving the batch.
            while (packed == 0) {
                --current;
                packed = _packed[current];
            }
        }
    }

    function _transfer(address from, address to, uint256 tokenId) private {
        if (to == address(0)) revert InvalidReceiver(address(0));

        uint256 prevPacked = _packedOwnershipOf(tokenId);
        address owner = address(uint160(prevPacked));
        if (owner != from) revert IncorrectOwner(from, tokenId, owner);

        if (msg.sender != from && !isApprovedForAll(from, msg.sender) && _tokenApprovals[tokenId] != msg.sender) {
            revert InsufficientApproval(msg.sender, tokenId);
        }

        // Clear the per-token approval (no event; ERC-721 only requires Transfer here).
        delete _tokenApprovals[tokenId];

        unchecked {
            _balances[from] -= 1;
            _balances[to] += 1;

            _packed[tokenId] = _pack(to, block.timestamp);

            uint256 nextId = tokenId + 1;
            if (_packed[nextId] == 0 && nextId < _nextTokenId) {
                // Next id is part of the same batch and still inherits from this slot: give it the
                // previous slot data so the rest of the batch keeps the previous owner.
                _packed[nextId] = prevPacked;
            }
        }

        emit Transfer(from, to, tokenId);
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private {
        if (to.code.length == 0) return;
        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            if (retval != IERC721Receiver.onERC721Received.selector) revert TransferToNonERC721Receiver(to);
        } catch (bytes memory reason) {
            if (reason.length == 0) revert TransferToNonERC721Receiver(to);
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }

    function _toString(uint256 value) private pure returns (string memory str) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits = 0;
        while (temp != 0) {
            ++digits;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            --digits;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        str = string(buffer);
    }
}
