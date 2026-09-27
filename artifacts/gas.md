# Gas and size report: BatchNFT vs BaselineNFT

Measured with forge 1.8.3, solc 0.8.26, Cancun EVM, optimizer on (200 runs), as pinned in
`foundry.toml`. Nothing was deployed. Commands used:

```
forge build --sizes                       # sizes table
forge snapshot                            # writes .gas-snapshot (per-test gas)
forge snapshot --check                    # passes on repeated full-suite runs
forge test --mc GasReportLog -vv          # isolated call costs quoted below
forge test --mc GasComparison -vv         # earlier contributor's sequential comparison
```

## 1. Deployed sizes

Runtime size is what the EVM stores after deployment. The limit (EIP-170) is 24,576 bytes.

| Contract | Runtime size (bytes) | Initcode size (bytes) | Margin to 24,576 | Role |
| --- | ---: | ---: | ---: | --- |
| BatchNFT | 4,284 | 5,012 | 20,292 | Deliverable |
| BaselineNFT | 4,173 | 4,907 | 20,403 | OpenZeppelin ERC721 baseline |
| AcceptingReceiver | 1,167 | 1,195 | 23,409 | Test helper (`test/helpers/Receivers.sol`) |
| WrongMagicReceiver | 335 | 363 | 24,241 | Test helper |
| RevertingReceiver | 362 | 390 | 24,214 | Test helper |
| SilentRevertReceiver | 318 | 346 | 24,258 | Test helper |
| NoHookContract | 121 | 147 | 24,455 | Test helper |

No contract exceeds 24,576 bytes. There is no size defect to report.

BatchNFT is 111 bytes larger than the baseline. The extra code is the ownership walk, the
back-fill branch in `_transfer`, the two inspection views (`ownershipOf`, `rawOwnershipSlot`)
and the hand-written `_toString`; OpenZeppelin's `Strings` and `ERC165` code is roughly the same
weight on the other side.

## 2. Gas per public function (`.gas-snapshot`)

Each line below is one test in `test/GasSnapshot.t.sol` that makes exactly one external call
from a fixture that is identical for both contracts (bob owns id 1; alice owns ids 2..21 minted as
a single 20-token batch; carol is approved for id 6; dave is an operator for alice). The number is
the test's gas as recorded by `forge snapshot`, so it includes a small constant test-harness
overhead (roughly 5,000 gas for a call preceded by `vm.prank`). Because the overhead is the same
on both sides, the difference column is exact.

