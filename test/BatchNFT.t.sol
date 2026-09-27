// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {BatchNFT} from "../src/BatchNFT.sol";
import {
    AcceptingReceiver,
    WrongMagicReceiver,
    RevertingReceiver,
    SilentRevertReceiver,
    NoHookContract
} from "./helpers/Receivers.sol";

contract BatchNFTTest is Test {
    string internal constant BASE_URI = "https://batchnft.example/token/";

    BatchNFT internal nft;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal operator = makeAddr("operator");

    function setUp() public {
        nft = new BatchNFT("BatchNFT", "BNFT", BASE_URI);
    }

    // ------------------------------------------------------------------
    // Metadata / ERC-165
    // ------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(nft.name(), "BatchNFT");
        assertEq(nft.symbol(), "BNFT");
        assertEq(nft.MAX_SUPPLY(), 10_000);
        assertEq(nft.MAX_BATCH(), 20);
        assertEq(nft.START_TOKEN_ID(), 1);
        assertEq(nft.totalSupply(), 0);
    }

    function test_supportsInterface() public view {
        assertTrue(nft.supportsInterface(type(IERC165).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC721Metadata).interfaceId));
        assertFalse(nft.supportsInterface(0xffffffff));
        assertFalse(nft.supportsInterface(0x780e9d63)); // ERC721Enumerable: intentionally unsupported
    }

    function test_tokenURI() public {
        vm.prank(alice);
        nft.mint(3);
        assertEq(nft.tokenURI(1), string.concat(BASE_URI, "1"));
        assertEq(nft.tokenURI(3), string.concat(BASE_URI, "3"));
    }

    function test_tokenURI_revertsForNonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.NonexistentToken.selector, 1));
        nft.tokenURI(1);
        vm.prank(alice);
        nft.mint(2);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.NonexistentToken.selector, 0));
        nft.tokenURI(0);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.NonexistentToken.selector, 3));
        nft.tokenURI(3);
    }

    // ------------------------------------------------------------------
    // Minting
    // ------------------------------------------------------------------

    function test_mint_idsStartAtOneAndEmitOneTransferPerId() public {
        for (uint256 id = 1; id <= 5; ++id) {
            vm.expectEmit(true, true, true, true, address(nft));
            emit IERC721.Transfer(address(0), alice, id);
        }
        vm.prank(alice);
        nft.mint(5);

        assertEq(nft.totalSupply(), 5);
        assertEq(nft.balanceOf(alice), 5);
        for (uint256 id = 1; id <= 5; ++id) {
            assertEq(nft.ownerOf(id), alice);
        }
    }

    function test_mint_writesOnlyFirstSlotOfBatch() public {
        vm.warp(1_700_000_000);
        vm.prank(alice);
        nft.mint(20);

        (address o, uint64 ts) = nft.rawOwnershipSlot(1);
        assertEq(o, alice);
        assertEq(ts, 1_700_000_000);
        for (uint256 id = 2; id <= 20; ++id) {
            (o, ts) = nft.rawOwnershipSlot(id);
            assertEq(o, address(0));
            assertEq(ts, 0);
            (address resolved, uint64 resolvedTs) = nft.ownershipOf(id);
            assertEq(resolved, alice);
            assertEq(resolvedTs, 1_700_000_000);
        }
    }

    function test_mint_consecutiveBatchesFromDifferentMinters() public {
        vm.prank(alice);
        nft.mint(3);
        vm.prank(bob);
        nft.mint(1);
        vm.prank(carol);
        nft.mint(20);

        assertEq(nft.ownerOf(3), alice);
        assertEq(nft.ownerOf(4), bob);
        assertEq(nft.ownerOf(5), carol);
        assertEq(nft.ownerOf(24), carol);
        assertEq(nft.balanceOf(alice), 3);
        assertEq(nft.balanceOf(bob), 1);
        assertEq(nft.balanceOf(carol), 20);
        assertEq(nft.totalSupply(), 24);
    }

    function test_mint_revertsOnZeroQuantity() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.InvalidQuantity.selector, 0));
        nft.mint(0);
    }

    function test_mint_revertsAboveMaxBatch() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.InvalidQuantity.selector, 21));
        nft.mint(21);
    }

    function test_mint_respectsMaxSupply() public {
        // Fill to 9,990 in batches of 20.
        for (uint256 i = 0; i < 499; ++i) {
            vm.prank(alice);
            nft.mint(20);
        }
        vm.prank(alice);
        nft.mint(10);
        assertEq(nft.totalSupply(), 9_990);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.MaxSupplyExceeded.selector, 11, 10));
        nft.mint(11);

        vm.prank(bob);
        nft.mint(10);
        assertEq(nft.totalSupply(), 10_000);
        assertEq(nft.ownerOf(10_000), bob);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.MaxSupplyExceeded.selector, 1, 0));
        nft.mint(1);
    }

    function test_mint_doesNotCallReceiverHook() public {
        AcceptingReceiver receiver = new AcceptingReceiver();
        vm.prank(address(receiver));
        nft.mint(2);
        assertEq(receiver.calls(), 0);
        assertEq(nft.ownerOf(1), address(receiver));
        assertEq(nft.ownerOf(2), address(receiver));
    }

    // ------------------------------------------------------------------
    // ownerOf / balanceOf
    // ------------------------------------------------------------------

    function test_ownerOf_revertsForZeroAndUnminted() public {
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.NonexistentToken.selector, 1));
        nft.ownerOf(1);
        vm.prank(alice);
        nft.mint(4);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.NonexistentToken.selector, 0));
        nft.ownerOf(0);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.NonexistentToken.selector, 5));
        nft.ownerOf(5);
    }

    function test_balanceOf_zeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.InvalidReceiver.selector, address(0)));
        nft.balanceOf(address(0));
    }

    function test_balanceOf_unknownAddressIsZero() public view {
        assertEq(nft.balanceOf(bob), 0);
    }

    // ------------------------------------------------------------------
    // Transfers: slot bookkeeping
    // ------------------------------------------------------------------

    function _mintBatchAs(address who, uint256 qty, uint256 ts) internal returns (uint256 startId) {
        startId = nft.totalSupply() + 1;
        vm.warp(ts);
        vm.prank(who);
        nft.mint(qty);
    }

    function test_transfer_firstOfBatch_backfillsNextSlot() public {
        _mintBatchAs(alice, 5, 1000);
        vm.warp(2000);

        vm.expectEmit(true, true, true, true, address(nft));
        emit IERC721.Transfer(alice, bob, 1);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 1);

        assertEq(nft.ownerOf(1), bob);
        for (uint256 id = 2; id <= 5; ++id) {
            assertEq(nft.ownerOf(id), alice);
        }
        assertEq(nft.balanceOf(alice), 4);
        assertEq(nft.balanceOf(bob), 1);

        (address o1, uint64 t1) = nft.rawOwnershipSlot(1);
        assertEq(o1, bob);
        assertEq(t1, 2000);
        (address o2, uint64 t2) = nft.rawOwnershipSlot(2);
        assertEq(o2, alice);
        assertEq(t2, 1000); // backfilled slot carries the original batch timestamp
        (address o3,) = nft.rawOwnershipSlot(3);
        assertEq(o3, address(0)); // untouched
    }

    function test_transfer_middleOfBatch() public {
        _mintBatchAs(alice, 5, 1000);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 3);

        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(2), alice);
        assertEq(nft.ownerOf(3), bob);
        assertEq(nft.ownerOf(4), alice);
        assertEq(nft.ownerOf(5), alice);

        (address o4,) = nft.rawOwnershipSlot(4);
        assertEq(o4, alice);
        (address o5,) = nft.rawOwnershipSlot(5);
        assertEq(o5, address(0));
    }

    function test_transfer_lastOfBatch_doesNotWriteBeyondMinted() public {
        _mintBatchAs(alice, 5, 1000);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 5);

        assertEq(nft.ownerOf(5), bob);
        assertEq(nft.ownerOf(4), alice);
        (address o6,) = nft.rawOwnershipSlot(6);
        assertEq(o6, address(0));

        // A later batch starting at 6 is unaffected.
        _mintBatchAs(carol, 2, 3000);
        assertEq(nft.ownerOf(6), carol);
        assertEq(nft.ownerOf(7), carol);
    }

    function test_transfer_lastOfBatch_doesNotOverwriteNextBatchStart() public {
        _mintBatchAs(alice, 3, 1000);
        _mintBatchAs(bob, 3, 1000);
        vm.prank(alice);
        nft.transferFrom(alice, carol, 3);

        assertEq(nft.ownerOf(3), carol);
        assertEq(nft.ownerOf(4), bob);
        (address o4,) = nft.rawOwnershipSlot(4);
        assertEq(o4, bob);
    }

    function test_transfer_nextSlotAlreadyWrittenIsLeftAlone() public {
        _mintBatchAs(alice, 4, 1000);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 2); // writes 2 -> bob, 3 -> alice
        vm.prank(alice);
        nft.transferFrom(alice, carol, 1); // 2 already written, must not be touched

        assertEq(nft.ownerOf(1), carol);
        assertEq(nft.ownerOf(2), bob);
        assertEq(nft.ownerOf(3), alice);
        assertEq(nft.ownerOf(4), alice);
    }

    function test_transfer_backToBackTransfersOfSameToken() public {
        _mintBatchAs(alice, 3, 1000);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 2);
        vm.prank(bob);
        nft.transferFrom(bob, carol, 2);
        vm.prank(carol);
        nft.transferFrom(carol, alice, 2);

        assertEq(nft.ownerOf(2), alice);
        assertEq(nft.balanceOf(alice), 3);
        assertEq(nft.balanceOf(bob), 0);
        assertEq(nft.balanceOf(carol), 0);
    }

    function test_transfer_selfTransfer() public {
        _mintBatchAs(alice, 3, 1000);
        vm.expectEmit(true, true, true, true, address(nft));
        emit IERC721.Transfer(alice, alice, 1);
        vm.prank(alice);
        nft.transferFrom(alice, alice, 1);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(2), alice);
        assertEq(nft.balanceOf(alice), 3);
    }

    function test_transfer_walkNeverExceedsNineteenSteps() public {
        _mintBatchAs(alice, 20, 1000);
        _mintBatchAs(bob, 20, 1000);
        // id 40 is the 20th token of bob's batch: 19 steps back to id 21.
        assertEq(nft.ownerOf(40), bob);
        assertEq(nft.ownerOf(20), alice);
        vm.prank(bob);
        nft.transferFrom(bob, carol, 40);
        assertEq(nft.ownerOf(40), carol);
        assertEq(nft.ownerOf(39), bob);
    }

    function test_transfer_updatesTimestampForMovedToken() public {
        _mintBatchAs(alice, 2, 1000);
        vm.warp(5000);
        vm.prank(alice);
        nft.transferFrom(alice, bob, 2);
        (address o, uint64 ts) = nft.ownershipOf(2);
        assertEq(o, bob);
        assertEq(ts, 5000);
        (o, ts) = nft.ownershipOf(1);
        assertEq(o, alice);
        assertEq(ts, 1000);
    }

    // ------------------------------------------------------------------
    // Transfers: authorisation and failure paths
    // ------------------------------------------------------------------

    function test_transfer_revertsToZeroAddress() public {
        _mintBatchAs(alice, 1, 1000);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.InvalidReceiver.selector, address(0)));
        nft.transferFrom(alice, address(0), 1);
    }

    function test_transfer_revertsWhenFromIsNotOwner() public {
        _mintBatchAs(alice, 1, 1000);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.IncorrectOwner.selector, bob, 1, alice));
        nft.transferFrom(bob, carol, 1);
    }

    function test_transfer_revertsWhenUnauthorised() public {
        _mintBatchAs(alice, 2, 1000);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.InsufficientApproval.selector, bob, 2));
        nft.transferFrom(alice, bob, 2);
    }

    function test_transfer_revertsForNonexistentToken() public {
        _mintBatchAs(alice, 2, 1000);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.NonexistentToken.selector, 3));
        nft.transferFrom(alice, bob, 3);
    }

    function test_transfer_byApprovedAddress_clearsApproval() public {
        _mintBatchAs(alice, 3, 1000);
        vm.prank(alice);
        nft.approve(operator, 2);
        assertEq(nft.getApproved(2), operator);

        vm.prank(operator);
        nft.transferFrom(alice, bob, 2);
        assertEq(nft.ownerOf(2), bob);
        assertEq(nft.getApproved(2), address(0));

        // The stale approval must not let the operator move it again.
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.InsufficientApproval.selector, operator, 2));
        nft.transferFrom(bob, carol, 2);
    }

    function test_transfer_approvalIsPerToken() public {
        _mintBatchAs(alice, 3, 1000);
        vm.prank(alice);
        nft.approve(operator, 2);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.InsufficientApproval.selector, operator, 3));
        nft.transferFrom(alice, bob, 3);
    }

    function test_transfer_byOperatorForAll() public {
        _mintBatchAs(alice, 3, 1000);
        vm.expectEmit(true, true, true, true, address(nft));
        emit IERC721.ApprovalForAll(alice, operator, true);
        vm.prank(alice);
        nft.setApprovalForAll(operator, true);
        assertTrue(nft.isApprovedForAll(alice, operator));

        vm.prank(operator);
        nft.transferFrom(alice, bob, 1);
        vm.prank(operator);
        nft.transferFrom(alice, bob, 3);
        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.ownerOf(2), alice);
        assertEq(nft.ownerOf(3), bob);

        vm.prank(alice);
        nft.setApprovalForAll(operator, false);
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.InsufficientApproval.selector, operator, 2));
        nft.transferFrom(alice, bob, 2);
    }

    function test_setApprovalForAll_zeroOperatorReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.InvalidOperator.selector, address(0)));
        nft.setApprovalForAll(address(0), true);
    }

    // ------------------------------------------------------------------
    // approve / getApproved
    // ------------------------------------------------------------------

    function test_approve_emitsAndStores() public {
        _mintBatchAs(alice, 2, 1000);
        vm.expectEmit(true, true, true, true, address(nft));
        emit IERC721.Approval(alice, bob, 2);
        vm.prank(alice);
        nft.approve(bob, 2);
        assertEq(nft.getApproved(2), bob);
        assertEq(nft.getApproved(1), address(0));
    }

    function test_approve_byOperatorForAll() public {
        _mintBatchAs(alice, 2, 1000);
        vm.prank(alice);
        nft.setApprovalForAll(operator, true);
        vm.prank(operator);
        nft.approve(bob, 1);
        assertEq(nft.getApproved(1), bob);
    }

    function test_approve_revertsForNonOwner() public {
        _mintBatchAs(alice, 2, 1000);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.InvalidApprover.selector, bob));
        nft.approve(bob, 1);
    }

    function test_approve_revertsForNonexistent() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.NonexistentToken.selector, 1));
        nft.approve(bob, 1);
    }

    function test_getApproved_revertsForNonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.NonexistentToken.selector, 7));
        nft.getApproved(7);
    }

    // ------------------------------------------------------------------
    // safeTransferFrom
    // ------------------------------------------------------------------

    function test_safeTransfer_toEOA() public {
        _mintBatchAs(alice, 2, 1000);
        vm.prank(alice);
        nft.safeTransferFrom(alice, bob, 1);
        assertEq(nft.ownerOf(1), bob);
        assertEq(nft.ownerOf(2), alice);
    }

    function test_safeTransfer_toAcceptingReceiver_passesArguments() public {
        AcceptingReceiver receiver = new AcceptingReceiver();
        _mintBatchAs(alice, 2, 1000);
        vm.prank(alice);
        nft.setApprovalForAll(operator, true);

        vm.prank(operator);
        nft.safeTransferFrom(alice, address(receiver), 2, hex"c0ffee");

        assertEq(receiver.calls(), 1);
        assertEq(receiver.lastOperator(), operator);
        assertEq(receiver.lastFrom(), alice);
        assertEq(receiver.lastTokenId(), 2);
        assertEq(receiver.lastData(), hex"c0ffee");
        assertEq(nft.ownerOf(2), address(receiver));
        assertEq(nft.balanceOf(address(receiver)), 1);
    }

    function test_safeTransfer_threeArgOverloadUsesEmptyData() public {
        AcceptingReceiver receiver = new AcceptingReceiver();
        _mintBatchAs(alice, 1, 1000);
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(receiver), 1);
        assertEq(receiver.lastData(), "");
        assertEq(receiver.lastOperator(), alice);
    }

    function test_safeTransfer_revertsOnWrongMagic() public {
        WrongMagicReceiver receiver = new WrongMagicReceiver();
        _mintBatchAs(alice, 1, 1000);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.TransferToNonERC721Receiver.selector, address(receiver)));
        nft.safeTransferFrom(alice, address(receiver), 1);
        assertEq(nft.ownerOf(1), alice);
    }

    function test_safeTransfer_bubblesReceiverRevert() public {
        RevertingReceiver receiver = new RevertingReceiver();
        _mintBatchAs(alice, 1, 1000);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RevertingReceiver.Nope.selector, 1));
        nft.safeTransferFrom(alice, address(receiver), 1);
    }

    function test_safeTransfer_silentRevertBecomesNonReceiverError() public {
        SilentRevertReceiver receiver = new SilentRevertReceiver();
        _mintBatchAs(alice, 1, 1000);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.TransferToNonERC721Receiver.selector, address(receiver)));
        nft.safeTransferFrom(alice, address(receiver), 1);
    }

    function test_safeTransfer_revertsForContractWithoutHook() public {
        NoHookContract target = new NoHookContract();
        _mintBatchAs(alice, 1, 1000);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.TransferToNonERC721Receiver.selector, address(target)));
        nft.safeTransferFrom(alice, address(target), 1);
    }

    function test_safeTransfer_unauthorisedRevertsBeforeHook() public {
        AcceptingReceiver receiver = new AcceptingReceiver();
        _mintBatchAs(alice, 1, 1000);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BatchNFT.InsufficientApproval.selector, bob, 1));
        nft.safeTransferFrom(alice, address(receiver), 1);
        assertEq(receiver.calls(), 0);
    }

    // ------------------------------------------------------------------
    // Fuzz: single-batch ownership resolution
    // ------------------------------------------------------------------

    function testFuzz_ownerOfResolvesWholeBatch(uint8 qtySeed, uint8 pickSeed) public {
        uint256 qty = bound(uint256(qtySeed), 1, 20);
        uint256 pick = bound(uint256(pickSeed), 1, qty);
        _mintBatchAs(alice, qty, 1000);

        vm.prank(alice);
        nft.transferFrom(alice, bob, pick);

        for (uint256 id = 1; id <= qty; ++id) {
            assertEq(nft.ownerOf(id), id == pick ? bob : alice);
        }
        assertEq(nft.balanceOf(alice), qty - 1);
        assertEq(nft.balanceOf(bob), 1);
    }
}
