// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/// @dev Accepts every token and records the last call.
contract AcceptingReceiver is IERC721Receiver {
    address public lastOperator;
    address public lastFrom;
    uint256 public lastTokenId;
    bytes public lastData;
    uint256 public calls;

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4)
    {
        lastOperator = operator;
        lastFrom = from;
        lastTokenId = tokenId;
        lastData = data;
        calls += 1;
        return IERC721Receiver.onERC721Received.selector;
    }
}

/// @dev Returns the wrong magic value.
contract WrongMagicReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0xdeadbeef;
    }
}

/// @dev Reverts with a custom reason.
contract RevertingReceiver {
    error Nope(uint256 tokenId);

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external pure returns (bytes4) {
        revert Nope(tokenId);
    }
}

/// @dev Reverts with no data at all.
contract SilentRevertReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        // solhint-disable-next-line reason-string
        revert();
    }
}

/// @dev Has code but no onERC721Received function and no fallback.
contract NoHookContract {
    uint256 public x;
}