| Function (scenario) | BatchNFT | BaselineNFT | BatchNFT minus baseline |
| --- | ---: | ---: | ---: |
| `MAX_SUPPLY()` | 5,535 | 5,535 | 0 |
| `MAX_BATCH()` | 5,492 | 5,492 | 0 |
| `START_TOKEN_ID()` | 5,471 | 5,449 | +22 |
| `mint(1)` (minter's balance slot already non-zero) | 66,256 | 66,812 | -556 |
| `mint(1)` (first mint by this address, cold balance slot) | 83,293 | 83,827 | -534 |
| `mint(5)` | 74,095 | 166,497 | -92,402 |
| `mint(20)` | 103,661 | 540,590 | -436,929 |
| `totalSupply()` | 7,519 | 7,644 | -125 |
| `name()` | 8,727 | 8,727 | 0 |
| `symbol()` | 8,838 | 8,727 | +111 |
| `tokenURI(21)` | 12,128 | 12,011 | +117 |
| `balanceOf(alice)` | 9,976 | 9,889 | +87 |
| `ownerOf(2)` (first id of batch, slot written, 0 walk steps) | 10,119 | 7,902 | +2,217 |
| `ownerOf(21)` (last id of batch, 19 walk steps) | 52,154 | 7,893 | +44,261 |
| `ownershipOf(21)` (BatchNFT only) | 52,365 | n/a | n/a |
| `rawOwnershipSlot(21)` (BatchNFT only) | 7,916 | n/a | n/a |
| `getApproved(6)` | 10,024 | 10,083 | -59 |
| `isApprovedForAll(alice, dave)` | 12,365 | 12,365 | 0 |
| `supportsInterface(IERC721)` | 5,764 | 5,748 | +16 |
| `approve(carol, 21)` (owner check walks 19 steps) | 105,029 | 61,009 | +44,020 |
| `setApprovalForAll(carol, true)` | 58,491 | 58,530 | -39 |
| `transferFrom` first id of batch (id 2) | 79,447 | 55,349 | +24,098 |
| `transferFrom` middle id of batch (id 11) | 116,483 | 55,337 | +61,146 |
| `transferFrom` last id of batch (id 21) | 118,584 | 55,283 | +63,301 |
| `transferFrom` by per-token approved address (id 6) | 107,907 | 57,857 | +50,050 |
| `transferFrom` by operator-for-all (id 11) | 120,826 | 59,588 | +61,238 |
| `safeTransferFrom(from,to,id)` to an EOA (id 11) | 119,302 | 58,221 | +61,081 |
| `safeTransferFrom(from,to,id,data)` to a receiver contract (id 11) | 249,572 | 188,493 | +61,079 |

## 3. The assignment's scenarios, measured as isolated calls

These are `gasleft()` deltas around a single external call, printed by `GasReportLogTest`
(`forge test --mc GasReportLog -vv`). Both contracts start from the same fixture and the EVM state
is reverted between scenarios, so every transfer is the first transfer out of an untouched
20-token batch. In this harness an empty state-changing external call measures about 26,200 gas
(cold account access plus forge's per-call accounting); that constant is included in every
non-view row below and cancels in the difference column.

| Scenario | BatchNFT | BaselineNFT | BatchNFT minus baseline | Ratio |
| --- | ---: | ---: | ---: | ---: |
| `mint(1)` | 60,994 | 61,529 | -535 | 0.99x |
| `mint(5)` | 68,878 | 161,281 | -92,403 | 0.43x |
| `mint(20)` | 98,443 | 535,351 | -436,908 | 0.18x |
| `transferFrom` first id of a 20-batch | 74,202 | 48,065 | +26,137 | 1.54x |
| `transferFrom` middle id (11) of a 20-batch | 111,228 | 48,065 | +63,163 | 2.31x |
| `transferFrom` last id (21) of a 20-batch | 113,294 | 48,065 | +65,229 | 2.36x |
| `transferFrom` a token whose slot is already written (second move) | 47,513 | 43,567 | +3,946 | 1.09x |
| `ownerOf` first id of a 20-batch (written slot) | 9,881 | 7,682 | +2,199 | 1.29x |
| `ownerOf` last id of a 20-batch (19-step walk) | 51,941 | 7,682 | +44,259 | 6.76x |

Marginal cost per additional minted id, from the mint rows: BatchNFT 1,971 gas (one `Transfer`
event, no storage), BaselineNFT 24,938 gas (one fresh `SSTORE` at 22,100 plus one event).

## 4. Where BatchNFT costs more than the baseline

Everything that resolves the owner of an id whose slot was never written pays one cold `SLOAD`
(2,100 gas) per walk step, plus one extra `SLOAD` of `_nextTokenId` for the existence check that
the baseline does not need.

1. **`ownerOf` on an unwritten id.** Cost grows linearly with the distance to the batch start:
   9,881 at 0 steps, 51,941 at 19 steps. The 19-step case is 6.8 times the baseline's 7,682.
   `ownershipOf` and `approve` inherit the same walk (`approve(carol, 21)` costs 105,029 against
   61,009). Even at 0 steps BatchNFT pays about 2,200 more, which is the `_nextTokenId` read.
2. **First transfer of any id out of a batch.** Three components add to the baseline's flat
   48,065:
   - the walk, 2,100 per step (0 steps for the first id, 9 for the middle, 19 for the last);
   - writing the moved token's slot as zero-to-nonzero (20,000) instead of nonzero-to-nonzero
     (2,900) whenever the id is not the batch start, an extra 17,100;
   - the back-fill write of `id + 1`, a fresh 22,100 `SSTORE`, whenever the next id exists and is
     unwritten. The last id of the last batch skips the write but still pays the 2,100 read.
   Observed: first +26,137, middle +63,163, last +65,229 (the last id trades the 22,100 back-fill
   for ten more walk steps).
3. **`safeTransferFrom` and operator transfers** carry the same premium as the underlying
   transfer position (about +61,000 for id 11 in every variant).
4. **Second and later transfers** of the same token cost 47,513 against 43,567 (+3,946): the
   `_nextTokenId` read, the read of `_packed[id + 1]` and the timestamp packing.
5. **Trivial constant deltas** of under 120 gas on `symbol`, `tokenURI`, `balanceOf`,
   `supportsInterface` and `START_TOKEN_ID` come from function-dispatch ordering, not logic.
6. **Runtime size** is 111 bytes larger (4,284 vs 4,173). Both are far below the limit.

## 5. Where BatchNFT costs less

`mint(quantity)` for quantity 2 and above: one `SSTORE` for the ownership slot and one for the
balance instead of one ownership `SSTORE` and one balance update per id. `mint(5)` saves 92,403
(57 percent) and `mint(20)` saves 436,908 (82 percent). `mint(1)` is a wash (-535). `totalSupply`,
`getApproved` and `setApprovalForAll` are within 130 gas of the baseline.

Break-even for a full 20-token batch: the 436,908 saved at mint covers about seven first
transfers. The premium per first transfer is 26,137 for the batch start and, for position k
steps from the start, roughly 26,137 + 17,100 + 2,100 x k (the last id skips the 22,100 back-fill);
summed over all 20 positions that is about 1,230,000, or 61,000 on average. If every token in a
batch is eventually transferred once, BatchNFT costs about 800,000 more than the baseline over the
batch's life; if most tokens stay with the minter, BatchNFT is far cheaper.

## 6. Notes on the measurement

- The baseline's cost is independent of the id's position in a batch (48,065 at every position;
  55,283 to 55,349 in the snapshot tests, the spread being the id's calldata zero bytes).
- Snapshot lines for the three fuzz tests (`testFuzz_*`) report mean and median gas over 256 runs
  with the seed fixed in `foundry.toml`. `forge snapshot --check` passes on repeated runs of the
  full suite. Running a filtered subset (for example `--mc DifferentialTest` alone) changes the
  fuzz input dictionary and therefore those three lines; check against the full suite.
- The earlier contributor's `GasComparisonTest` measures the three transfer positions
  sequentially on one batch, so its middle and last numbers (109,068 and 91,208) reflect shorter
  walks after earlier back-fills. Section 3 measures each position on an untouched batch instead.
- No defect was found in the implementation while measuring it. All 115 tests pass.
