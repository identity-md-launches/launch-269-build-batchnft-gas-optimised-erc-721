// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {BatchNFT} from "../src/BatchNFT.sol";
import {BaselineNFT} from "../src/BaselineNFT.sol";
import {AcceptingReceiver, WrongMagicReceiver} from "./helpers/Receivers.sol";

/// @notice Differential fuzz: the same sequence of calls is applied to BatchNFT and to the
///         OpenZeppelin baseline. Every call must succeed on both or revert on both, and at the
///         end `ownerOf` and `balanceOf` must agree for every id and every actor.
contract DifferentialTest is Test {
    uint256 internal constant MAX_OPS = 64;
    uint256 internal constant OP_KINDS = 12;

    BatchNFT internal batch;
    BaselineNFT internal base;

    struct Batch {
        uint256 start;
        uint256 qty;
    }

    address[] internal actors;
    Batch[] internal batches;
    uint256 internal minted;
    uint256 internal opsApplied;
    uint256 internal opsSucceeded;

    function setUp() public {
        batch = new BatchNFT("BatchNFT", "BNFT", "ipfs://batch/");
        base = new BaselineNFT("BaselineNFT", "BASE", "ipfs://batch/");

        actors.push(makeAddr("actor0"));
        actors.push(makeAddr("actor1"));
        actors.push(makeAddr("actor2"));
        actors.push(makeAddr("actor3"));
        actors.push(makeAddr("actor4"));
        actors.push(address(new AcceptingReceiver()));
        actors.push(address(new WrongMagicReceiver()));

        vm.warp(1_700_000_000);
    }

    // ------------------------------------------------------------------
    // Entry points
    // ------------------------------------------------------------------

    /// @dev Fully fuzzed sequence of up to MAX_OPS operations.
    function testFuzz_differential(uint256[] memory seeds) public {
        uint256 n = seeds.length < MAX_OPS ? seeds.length : MAX_OPS;
        for (uint256 i = 0; i < n; ++i) {
            _step(seeds[i]);
        }
        _assertEquivalent();
    }

    /// @dev Longer sequences derived from a single seed, so the fuzzer reaches deep states cheaply.
    function testFuzz_differentialLongSequence(uint256 seed, uint8 lengthSeed) public {
        uint256 n = bound(uint256(lengthSeed), 1, 200);
        for (uint256 i = 0; i < n; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            _step(seed);
        }
        _assertEquivalent();
    }

    /// @dev Deterministic scenario touching every operation kind, so a broken op is caught even if
    ///      the fuzzer happens not to sample it.
    function test_differential_scriptedScenario() public {
        for (uint256 kind = 0; kind < OP_KINDS; ++kind) {
            for (uint256 r = 0; r < 6; ++r) {
                uint256 entropy = uint256(keccak256(abi.encode("scripted", kind, r))) / OP_KINDS;
                _step(entropy * OP_KINDS + kind);
            }
        }
        assertGt(opsSucceeded, 0);
        _assertEquivalent();
    }

    // ------------------------------------------------------------------
    // Operation dispatcher
    // ------------------------------------------------------------------

    function _step(uint256 seed) internal {
        uint256 kind = seed % OP_KINDS;
        seed /= OP_KINDS;

        if (kind == 0 || kind == 1) {
            _opMint(seed);
        } else if (kind == 2) {
            _opTransferBatchPosition(seed, 0);
        } else if (kind == 3) {
            _opTransferBatchPosition(seed, 1);
        } else if (kind == 4) {
            _opTransferBatchPosition(seed, 2);
        } else if (kind == 5) {
            _opSelfTransfer(seed);
        } else if (kind == 6) {
            _opApproveThenTransfer(seed);
        } else if (kind == 7) {
            _opApproveForAllThenTransfer(seed);
        } else if (kind == 8) {
            _opSafeTransfer(seed);
        } else if (kind == 9) {
            _opRandomTransfer(seed);
        } else if (kind == 10) {
            _opUnauthorisedTransfer(seed);
        } else {
            _opRevokeOperator(seed);
        }
    }

    function _opMint(uint256 seed) internal {
        address who = _actor(seed);
        seed >>= 8;
        // 0..21 so invalid quantities are exercised too.
        uint256 qty = seed % 22;
        seed >>= 8;
        if (seed % 4 == 0) vm.warp(block.timestamp + 1 + (seed % 1000));

        bool ok = _both(who, abi.encodeWithSelector(BatchNFT.mint.selector, qty));
        if (ok) {
            batches.push(Batch({start: minted + 1, qty: qty}));
            minted += qty;
        }
    }

    /// @param position 0 = first id of a batch, 1 = middle, 2 = last.
    function _opTransferBatchPosition(uint256 seed, uint256 position) internal {
        if (batches.length == 0) return;
        Batch memory b = batches[seed % batches.length];
        seed >>= 16;
        uint256 id;
        if (position == 0) id = b.start;
        else if (position == 2) id = b.start + b.qty - 1;
        else id = b.start + b.qty / 2;

        address from = base.ownerOf(id);
        address to = _actor(seed);
        _both(from, abi.encodeWithSelector(IERC721.transferFrom.selector, from, to, id));
    }

    function _opSelfTransfer(uint256 seed) internal {
        if (minted == 0) return;
        uint256 id = 1 + (seed % minted);
        address owner = base.ownerOf(id);
        _both(owner, abi.encodeWithSelector(IERC721.transferFrom.selector, owner, owner, id));
    }

    function _opApproveThenTransfer(uint256 seed) internal {
        if (minted == 0) return;
        uint256 id = 1 + (seed % minted);
        seed >>= 16;
        address owner = base.ownerOf(id);
        address spender = _actor(seed);
        seed >>= 8;
        address to = _actor(seed);
        seed >>= 8;

        // Sometimes the approve call comes from someone who is not the owner (should revert on both).
        address approver = seed % 5 == 0 ? _actor(seed >> 8) : owner;
        _both(approver, abi.encodeWithSelector(IERC721.approve.selector, spender, id));
        _both(spender, abi.encodeWithSelector(IERC721.transferFrom.selector, owner, to, id));
    }

    function _opApproveForAllThenTransfer(uint256 seed) internal {
        if (minted == 0) return;
        address owner = _actor(seed);
        seed >>= 8;
        address op = _actor(seed);
        seed >>= 8;
        _both(owner, abi.encodeWithSelector(IERC721.setApprovalForAll.selector, op, true));

        uint256 id = 1 + (seed % minted);
        seed >>= 16;
        address to = _actor(seed);
        // `owner` may or may not actually own `id`; both contracts must agree.
        _both(op, abi.encodeWithSelector(IERC721.transferFrom.selector, owner, to, id));
    }

    function _opSafeTransfer(uint256 seed) internal {
        if (minted == 0) return;
        uint256 id = 1 + (seed % minted);
        seed >>= 16;
        address owner = base.ownerOf(id);
        address to = _actor(seed);
        seed >>= 8;
        bytes memory data = seed % 2 == 0 ? bytes("") : abi.encodePacked(seed);
        if (seed % 3 == 0) {
            _both(owner, abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", owner, to, id));
        } else {
            _both(
                owner, abi.encodeWithSignature("safeTransferFrom(address,address,uint256,bytes)", owner, to, id, data)
            );
        }
    }

    /// @dev Random (caller, from, to, id) including nonexistent ids and the zero address.
    function _opRandomTransfer(uint256 seed) internal {
        uint256 id = seed % (minted + 3); // 0 and minted+1, minted+2 do not exist
        seed >>= 16;
        address caller = _actor(seed);
        seed >>= 8;
        address from = _actor(seed);
        seed >>= 8;
        address to = seed % 7 == 0 ? address(0) : _actor(seed);
        _both(caller, abi.encodeWithSelector(IERC721.transferFrom.selector, from, to, id));
    }

    function _opUnauthorisedTransfer(uint256 seed) internal {
        if (minted == 0) return;
        uint256 id = 1 + (seed % minted);
        seed >>= 16;
        address owner = base.ownerOf(id);
        address caller = _actor(seed);
        seed >>= 8;
        address to = _actor(seed);
        _both(caller, abi.encodeWithSelector(IERC721.transferFrom.selector, owner, to, id));
    }

    function _opRevokeOperator(uint256 seed) internal {
        address owner = _actor(seed);
        seed >>= 8;
        address op = seed % 9 == 0 ? address(0) : _actor(seed);
        _both(owner, abi.encodeWithSelector(IERC721.setApprovalForAll.selector, op, false));
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Applies the same call to both contracts from the same caller and asserts they agree on
    ///      success vs revert. Returns whether the call succeeded.
    function _both(address caller, bytes memory data) internal returns (bool) {
        vm.prank(caller);
        (bool okBatch,) = address(batch).call(data);
        vm.prank(caller);
        (bool okBase,) = address(base).call(data);
        assertEq(okBatch, okBase, "success/revert mismatch");
        opsApplied += 1;
        if (okBatch) opsSucceeded += 1;
        return okBatch;
    }

    function _assertEquivalent() internal view {
        assertEq(batch.totalSupply(), base.totalSupply(), "totalSupply");
        assertEq(batch.totalSupply(), minted, "tracked minted");

        // Every minted id resolves to the same owner and the same tokenURI.
        for (uint256 id = 1; id <= minted; ++id) {
            assertEq(batch.ownerOf(id), base.ownerOf(id), "ownerOf");
            assertEq(batch.getApproved(id), base.getApproved(id), "getApproved");
        }
        if (minted > 0) {
            assertEq(batch.tokenURI(minted), base.tokenURI(minted), "tokenURI");
        }

        // Ids outside the minted range revert on both.
        _assertBothRevertOwnerOf(0);
        _assertBothRevertOwnerOf(minted + 1);
        _assertBothRevertOwnerOf(minted + 25);

        // Balances agree for every actor and sum to the minted count.
        uint256 sum;
        for (uint256 i = 0; i < actors.length; ++i) {
            uint256 bal = batch.balanceOf(actors[i]);
            assertEq(bal, base.balanceOf(actors[i]), "balanceOf");
            sum += bal;
            for (uint256 j = 0; j < actors.length; ++j) {
                assertEq(
                    batch.isApprovedForAll(actors[i], actors[j]),
                    base.isApprovedForAll(actors[i], actors[j]),
                    "isApprovedForAll"
                );
            }
        }
        assertEq(sum, minted, "balances sum to minted");
    }

    function _assertBothRevertOwnerOf(uint256 id) internal view {
        (bool okBatch,) = address(batch).staticcall(abi.encodeWithSelector(IERC721.ownerOf.selector, id));
        (bool okBase,) = address(base).staticcall(abi.encodeWithSelector(IERC721.ownerOf.selector, id));
        assertFalse(okBatch, "batch ownerOf should revert");
        assertFalse(okBase, "base ownerOf should revert");
    }
}
