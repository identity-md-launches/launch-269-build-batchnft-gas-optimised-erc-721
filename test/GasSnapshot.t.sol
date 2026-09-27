// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {BatchNFT} from "../src/BatchNFT.sol";
import {BaselineNFT} from "../src/BaselineNFT.sol";
import {AcceptingReceiver} from "./helpers/Receivers.sol";

/// @notice Shared fixture for the per-function gas snapshot tests. Every `test_gas_*` function
///         below makes exactly one call to the contract under test, so the `.gas-snapshot` line for
///         that test is the cost of that call plus a small, constant test-harness overhead.
///
///         State after setUp (identical for both contracts):
///           - bob owns id 1 (warm-up mint; bob's balance slot is non-zero)
///           - alice owns ids 2..21, minted as one 20-token batch, so on BatchNFT only slot 2 is written
///           - carol is approved for id 6; dave is an operator for all of alice's tokens
///           - `receiver` is a contract implementing onERC721Received
abstract contract GasFixture is Test {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal fresh = makeAddr("fresh");
    AcceptingReceiver internal receiver;

    uint256 internal constant FIRST = 2;
    uint256 internal constant MIDDLE = 11;
    uint256 internal constant LAST = 21;

    function _prepare(IERC721 nft, function(uint256) external mint) internal {
        receiver = new AcceptingReceiver();
        vm.warp(1_700_000_000);
        vm.prank(bob);
        mint(1);
        vm.startPrank(alice);
        mint(20);
        nft.approve(carol, 6);
        nft.setApprovalForAll(dave, true);
        vm.stopPrank();
    }
}

contract BatchNFTGasTest is GasFixture {
    BatchNFT internal nft;

    function setUp() public {
        nft = new BatchNFT("BatchNFT", "BNFT", "ipfs://batch/");
        _prepare(nft, nft.mint);
    }

    // --- constants ---------------------------------------------------------

    function test_gas_MAX_SUPPLY() public view {
        nft.MAX_SUPPLY();
    }

    function test_gas_MAX_BATCH() public view {
        nft.MAX_BATCH();
    }

    function test_gas_START_TOKEN_ID() public view {
        nft.START_TOKEN_ID();
    }

    // --- mint --------------------------------------------------------------

    function test_gas_mint_1() public {
        vm.prank(alice);
        nft.mint(1);
    }

    function test_gas_mint_5() public {
        vm.prank(alice);
        nft.mint(5);
    }

    function test_gas_mint_20() public {
        vm.prank(alice);
        nft.mint(20);
    }

    /// @dev First mint by an address: pays the zero-to-nonzero write of the balance slot.
    function test_gas_mint_1_coldBalance() public {
        vm.prank(fresh);
        nft.mint(1);
    }

    // --- views -------------------------------------------------------------

    function test_gas_totalSupply() public view {
        nft.totalSupply();
    }

    function test_gas_name() public view {
        nft.name();
    }

    function test_gas_symbol() public view {
        nft.symbol();
    }

    function test_gas_tokenURI() public view {
        nft.tokenURI(LAST);
    }

    function test_gas_balanceOf() public view {
        nft.balanceOf(alice);
    }

    /// @dev Slot written at mint: zero walk steps.
    function test_gas_ownerOf_firstOfBatch() public view {
        nft.ownerOf(FIRST);
    }

    /// @dev Last id of an untouched 20-token batch: 19 walk steps.
    function test_gas_ownerOf_lastOfBatch() public view {
        nft.ownerOf(LAST);
    }

    function test_gas_ownershipOf_lastOfBatch() public view {
        nft.ownershipOf(LAST);
    }

    function test_gas_rawOwnershipSlot() public view {
        nft.rawOwnershipSlot(LAST);
    }

    function test_gas_getApproved() public view {
        nft.getApproved(6);
    }

    function test_gas_isApprovedForAll() public view {
        nft.isApprovedForAll(alice, dave);
    }

    function test_gas_supportsInterface() public view {
        nft.supportsInterface(type(IERC721).interfaceId);
    }

    // --- approvals ---------------------------------------------------------

    /// @dev Approving the last id of the batch: pays the 19-step walk to resolve the owner.
    function test_gas_approve() public {
        vm.prank(alice);
        nft.approve(carol, LAST);
    }

    function test_gas_setApprovalForAll() public {
        vm.prank(alice);
        nft.setApprovalForAll(carol, true);
    }

    // --- transfers ---------------------------------------------------------

    function test_gas_transferFrom_firstOfBatch() public {
        vm.prank(alice);
        nft.transferFrom(alice, bob, FIRST);
    }

    function test_gas_transferFrom_middleOfBatch() public {
        vm.prank(alice);
        nft.transferFrom(alice, bob, MIDDLE);
    }

    function test_gas_transferFrom_lastOfBatch() public {
        vm.prank(alice);
        nft.transferFrom(alice, bob, LAST);
    }

    function test_gas_transferFrom_byApprovedAddress() public {
        vm.prank(carol);
        nft.transferFrom(alice, bob, 6);
    }

    function test_gas_transferFrom_byOperator() public {
        vm.prank(dave);
        nft.transferFrom(alice, bob, MIDDLE);
    }

    function test_gas_safeTransferFrom_toEOA() public {
        vm.prank(alice);
        nft.safeTransferFrom(alice, bob, MIDDLE);
    }

    function test_gas_safeTransferFrom_withData_toReceiver() public {
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(receiver), MIDDLE, hex"01");
    }
}

