# BatchNFT

A gas-optimised ERC-721 with ERC721A-style batch minting (`src/BatchNFT.sol`), an OpenZeppelin
ERC721 baseline with identical mint rules (`src/BaselineNFT.sol`), unit tests for both, a gas
comparison, and a differential fuzz test that drives both contracts with the same call sequences
and requires identical `ownerOf`, `balanceOf` and success/revert behaviour.

Nothing here is deployed. There is no deploy script; see "Deployment parameters" below.

## Layout

| Path | Purpose |
| --- | --- |
| `src/BatchNFT.sol` | Batch-minting ERC-721 (the deliverable). |
| `src/BaselineNFT.sol` | OpenZeppelin `ERC721` with the same mint rules, one `_mint` per id. |
| `test/BatchNFT.t.sol` | Unit tests: mint rules, slot bookkeeping, approvals, safe transfers, failure paths. |
| `test/BaselineNFT.t.sol` | Unit tests for the baseline's mint rules. |
| `test/Differential.t.sol` | Differential fuzz: same fuzzed mint/transfer sequences on both contracts. |
| `test/Gas.t.sol` | Gas comparison (run with `-vv` to see the numbers). |
| `test/helpers/Receivers.sol` | `onERC721Received` mocks: accepting, wrong magic, reverting, silent revert, no hook. |
| `lib/openzeppelin-contracts` | Vendored subset of OpenZeppelin Contracts v5.1.0 (plain files, MIT). |
| `lib/forge-std` | Vendored forge-std v1.9.4 (plain files, MIT/Apache-2.0). |

Dependencies are committed as ordinary files, not git submodules, so the project builds offline.

## Building and testing

```
forge build
forge test
forge test --mc GasComparison -vv     # print gas numbers
forge fmt --check
```

`foundry.toml` pins `solc = "0.8.26"`, Cancun EVM, optimizer on with 200 runs. `ffi` is off and no
filesystem permissions are granted. Tests do not read or write environment variables and do not
depend on the caller of any script, so they pass in any order and in parallel.

## BatchNFT design

### Rules

- Token ids start at 1 and are sequential.
- `mint(uint256 quantity)` is public and free. `quantity` must be 1 to 20 inclusive, and
  `totalSupply() + quantity` may not exceed 10,000. The caller receives the tokens. No receiver
  callback runs on mint, even if the caller is a contract. One `Transfer(0, to, id)` is emitted per
  id.
- Full ERC-721: `approve`, `getApproved`, `setApprovalForAll`, `isApprovedForAll`,
  `transferFrom`, both `safeTransferFrom` overloads with the `onERC721Received` check, ERC-165 for
  ERC-165, ERC-721 and ERC-721 Metadata.
- No burn. No enumerable extension. `totalSupply()` is provided as a plain minted counter.
- `tokenURI(id)` returns the constructor's base string followed by the decimal id, and reverts for
  unminted ids.

### Storage model

`_packed[id]` is a single `uint256`: the owner in the low 160 bits and a `uint64` start timestamp
at bits 160 to 223. A slot of zero means "not written".

- **Mint** writes exactly one slot, at the first id of the batch, with the minter and
  `block.timestamp`. It increments the minter's balance once by `quantity`.
- **ownerOf(id)** reverts if `id` is 0 or has not been minted, then walks back from `id` to the
  nearest written slot. Because every batch writes its first slot and a batch is at most 20 ids
  long, the walk is at most 19 steps and never crosses into another batch.
