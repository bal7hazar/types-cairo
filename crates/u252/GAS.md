# u252 gas budgets

Every test of the package, benchmarks included, is a snforge test carrying
`#[available_gas(l2_gas: N)]`: CI fails when a change makes it more expensive than its budget.

Measured on 2026-09-28 at commit `604b376` with scarb 2.19.4 and snforge 0.61.0 (Sierra gas;
with Sierra >= 1.7 snforge reports `l2_gas` = Sierra gas, builtins included). The column
"origami_hexmap 1.8.0" is the same test measured the same day in `dojoengine/origami` at commit `04ab30c` (workspace version 1.8.0),
where the code was extracted from: every figure is identical, the extraction costs nothing.

## How to record a budget

1. Run `snforge test` in `crates/u252` and read `l2_gas`.
2. Measure **with a budget already set** (a loose one for a new test): adding the attribute
   changes the measured gas of a test, its value does not.
3. Set the budget to `N = ceil(1.05 * measured)` and update the row of the test below.
4. Raising a budget needs a reason written in the pull request. Lowering one needs nothing; a
   change that makes a test more than 5 % cheaper must lower its budget.

The unit tests of `origami_hexmap` carried no budget: their reference figures were measured on a
copy of the source with a loose budget added (rule 2), nothing else changed.

Microbenchmarks repeat the operation 100 times in a loop. Per-operation cost =
`(test - baseline) / 100`, the baseline being the test that builds the same operands. Every loop
iteration itself costs 1_270.

## Representation

`u252` is `struct { value: felt252 }` with the value set `[0, P - 1]`
(`P = 2^251 + 17 * 2^192 + 1`): every felt is a valid `u252`, so `Into<felt252, u252>`,
`Into<u252, felt252>`, `Serde` and `StorePacking<u252, felt252>` are identities with no check and
no invariant to re-establish. The checked operations panic exactly when the true integer result
leaves `[0, P - 1]` (property tests against `u256` on the edges 0, 1, 2^128 - 1, 2^128, 2^251,
P - 1, P - 2 and 36 pseudo-random wide and narrow values, all pairs).

Candidates refused or not viable (scarb 2.19.4):

| Candidate | Result |
|---|---|
| `BoundedInt<0, 2^252 - 1>` or any `MAX >= P` | Refused: `E2008 The value does not fit within the range of type core::felt252` (2^252 - 1 > P). A felt cannot hold 2^252 - 1 either. |
| `BoundedInt<0, 2^251 - 1>` + `AddHelper` (result `<0, 2^252 - 2>`) | Refused: `E2008` (result max > P). |
| `SubHelper` on it (result `<-(2^251 - 1), 2^251 - 1>`) | Compiler panic: `Could not specialize type BoundedInt<-..., ...>` (range size >= P). |
| `bounded_int_div_rem<BoundedInt<0, 2^251 - 1>, BoundedInt<1, 255>>` | Refused: `Could not specialize libfunc bounded_int_div_rem ... unsupported` (quotient must be < 2^128). |
| `bounded_int_constrain` at 2^128 | Refused: both halves must span at most 2^128 values. |
| `downcast<felt252, BoundedInt<0, 2^251 - 1>>` | Refused: `downcast` only targets ranges of at most 2^128 values. |
| `BoundedInt<0, P - 1>` | Type accepted; `upcast` to `felt252` is free (identity), but `upcast<felt252, _>` is refused (the felt252 range is `(-P, P)`) and `downcast` too: it cannot be built from a felt, so it cannot carry the infallible `Into`. |
| `bounded_int_is_zero` | Usable only in corelib: its result type `IsZeroResult` is not visible outside. |
| Bitwise on a 252-bit word | No libfunc: `bitwise` exists only for `u8..u128`. |

Why the checks need two splits: the only sound range proof on a full-range felt is the
`felt252 -> u256` split (`u128s_from_felt252`: 1 range check below 2^128, 3 above, measured 820 and
1_611 per op). For `[0, P - 1]`, `a + b` and `a + b - P` are the same field element, so the sum
alone cannot reveal the overflow; with the split of one operand it can (`a + b` wraps iff the
field sum is below `a`). The same holds for `[0, 2^251 - 1]` (`2 * MAX > P`), which in addition
pays a split on every `TryInto<felt252>` (2_281).

## Benchmarks