contract BaselineNFTGasTest is GasFixture {
    BaselineNFT internal nft;

    function setUp() public {
        nft = new BaselineNFT("BaselineNFT", "BASE", "ipfs://batch/");
        _prepare(nft, nft.mint);
    }

    // --- constants ---------------------------------------------------------

    function test_gas_MAX_SUPPLY() public view {
        nft.MAX_SUPPLY();
    }

    function test_gas_MAX_BATCH() public view {
        nft.MAX_BATCH();
    }

    function test_gas_START_TOKEN_ID() public view {
        nft.START_TOKEN_ID();
    }

    // --- mint --------------------------------------------------------------

    function test_gas_mint_1() public {
        vm.prank(alice);
        nft.mint(1);
    }

    function test_gas_mint_5() public {
        vm.prank(alice);
        nft.mint(5);
    }

    function test_gas_mint_20() public {
        vm.prank(alice);
        nft.mint(20);
    }

    function test_gas_mint_1_coldBalance() public {
        vm.prank(fresh);
        nft.mint(1);
    }

    // --- views -------------------------------------------------------------

    function test_gas_totalSupply() public view {
        nft.totalSupply();
    }

    function test_gas_name() public view {
        nft.name();
    }

    function test_gas_symbol() public view {
        nft.symbol();
    }

    function test_gas_tokenURI() public view {
        nft.tokenURI(LAST);
    }

    function test_gas_balanceOf() public view {
        nft.balanceOf(alice);
    }

    function test_gas_ownerOf_firstOfBatch() public view {
        nft.ownerOf(FIRST);
    }

    function test_gas_ownerOf_lastOfBatch() public view {
        nft.ownerOf(LAST);
    }

    function test_gas_getApproved() public view {
        nft.getApproved(6);
    }

    function test_gas_isApprovedForAll() public view {
        nft.isApprovedForAll(alice, dave);
    }

    function test_gas_supportsInterface() public view {
        nft.supportsInterface(type(IERC721).interfaceId);
    }

    // --- approvals ---------------------------------------------------------

    function test_gas_approve() public {
        vm.prank(alice);
        nft.approve(carol, LAST);
    }

    function test_gas_setApprovalForAll() public {
        vm.prank(alice);
        nft.setApprovalForAll(carol, true);
    }

    // --- transfers ---------------------------------------------------------

    function test_gas_transferFrom_firstOfBatch() public {
        vm.prank(alice);
        nft.transferFrom(alice, bob, FIRST);
    }

    function test_gas_transferFrom_middleOfBatch() public {
        vm.prank(alice);
        nft.transferFrom(alice, bob, MIDDLE);
    }

    function test_gas_transferFrom_lastOfBatch() public {
        vm.prank(alice);
        nft.transferFrom(alice, bob, LAST);
    }

    function test_gas_transferFrom_byApprovedAddress() public {
        vm.prank(carol);
        nft.transferFrom(alice, bob, 6);
    }

    function test_gas_transferFrom_byOperator() public {
        vm.prank(dave);
        nft.transferFrom(alice, bob, MIDDLE);
    }

    function test_gas_safeTransferFrom_toEOA() public {
        vm.prank(alice);
        nft.safeTransferFrom(alice, bob, MIDDLE);
    }

    function test_gas_safeTransferFrom_withData_toReceiver() public {
        vm.prank(alice);
        nft.safeTransferFrom(alice, address(receiver), MIDDLE, hex"01");
    }
}