- **Transfer** writes the moved token's slot with the new owner and the current timestamp. If
  `id + 1` has been minted and its slot is still zero, that slot is written with the previous slot
  data (previous owner and the batch's original start timestamp). The rest of the batch therefore
  keeps its owner. If `id + 1` is already written, or is not minted yet, nothing else changes, so a
  later batch's first slot is never overwritten.
- `balanceOf` is a plain per-address counter. `balanceOf(address(0))` reverts, matching
  OpenZeppelin.

Two extra views exist for testing and off-chain inspection: `ownershipOf(id)` returns the resolved
owner and start timestamp, and `rawOwnershipSlot(id)` returns the raw slot without walking.

### Behavioural parity with OpenZeppelin ERC721

The differential test requires the same call to succeed or revert on both contracts, so the
following OpenZeppelin choices are mirrored on purpose. Error selectors differ; only the
success/revert outcome is compared.

- `setApprovalForAll(address(0), ...)` reverts.
- `transferFrom` to the zero address reverts.
- `approve` may be called by the owner or by an operator approved for all; approving the owner
  itself is allowed.
- A per-token approval is cleared on transfer without an `Approval` event.
- `safeTransferFrom` to a contract reverts if the hook returns the wrong magic value or reverts
  with empty data. A hook revert with data is bubbled up unchanged.
- Self-transfers are allowed and emit `Transfer(owner, owner, id)`.

## Gas comparison

From `forge test --mc GasComparison -vv` with solc 0.8.26, optimizer 200 runs, after one warm-up
mint by another address. Both contracts pay for one `Transfer` event per id; the difference is one
`SSTORE` per batch instead of one per id.

| Operation | BatchNFT | Baseline (OZ) |
| --- | ---: | ---: |
| `mint(1)` (first mint by this address) | 78,094 | 78,617 |
| `mint(5)` | 64,378 | 156,769 |
| `mint(20)` | 93,943 | 530,839 |
| `transferFrom` first id of a 20-batch | 69,756 | 43,619 |
| `transferFrom` middle id of a 20-batch | 109,068 | 48,119 |
| `transferFrom` last id of a 20-batch | 91,208 | 48,119 |
| `transferFrom` a token whose slot is already written | 54,020 | 48,067 |
| `ownerOf` written slot / 19-step walk | 5,371 / 51,940 | 7,681 |

`mint(1)` in the table is more expensive than `mint(5)` only because it is the first mint by that
address and pays the zero-to-nonzero cost of the balance slot.

The trade-off is the standard ERC721A one: minting is far cheaper, but the first transfer out of a
batch pays the ownership walk plus a second `SSTORE` to back-fill the next id, and reads of ids
deep in an untouched batch are more expensive. Later transfers of the same token cost about the
same as the baseline.

## Assumptions

- Minting is unrestricted and free by specification. Anyone can mint the whole 10,000 supply, and
  there is no per-address cap, allowlist, pause, or owner role. This is intended for the exercise
  and is not a production mint policy.
- The base URI, name and symbol are constructor arguments and cannot be changed after deployment.
- `block.timestamp` is stored only as informational metadata (the ERC721A `startTimestamp`). No
  logic depends on it, so miner-controlled timestamps are not a security concern.
- The batch walk bound (19 steps) relies on `MAX_BATCH = 20` and on the absence of burn. Adding
  burn or raising the batch size requires revisiting `ownerOf` and the transfer back-fill.
- `safeTransferFrom` makes an external call to the receiver after all state changes, so reentrant
  calls see a consistent state; the differential test includes contract actors.

## Deployment parameters

No deployment is performed by this assignment. To deploy either contract, supply:

| Parameter | Type | Notes |
| --- | --- | --- |
| `name_` | `string` | Collection name, e.g. `"BatchNFT"`. |
| `symbol_` | `string` | Collection symbol, e.g. `"BNFT"`. |
| `baseTokenURI_` | `string` | Fixed prefix; `tokenURI(id)` = prefix + decimal id. Immutable after deploy. |

`MAX_SUPPLY = 10_000`, `MAX_BATCH = 20` and `START_TOKEN_ID = 1` are compile-time constants.
Target EVM is Cancun (`evm_version = "cancun"`); deploying to a chain without Cancun support
requires recompiling with an older EVM target.

## Operational responsibilities

- Whoever deploys is responsible for choosing the metadata base URI and hosting the metadata at
  `baseURI + id` for ids 1 to 10,000. There is no on-chain way to change it later.
- There are no administrative functions, no upgradeability and no funds held by the contracts.
- Marketplaces and indexers should read ownership through `ownerOf`, not from `Transfer` events
  alone: a mint emits one event per id, and every transfer emits one event, so event-based indexing
  is also correct, but raw storage reads of `_packed` are not.
- Passing tests are not a security audit. An independent adversarial review is recommended before
  any production use, particularly of the packed-slot transfer logic.

## Test summary

- Unit tests (`BatchNFTTest`, 45 tests): id numbering, one event per id, single slot per batch,
  batch boundaries against `MAX_SUPPLY`, invalid quantities, first/middle/last transfers with
  back-fill checks via `rawOwnershipSlot`, no overwrite of a following batch's slot, 19-step walk,
  timestamps, approvals and operators (grant, use, clear, revoke), every `safeTransferFrom` failure
  mode, ERC-165 and `tokenURI`.
- Baseline tests (`BaselineNFTTest`, 6 tests): the same mint rules on the OpenZeppelin contract.
- Differential (`DifferentialTest`, 3 tests): fuzzed sequences of up to 64 ops from a `uint256[]`,
  seeded sequences of up to 200 ops, and a scripted scenario that exercises every op kind. Ops cover
  mints of 0 to 21, transfers of the first, middle and last id of a batch, self-transfers,
  `approve` then transfer by the approvee (including approvals attempted by non-owners),
  `setApprovalForAll` then transfer by the operator, `safeTransferFrom` to EOAs and to accepting or
  rejecting receiver contracts, random transfers including nonexistent ids and the zero address,
  unauthorised transfers and operator revocation. After each sequence `ownerOf`, `getApproved`,
  `balanceOf`, `isApprovedForAll`, `totalSupply` and out-of-range reverts are compared.
- Gas (`GasComparisonTest`, 3 tests): logs the numbers above and asserts the direction of the
  mint saving.

A mutation check was run during development: replacing the transfer back-fill with a zero write
makes the differential fuzz fail immediately with a success/revert mismatch.