Source: `src/tests/bench_u252.cairo`, losing variants included.

| Operation | Test | origami_hexmap 1.8.0 | Measured | Budget | Per op |
|---|---|---:|---:|---:|---:|
| _Baselines_ | | | | | |
| Loop only | `bench_u252_baseline_loop` | 141_990 | 141_990 | 149_090 |  |
| Two wide felts `fa(n)`, `fb(n)` | `bench_u252_baseline_felt` | 211_290 | 211_290 | 221_855 |  |
| One wide felt `fc(n)` | `bench_u252_baseline_shift` | 171_690 | 171_690 | 180_275 |  |
| One narrow felt | `bench_u252_baseline_narrow` | 161_790 | 161_790 | 169_880 |  |
| Two `u256` (both limbs vary) | `bench_u252_baseline_u256` | 338_010 | 338_010 | 354_911 |  |
| One `u256` | `bench_u252_baseline_shift_u256` | 235_050 | 235_050 | 246_803 |  |
| Two `u128` | `bench_u252_baseline_u128` | 244_950 | 244_950 | 257_198 |  |
| One `u128` | `bench_u252_baseline_u128_one` | 188_520 | 188_520 | 197_946 |  |
| _Checked add_ | | | | | |
| `u256 +` | `bench_u252_add_u256` | 523_140 | 523_140 | 549_297 | 1_851 |
| `u128 +` | `bench_u252_add_u128` | 271_680 | 271_680 | 285_264 | 267 |
| `felt252 +` (unchecked) | `bench_u252_add_felt` | 211_290 | 211_290 | 221_855 | 0 |
| **`u252 +`: `split(a + b) >= split(a)` (winner)** | `bench_u252_add` | 633_490 | 633_490 | 665_165 | 4_222 |
| `u252 +`, narrow operands | `bench_u252_add_narrow` | 460_490 | 460_490 | 483_515 | 2_987 |
| `u252 +` via `split(a) + split(b) < P` (loser) | `bench_u252_add_via_sum` | 848_490 | 848_490 | 890_915 | 6_372 |
| `[0, 2^251 - 1]` add (two splits, high limb < 2^123) | `bench_u251_add` | 818_490 | 818_490 | 859_415 | 6_072 |
| _Checked sub_ | | | | | |
| `u256 -` | `bench_u252_sub_u256` | 531_060 | 531_060 | 557_613 | 1_930 |
| `u128 -` | `bench_u252_sub_u128` | 271_680 | 271_680 | 285_264 | 267 |
| **`u252 -`: `split(a - b) <= split(a)` (winner)** | `bench_u252_sub` | 633_490 | 633_490 | 665_165 | 4_222 |
| `u252 -` via `split(a) >= split(b)` (loser) | `bench_u252_sub_via_operands` | 653_490 | 653_490 | 686_165 | 4_422 |
| `[0, 2^251 - 1]` sub | `bench_u251_sub` | 653_490 | 653_490 | 686_165 | 4_422 |
| _Wrapping add and sub_ | | | | | |
| `u256` `wrapping_add` | `bench_u252_wrapping_add_u256` | 503_340 | 503_340 | 528_507 | 1_653 |
| `u128` `wrapping_add` | `bench_u252_wrapping_add_u128` | 322_170 | 322_170 | 338_279 | 772 |
| **`u252` `wrapping_add` (mod P, field add)** | `bench_u252_wrapping_add` | 211_290 | 211_290 | 221_855 | 0 |
| **`u252` `wrapping_sub` (mod P, field sub)** | `bench_u252_wrapping_sub` | 211_290 | 211_290 | 221_855 | 0 |
| _Left shift by 17 (checked)_ | | | | | |
| `u256 * 2^17` | `bench_u252_shl_u256` | 1_631_300 | 1_631_300 | 1_712_865 | 13_962 |
| `felt252 * 2^17` (`Bits::shl`, unchecked) | `bench_u252_shl_felt` | 318_690 | 318_690 | 334_625 | 1_470 |
| **`u252::shl`: low bits of the canonical product (winner)** | `bench_u252_shl` | 689_010 | 689_010 | 723_461 | 5_173 |
| `u252::shl` by 145 (high-limb branch), narrow operand | `bench_u252_shl_high` | 719_010 | 719_010 | 754_961 | 5_572 |
| `u252::shl`, low limb times `2^-k` cast to `u128` (loser) | `bench_u252_shl_inv_cast` | 729_490 | 729_490 | 765_965 | 5_578 |
| `u252::shl`, mask split to `u256` + two-limb AND (loser) | `bench_u252_shl_mask_u256` | 872_510 | 872_510 | 916_136 | 7_008 |
| `u252::shl` via `u256` overflowing product (loser) | `bench_u252_shl_via_u256` | 2_067_490 | 2_067_490 | 2_170_865 | 18_958 |
| _Right shift by 17 (the exact tests include one felt mul, 98)_ | | | | | |
| `u256 / 2^17` (floor) | `bench_u252_shr_u256` | 870_050 | 870_050 | 913_553 | 6_350 |
| `felt252 * 2^-17` (`Bits::shr_exact`, unchecked) | `bench_u252_shr_exact_felt` | 328_590 | 328_590 | 345_020 | 1_569 |
| **`u252::shr_exact`: low limb times `2^-k` cast to `u128` (winner)** | `bench_u252_shr_exact` | 602_490 | 602_490 | 632_615 | 4_308 |
| `u252::shr_exact`, mask cast + limb AND (loser) | `bench_u252_shr_exact_and` | 836_010 | 836_010 | 877_811 | 6_643 |
| **`u252::shr` (floor): dropped bits by limb AND, exact field division** | `bench_u252_shr` | 826_010 | 826_010 | 867_311 | 6_543 |
| _DivRem by 7_ | | | | | |
| `u256` DivRem | `bench_u252_divrem_u256` | 879_950 | 879_950 | 923_948 | 6_449 |
| `u128` DivRem | `bench_u252_divrem_u128` | 344_940 | 344_940 | 362_187 | 1_564 |
| **`u252::div_rem`: split + `u256` DivRem (winner)** | `bench_u252_divrem` | 1_038_490 | 1_038_490 | 1_090_415 | 8_668 |
| `u252::div_rem`: 4 `u128` DivRem + `felt252_div` (loser) | `bench_u252_divrem_felt` | 1_287_490 | 1_287_490 | 1_351_865 | 11_158 |
| _Checked mul (wide x small)_ | | | | | |
| `u256 *` | `bench_u252_mul_u256` | 1_738_220 | 1_738_220 | 1_825_131 | 14_002 |
| `felt252 *` (unchecked) | `bench_u252_mul_felt` | 238_020 | 238_020 | 249_921 | 267 |
| **`u252 *`: two `u128` wide products (winner)** | `bench_u252_mul` | 1_302_490 | 1_302_490 | 1_367_615 | 10_912 |
| `u252 *`, narrow x narrow | `bench_u252_mul_narrow` | 1_156_490 | 1_156_490 | 1_214_315 | 9_947 |
| `u252 *` via `u256` overflowing product (loser) | `bench_u252_mul_u256_product` | 1_986_020 | 1_986_020 | 2_085_321 | 17_747 |
| _Comparisons_ | | | | | |
| `u256 ==` | `bench_u252_eq_u256` | 420_180 | 420_180 | 441_189 | 822 |
| `felt252 ==` | `bench_u252_eq_felt` | 240_990 | 240_990 | 253_040 | 297 |
| **`u252 ==`** | `bench_u252_eq` | 240_990 | 240_990 | 253_040 | 297 |
| `u256 <` | `bench_u252_lt_u256` | 427_110 | 427_110 | 448_466 | 891 |
| `u128 <` | `bench_u252_lt_u128` | 321_180 | 321_180 | 337_239 | 762 |
| **`u252 <`: two splits + `u256 <` (winner)** | `bench_u252_lt` | 644_490 | 644_490 | 676_715 | 4_332 |
| `u252 <`, narrow operands | `bench_u252_lt_narrow` | 520_400 | 520_400 | 546_420 | 3_586 |
| `u252 <`, limbs compared by hand (loser) | `bench_u252_lt_manual` | 661_490 | 661_490 | 694_565 | 4_502 |
| `[0, 2^251 - 1]` `<` | `bench_u251_lt` | 644_490 | 644_490 | 676_715 | 4_332 |
| **`u252 <=`** | `bench_u252_le` | 664_490 | 664_490 | 697_715 | 4_532 |
| `felt252 == 0` | `bench_u252_is_zero_felt` | 201_390 | 201_390 | 211_460 | 297 |
| **`u252::is_zero`** | `bench_u252_is_zero` | 201_390 | 201_390 | 211_460 | 297 |
| _Bitwise_ | | | | | |
| `u128 &` | `bench_u252_and_u128` | 394_850 | 394_850 | 414_593 | 1_499 |
| `u256 &` | `bench_u252_and_u256` | 576_610 | 576_610 | 605_441 | 2_386 |
| `u256 \|` | `bench_u252_or_u256` | 576_610 | 576_610 | 605_441 | 2_386 |
| `u256 ^` | `bench_u252_xor_u256` | 576_610 | 576_610 | 605_441 | 2_386 |
| **`u252 &`** (two splits, join) | `bench_u252_and` | 821_690 | 821_690 | 862_775 | 6_104 |
| **`u252 \|`** (two splits, `< P` check, join) | `bench_u252_or` | 911_510 | 911_510 | 957_086 | 7_002 |
| **`u252 ^`** (two splits, `< P` check, join) | `bench_u252_xor` | 911_510 | 911_510 | 957_086 | 7_002 |
| Bit test, `u256` (`Bits::get`) | `bench_u252_bit_test_u256` | 776_540 | 776_540 | 815_367 | 5_415 |
| **Bit test, `u252::bit`** (split + `Bits::get`) | `bench_u252_bit_test` | 884_080 | 884_080 | 928_284 | 7_124 |
| Bit set known unset, felt `+ 2^i` (`Bits::set`) | `bench_u252_bit_set_felt` | 421_650 | 421_650 | 442_733 | 2_500 |
| **Bit set, `u252::set_bit`** (split, limb test, `< P` check) | `bench_u252_bit_set` | 929_060 | 929_060 | 975_513 | 7_574 |
| _Conversions, Serde, storage_ | | | | | |
| **`felt252 -> u252` and back (`Into`, both ways)** | `bench_u252_from_felt` | 171_690 | 171_690 | 180_275 | 0 |
| `u252 -> u256` (`Into`), wide | `bench_u252_to_u256` | 332_790 | 332_790 | 349_430 | 1_611 |
| `u252 -> u256` (`Into`), narrow | `bench_u252_to_u256_narrow` | 243_740 | 243_740 | 255_927 | 820 |
| `u256 -> u252` (`TryInto`, `< P`) | `bench_u252_from_u256` | 340_980 | 340_980 | 358_029 | 1_059 |
| `u128 -> u252` (`Into`) | `bench_u252_from_u128` | 188_520 | 188_520 | 197_946 | 0 |
| `u252 -> u128` (`TryInto`) | `bench_u252_to_u128` | 188_890 | 188_890 | 198_335 | 271 |
| `u8 -> u252` (`Into`, the test adds 1) | `bench_u252_from_u8` | 151_890 | 151_890 | 159_485 | 99 |
| `u252 -> u8` (`TryInto`, the test adds 1) | `bench_u252_to_u8` | 205_350 | 205_350 | 215_618 | 634 |
| `felt252 -> [0, 2^251 - 1]` (`TryInto`: split + high < 2^123) | `bench_u251_from_felt` | 399_790 | 399_790 | 419_780 | 2_281 |
| `u256` Serde round trip | `bench_u252_serde_u256` | 439_050 | 439_050 | 461_003 | 2_040 |
| **`u252` Serde round trip (no range check)** | `bench_u252_serde` | 231_790 | 231_790 | 243_380 | 601 |
| **`u252` `StorePacking` round trip** | `bench_u252_store_packing` | 171_690 | 171_690 | 180_275 | 0 |

