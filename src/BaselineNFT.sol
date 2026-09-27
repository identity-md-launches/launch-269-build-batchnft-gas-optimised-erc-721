// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title BaselineNFT
/// @notice Plain OpenZeppelin ERC721 with the same mint rules as BatchNFT, used as the gas and
///         behaviour baseline. Each id in a batch is minted with a separate `_mint`, which writes
///         one owner slot per token and (in OpenZeppelin's `_update`) updates the balance per token.
contract BaselineNFT is ERC721 {
    uint256 public constant MAX_SUPPLY = 10_000;
    uint256 public constant MAX_BATCH = 20;
    uint256 public constant START_TOKEN_ID = 1;

    error InvalidQuantity(uint256 quantity);
    error MaxSupplyExceeded(uint256 requested, uint256 remaining);

    string private _baseTokenURI;
    uint256 private _nextTokenId = START_TOKEN_ID;

    constructor(string memory name_, string memory symbol_, string memory baseTokenURI_) ERC721(name_, symbol_) {
        _baseTokenURI = baseTokenURI_;
    }

    /// @notice Mint `quantity` consecutive tokens to the caller. Free, public, no receiver callback.
    function mint(uint256 quantity) external {
        if (quantity == 0 || quantity > MAX_BATCH) revert InvalidQuantity(quantity);

        uint256 startId = _nextTokenId;
        uint256 remaining = MAX_SUPPLY + START_TOKEN_ID - startId;
        if (quantity > remaining) revert MaxSupplyExceeded(quantity, remaining);

        uint256 endId = startId + quantity;
        for (uint256 id = startId; id < endId; ++id) {
            _mint(msg.sender, id);
        }
        _nextTokenId = endId;
    }

    /// @notice Number of tokens minted so far.
    function totalSupply() external view returns (uint256) {
        return _nextTokenId - START_TOKEN_ID;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}
