// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {BatchNFT} from "../src/BatchNFT.sol";
import {BaselineNFT} from "../src/BaselineNFT.sol";

/// @notice Gas comparison between BatchNFT and the OpenZeppelin baseline. Numbers are logged with
///         `forge test --mc GasComparison -vv`; the assertions only pin the direction of the
///         trade-off (batch mint cheaper, first-transfer-out-of-a-batch not cheaper).
contract GasComparisonTest is Test {
    BatchNFT internal batch;
    BaselineNFT internal base;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        batch = new BatchNFT("BatchNFT", "BNFT", "ipfs://batch/");
        base = new BaselineNFT("BaselineNFT", "BASE", "ipfs://batch/");
        // Warm both contracts so the first measured mint does not pay the one-time zero->nonzero
        // cost of the balance slot and the next-id slot.
        vm.startPrank(bob);
        batch.mint(1);
        base.mint(1);
        vm.stopPrank();
    }

    function _mintGas(uint256 qty) internal returns (uint256 gBatch, uint256 gBase) {
        vm.startPrank(alice);
        uint256 g0 = gasleft();
        batch.mint(qty);
        gBatch = g0 - gasleft();
        g0 = gasleft();
        base.mint(qty);
        gBase = g0 - gasleft();
        vm.stopPrank();
    }

    function test_gas_mint() public {
        (uint256 b1, uint256 o1) = _mintGas(1);
        (uint256 b5, uint256 o5) = _mintGas(5);
        (uint256 b20, uint256 o20) = _mintGas(20);

        console2.log("mint(1)   BatchNFT / Baseline:", b1, o1);
        console2.log("mint(5)   BatchNFT / Baseline:", b5, o5);
        console2.log("mint(20)  BatchNFT / Baseline:", b20, o20);

        assertLt(b5, o5, "mint(5) should be cheaper on BatchNFT");
        assertLt(b20, o20, "mint(20) should be cheaper on BatchNFT");
        // Batch mint grows roughly by one Transfer event per id, far below one SSTORE per id.
        assertLt(b20 - b1, (o20 - o1) / 4, "marginal cost per id should be much lower on BatchNFT");
    }

    function test_gas_transferPositionsInBatch() public {
        // Alice mints ids 2..21 on both.
        vm.startPrank(alice);
        batch.mint(20);
        base.mint(20);
        vm.stopPrank();

        uint256[3] memory ids = [uint256(2), 11, 21]; // first, middle, last of the batch
        string[3] memory labels = ["first ", "middle", "last  "];
        for (uint256 i = 0; i < ids.length; ++i) {
            vm.startPrank(alice);
            uint256 g0 = gasleft();
            batch.transferFrom(alice, bob, ids[i]);
            uint256 gBatch = g0 - gasleft();
            g0 = gasleft();
            base.transferFrom(alice, bob, ids[i]);
            uint256 gBase = g0 - gasleft();
            vm.stopPrank();
            console2.log(string.concat("transfer ", labels[i], " BatchNFT / Baseline:"), gBatch, gBase);
        }

        // Second transfer of a token whose slot is already written (no back-fill needed).
        vm.startPrank(bob);
        uint256 g1 = gasleft();
        batch.transferFrom(bob, alice, 11);
        uint256 gBatch2 = g1 - gasleft();
        g1 = gasleft();
        base.transferFrom(bob, alice, 11);
        uint256 gBase2 = g1 - gasleft();
        vm.stopPrank();
        console2.log("transfer again    BatchNFT / Baseline:", gBatch2, gBase2);
    }

    function test_gas_ownerOfWalk() public {
        vm.startPrank(alice);
        batch.mint(20);
        base.mint(20);
        vm.stopPrank();

        uint256 g0 = gasleft();
        batch.ownerOf(2); // written slot, zero steps
        uint256 gFirst = g0 - gasleft();
        g0 = gasleft();
        batch.ownerOf(21); // 19 steps back
        uint256 gLast = g0 - gasleft();
        g0 = gasleft();
        base.ownerOf(21);
        uint256 gBase = g0 - gasleft();
        console2.log("ownerOf first / last-of-20 / baseline:", gFirst, gLast, gBase);
        assertGt(gLast, gFirst);
    }
}