The five benchmarks of `Layout::expand` and of the BFS layer step on a 17x14 board
(`bench_u252_expand_u256`, `bench_u252_expand`, `bench_u252_step_u256`, `bench_u252_step`,
`bench_u252_step_fused`) stay in `origami_hexmap`: they measure its board layout, which is not
part of this package. Their figures in `origami_hexmap` 1.8.0: `expand` on `u252` 21.0k against
19.4k on `u256` (+9 %), the BFS layer 22.6k against 21.0k (+8 %), 21.5k when fused.

## Verdict


* **Where `u252` removes the `u256` overhead**: everything that stays a field operation.
  `Into` both ways, `StorePacking` and `wrapping_add`/`wrapping_sub` (modulo P) cost 0 (`u256`:
  1.6k for a wrapping add); `==` and `is_zero` 0.3k (`u256 ==`: 0.8k); `Serde` 0.6k (`u256`:
  2.0k); unchecked shifts stay felt products (1.5k with the table lookup, `u256 * 2^17`: 14.0k).
  Checked left shift 5.2k and checked mul 10.9k beat `u256` (14.0k both); checked exact right shift
  4.3k beats the `u256` division (6.4k).
* **Where it cannot**: every operation that needs the integer order or the bits pays one
  `felt252 -> u256` split per operand (0.8k narrow, 1.6k wide). Checked add/sub 4.2k vs 1.9k,
  `<` 4.3k vs 0.9k, `&` 6.1k and `|`/`^` 7.0k vs 2.4k, bit test 7.1k vs 5.4k, DivRem 8.7k vs 6.4k,
  floor right shift 6.5k vs 6.4k. No libfunc offers a cheaper range proof or a wider bitwise.
