// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {BaselineNFT} from "../src/BaselineNFT.sol";
import {AcceptingReceiver} from "./helpers/Receivers.sol";

contract BaselineNFTTest is Test {
    string internal constant BASE_URI = "https://batchnft.example/token/";

    BaselineNFT internal nft;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        nft = new BaselineNFT("BaselineNFT", "BASE", BASE_URI);
    }

    function test_metadata() public view {
        assertEq(nft.name(), "BaselineNFT");
        assertEq(nft.symbol(), "BASE");
        assertEq(nft.MAX_SUPPLY(), 10_000);
        assertEq(nft.MAX_BATCH(), 20);
        assertEq(nft.totalSupply(), 0);
    }

    function test_mint_idsStartAtOneAndEmitOneTransferPerId() public {
        for (uint256 id = 1; id <= 4; ++id) {
            vm.expectEmit(true, true, true, true, address(nft));
            emit IERC721.Transfer(address(0), alice, id);
        }
        vm.prank(alice);
        nft.mint(4);
        assertEq(nft.totalSupply(), 4);
        assertEq(nft.balanceOf(alice), 4);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(4), alice);
        assertEq(nft.tokenURI(4), string.concat(BASE_URI, "4"));
    }

    function test_mint_revertsOnZeroAndAboveMaxBatch() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BaselineNFT.InvalidQuantity.selector, 0));
        nft.mint(0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BaselineNFT.InvalidQuantity.selector, 21));
        nft.mint(21);
    }

    function test_mint_respectsMaxSupply() public {
        for (uint256 i = 0; i < 499; ++i) {
            vm.prank(alice);
            nft.mint(20);
        }
        vm.prank(alice);
        nft.mint(10);
        assertEq(nft.totalSupply(), 9_990);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BaselineNFT.MaxSupplyExceeded.selector, 11, 10));
        nft.mint(11);

        vm.prank(bob);
        nft.mint(10);
        assertEq(nft.ownerOf(10_000), bob);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BaselineNFT.MaxSupplyExceeded.selector, 1, 0));
        nft.mint(1);
    }

    function test_mint_doesNotCallReceiverHook() public {
        AcceptingReceiver receiver = new AcceptingReceiver();
        vm.prank(address(receiver));
        nft.mint(2);
        assertEq(receiver.calls(), 0);
        assertEq(nft.ownerOf(2), address(receiver));
    }

    function test_ownerOf_revertsForUnminted() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        nft.ownerOf(1);
    }
}