/// @notice Isolated call-cost measurements for the scenarios in the assignment, taken with
///         `gasleft()` around a single external call and with the EVM state reverted between
///         scenarios so each one starts from the same fixture. These are the numbers quoted in
///         artifacts/gas.md next to the `.gas-snapshot` values. Run with
///         `forge test --mc GasReportLog -vv` to print them.
contract GasReportLogTest is Test {
    BatchNFT internal batch;
    BaselineNFT internal base;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant FIRST = 2;
    uint256 internal constant MIDDLE = 11;
    uint256 internal constant LAST = 21;

    function setUp() public {
        batch = new BatchNFT("BatchNFT", "BNFT", "ipfs://batch/");
        base = new BaselineNFT("BaselineNFT", "BASE", "ipfs://batch/");
        vm.warp(1_700_000_000);
        vm.startPrank(bob);
        batch.mint(1);
        base.mint(1);
        vm.stopPrank();
        vm.startPrank(alice);
        batch.mint(20); // ids 2..21
        base.mint(20);
        vm.stopPrank();
    }

    function _measureMint(uint256 qty) internal returns (uint256 gBatch, uint256 gBase) {
        uint256 snap = vm.snapshotState();
        vm.startPrank(alice);
        uint256 g0 = gasleft();
        batch.mint(qty);
        gBatch = g0 - gasleft();
        g0 = gasleft();
        base.mint(qty);
        gBase = g0 - gasleft();
        vm.stopPrank();
        vm.revertToState(snap);
    }

    function _measureTransfer(uint256 id) internal returns (uint256 gBatch, uint256 gBase) {
        uint256 snap = vm.snapshotState();
        vm.startPrank(alice);
        uint256 g0 = gasleft();
        batch.transferFrom(alice, bob, id);
        gBatch = g0 - gasleft();
        g0 = gasleft();
        base.transferFrom(alice, bob, id);
        gBase = g0 - gasleft();
        vm.stopPrank();
        vm.revertToState(snap);
    }

    function _measureOwnerOf(uint256 id) internal view returns (uint256 gBatch, uint256 gBase) {
        uint256 g0 = gasleft();
        batch.ownerOf(id);
        gBatch = g0 - gasleft();
        g0 = gasleft();
        base.ownerOf(id);
        gBase = g0 - gasleft();
    }

    function test_gasReport_mint() public {
        (uint256 m1b, uint256 m1o) = _measureMint(1);
        (uint256 m5b, uint256 m5o) = _measureMint(5);
        (uint256 m20b, uint256 m20o) = _measureMint(20);
        console2.log("mint(1)  warm balance     BatchNFT / Baseline:", m1b, m1o);
        console2.log("mint(5)                   BatchNFT / Baseline:", m5b, m5o);
        console2.log("mint(20)                  BatchNFT / Baseline:", m20b, m20o);
        // Direction of the trade-off: batch minting is cheaper.
        assertLt(m5b, m5o, "mint(5) should be cheaper on BatchNFT");
        assertLt(m20b, m20o, "mint(20) should be cheaper on BatchNFT");
    }

    function test_gasReport_transferFromPositionsInBatch() public {
        (uint256 tfb, uint256 tfo) = _measureTransfer(FIRST);
        (uint256 tmb, uint256 tmo) = _measureTransfer(MIDDLE);
        (uint256 tlb, uint256 tlo) = _measureTransfer(LAST);
        console2.log("transferFrom first of 20  BatchNFT / Baseline:", tfb, tfo);
        console2.log("transferFrom middle of 20 BatchNFT / Baseline:", tmb, tmo);
        console2.log("transferFrom last of 20   BatchNFT / Baseline:", tlb, tlo);
    }

    /// @dev Second transfer of a token whose slot is already written (no walk, no back-fill).
    function test_gasReport_transferFromSlotAlreadyWritten() public {
        vm.startPrank(alice);
        batch.transferFrom(alice, bob, MIDDLE);
        base.transferFrom(alice, bob, MIDDLE);
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 g0 = gasleft();
        batch.transferFrom(bob, alice, MIDDLE);
        uint256 tab = g0 - gasleft();
        g0 = gasleft();
        base.transferFrom(bob, alice, MIDDLE);
        uint256 tao = g0 - gasleft();
        vm.stopPrank();
        console2.log("transferFrom slot written BatchNFT / Baseline:", tab, tao);
    }

    function test_gasReport_ownerOf() public view {
        (uint256 ofb, uint256 ofo) = _measureOwnerOf(FIRST);
        (uint256 olb, uint256 olo) = _measureOwnerOf(LAST);
        console2.log("ownerOf first of 20       BatchNFT / Baseline:", ofb, ofo);
        console2.log("ownerOf last of 20        BatchNFT / Baseline:", olb, olo);
        assertGt(olb, ofb, "19-step walk should cost more than a written slot");
    }
}