* **Cost of the infallible `Into`**: nothing for the conversions themselves; compared with a
  `[0, 2^251 - 1]` type the checked add is even cheaper (4.2k vs 6.1k: the overflow test is one
  comparison with an operand, instead of a sum of two splits), sub and `<` are equal, and the
  2^251 type pays 2.3k on every `TryInto<felt252>` and `Serde` read.
* **Bitmaps**: keep `u256` (or felt bitmaps with felt shifts) for the set algebra; a `u252`
  operand adds a split and a join around every set operation (see the figures of
  `origami_hexmap` above). `u252` is worth using for counters, storage and APIs that convert to
  and from `felt252`.

## Unit tests

Sources: `src/integer.cairo`, `src/bits.cairo` (inline tests) and `tests/readme.cairo`.

| Test | origami_hexmap 1.8.0 | Measured | Budget |
|---|---:|---:|---:|
| `test_bits_get_set_unset` | 5_079_149 | 5_079_149 | 5_333_107 |
| `test_bits_inv` | 1_051_210 | 1_051_210 | 1_103_771 |
| `test_bits_pow` | 19_450 | 19_450 | 20_423 |
| `test_bits_shifts` | 20_620 | 20_620 | 21_651 |
| `test_bits_to_felt` | 16_850 | 16_850 | 17_693 |
| `test_readme_add_overflow` | new | 19_140 | 20_097 |
| `test_readme_bits` | new | 27_633 | 29_015 |
| `test_readme_usage` | new | 56_905 | 59_751 |
| `test_u252_add_overflow` | 19_140 | 19_140 | 20_097 |
| `test_u252_add_overflow_wide` | 19_930 | 19_930 | 20_927 |
| `test_u252_arithmetic_against_u256` | 363_394_130 | 363_394_130 | 381_563_837 |
| `test_u252_constants_and_conversions` | 16_550 | 16_550 | 17_378 |
| `test_u252_div_rem_and_bits` | 2_063_174 | 2_063_174 | 2_166_333 |
| `test_u252_into_roundtrip` | 342_682 | 342_682 | 359_817 |
| `test_u252_mul_overflow` | 26_470 | 26_470 | 27_794 |
| `test_u252_or_overflow` | 22_296 | 22_296 | 23_411 |
| `test_u252_serde_and_packing` | 229_352 | 229_352 | 240_820 |
| `test_u252_set_bit_overflow` | 21_343 | 21_343 | 22_411 |
| `test_u252_shifts_against_u256` | 25_993_259 | 25_993_259 | 27_292_922 |
| `test_u252_shl_edges` | 18_119_527 | 18_119_527 | 19_025_504 |
| `test_u252_shl_overflow_top` | 21_593 | 21_593 | 22_673 |
| `test_u252_shl_overflow_wide` | 21_113 | 21_113 | 22_169 |
| `test_u252_shr_inexact` | 19_590 | 19_590 | 20_570 |
| `test_u252_sub_underflow` | 19_140 | 19_140 | 20_097 |
| `test_u252_u256_try_into_edges` | 13_720 | 13_720 | 14_406 |

`test_u252_arithmetic_against_u256` (all pairs of 48 samples against the `u256` oracle),
`test_u252_shifts_against_u256` and `test_u252_shl_edges` are property tests, not benchmarks: their
cost is the cost of the oracle loops.
