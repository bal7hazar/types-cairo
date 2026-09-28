# u252

An unsigned integer with the value set of `felt252`, `[0, P - 1]`
(`P = 2^251 + 17 * 2^192 + 1`), held in one field element.

Every felt is a valid `u252`: conversions with `felt252`, `Serde` and storage packing are free
and cannot fail. The checked operations panic exactly when the true integer result leaves
`[0, P - 1]`.

The code is extracted from [`origami_hexmap`](https://github.com/dojoengine/origami/tree/main/crates/hexmap)
1.8.0 (`dojoengine/origami` at `04ab30c`), where the type was born. **Numeric results are API**:
names, signatures, results, panics and their messages are those of `origami_hexmap` 1.8.0, and
changing one of them is a breaking change.

## Installation

```toml
[dependencies]
u252 = "0.1.0"
```

Toolchain: Cairo 2.19.4 (scarb 2.19.4), edition `2024_07`. The package has no dependency;
`StorePacking` comes from the core library.

## Usage

```rust
use core::num::traits::{Bounded, CheckedAdd, WrappingAdd};
use u252::{PRIME, U252Trait};

// Conversions with `felt252` are free, both ways
let x: u252::u252 = 0x2a.into();
let raw: felt252 = x.into();

// Checked arithmetic on the integers `[0, P - 1]`
let max: u252::u252 = Bounded::MAX;
assert!(max.checked_add(x).is_none());
assert!(max.wrapping_add(x).value() == 0x29); // modulo P
assert!(x + x == 84_u8.into()); // panics with 'u252_add Overflow' above P - 1

// Shifts and bits
assert!(x.shl(3) == 336_u16.into());
assert!(x.shr(1) == 21_u8.into());
assert!(x.bit(1) && !x.bit(0));
let (quotient, remainder) = x.div_rem(5);
```

These examples are compiled and run by `tests/readme.cairo`.

### Importing the type

The package and the type share the name `u252`. In Cairo 2.19.4 a name imported in a module
hides the package of the same name, so a module that imports the type cannot import anything
else from the package:

```rust
use u252::{U252Trait, u252}; // error[E2086]: Invalid path.
```

| Form | |
|---|---|
| `use u252::{PRIME, U252Trait};` and the type written `u252::u252` | Works, used by the examples above |
| `use u252::u252;` as the only import from the package in the module | Works; the traits and constants then come through another module of yours that re-exports them |
| Through a package that re-exports it: `use origami_hexmap::{U252Trait, u252};` | Works |

### What is in the package

| Item | |
|---|---|
| `u252::u252` | The type: `Copy, Drop, PartialEq, Serde, Debug, Default` |
| `u252::PRIME` | `P` as a `u256` |
| `u252::U252Trait` | `new`, `value`, `shl`, `shr_exact`, `shr`, `div_rem`, `bit`, `set_bit` |
| Conversions | `Into` from `felt252`, `u8`, `u16`, `u32`, `u64`, `u128`; `Into` to `felt252` and `u256`; `TryInto` from `u256` and to `u8` .. `u128` |
| Storage | `StorePacking<u252, felt252>` |
| Arithmetic | `+`, `-`, `*` (panic on overflow), `/`, `%`, `CheckedAdd`, `CheckedSub`, `CheckedMul`, `WrappingAdd`, `WrappingSub`, `WrappingMul` (modulo `P`) |
| Order and bits | `PartialOrd`, `&`, `\|`, `^` |
| Constants | `Zero`, `One`, `Bounded` |
| `u252::bits` | `Bits` (`pow`, `inv`, `shl`, `shr_exact`, `to_felt`, `get`, `set`, `unset`), `TWO_POW_128`, the tables `POW`, `INV`, `POW128` |

The root re-exports `u252`, `U252Trait` and `PRIME`; they live in the module `u252::integer`.

### Panics

| Message | Raised by |
|---|---|
| `'u252_add Overflow'` | `+` |
| `'u252_sub Overflow'` | `-` |
| `'u252_mul Overflow'` | `*` |
| `'u252_shl Overflow'` | `shl` |
| `'u252_shr Inexact'` | `shr_exact` |
| `'u252_or Overflow'` | `\|`, `set_bit` (also for an index above 251) |
| `'u252_xor Overflow'` | `^` |
| `'Index out of bounds'` (core library) | `shl`, `shr`, `shr_exact` by more than 251 (the table lookup) |
| `'Division by 0'` (core library) | `/`, `%` by zero |

## When to use it

Use `u252` for counters, packed values and stored values that are felts on the wire:
conversions, `Serde`, `StorePacking`, `==`, wrapping arithmetic and exact shifts cost nothing or
less than `u256`. Keep `u256` (or felt bitmaps) for set operations and comparisons: `&`, `|`,
`^`, `<` and checked `+` / `-` split the felt into two limbs first and cost 2x to 3x the `u256`
operation (checked add 4.2k against 1.9k, `&` 6.1k against 2.4k). Figures: [GAS.md](GAS.md).

### Why `u256` appears in the code

`u256` is used inside the package for one reason: the `felt252 -> u256` split
(`u128s_from_felt252`) is the only sound range proof on a full-range felt, and no libfunc offers
a bitwise operation wider than `u128`. Order, checked arithmetic, `/`, `%` and the bitwise
operators therefore work on the two limbs of the canonical integer. Everything that can stay a
field operation does.

## The module `u252::bits`

`u252` reads three tables and four helpers of `origami_hexmap::helpers::bits`. The extraction
takes the helpers that read those tables and nothing else:

| Extracted | Why |
|---|---|
| `POW`, `INV`, `POW128`, `TWO_POW_128` | The tables of `2^k`, `2^-k` and the `u128` powers, read by `shl`, `shr`, `shr_exact`, `bit`, `set_bit` |
| `Bits::pow`, `Bits::inv`, `Bits::to_felt`, `Bits::get` | Called by `u252` |
| `Bits::shl`, `Bits::shr_exact`, `Bits::set`, `Bits::unset` | The unchecked felt operations that the benchmarks of `u252` compare it with, and that the tests of `Bits::get` need. One line each over the same tables: no table, no builtin and no dependency is added |

| Left in `origami_hexmap` | Why |
|---|---|
| `Bits::bitwise`, `and`, `or`, `xor` and the local `extern fn bitwise` | Set algebra of the board algorithms; `u252` uses the core operators |
| `Bits::popcount`, `popcount_small`, `popcount_sparse`, `byte_counts`, `top_byte`, `low_byte` | Used by the generators only |
| `Set<T>`, `WideSet`, `SmallSet` | Generic sets of the path finders |
| `TWO_POW_32`, `TWO_POW_64`, `TWO_POW_120`, `BYTES_ONE` | Constants of the random pool and of the population count |

## Deviations from `origami_hexmap` 1.8.0

The behaviour of every extracted item is unchanged. What differs:

| Deviation | Reason |
|---|---|
| Paths: `origami_hexmap::types::u252::*` is `u252::integer::*` (root: `u252::{u252, U252Trait, PRIME}`), `origami_hexmap::helpers::bits::*` is `u252::bits::*` | A new package. The module cannot be named `u252` next to the re-exported type |
| `PRIME` is also re-exported at the root | It was reachable only through `types::u252` |
| A consumer cannot write `use u252::{U252Trait, u252};` | The package and the type share a name, see "Importing the type" |
| `u252::bits` holds 8 of the 18 functions of `Bits`, none of `Set<T>`, 1 of the 5 public constants | See "The module `u252::bits`" |
| The unit tests carry `#[available_gas]` | The owner's rule: every test has a budget. They had none |
| Budgets are `ceil(1.05 * measured)`, no longer rounded up to 1000 | The owner's rule. Every budget is lower than or equal to the one of `origami_hexmap` |
| `test_bits_popcount` and `test_bits_bitwise` are not brought | They test helpers that are not extracted |
| The five benchmarks `bench_u252_expand*` and `bench_u252_step*` are not brought | They measure `Layout::expand` of `origami_hexmap` on a board fixture |
| `test_readme_u252` is replaced by `tests/readme.cairo` of this package | It used `HexMap` |
| In `bench_u252.cairo`: the unused import `TWO_POW_128` and the constant `INV_2` are removed | `INV_2` served the benchmarks that are not brought |
| Module documentation: references to `GAS.md`, section "S1 u252" point to `GAS.md` | The section is the whole file here |

## Migration

### `origami_hexmap`

`origami_hexmap` depends on this package and keeps its public paths, so that
`use origami_hexmap::{U252Trait, u252}` and `origami_hexmap::types::u252::PRIME` keep working.

```toml
# crates/hexmap/Scarb.toml
[dependencies]
u252 = "0.1.0"
```

```rust
// src/types/u252.cairo, the whole file
pub use u252::integer::*;
```

```rust
// src/helpers/bits.cairo: the tables and `TWO_POW_128` come from the package,
// the rest of the file (`Bits`, `Set<T>`, the other constants) is unchanged
pub use u252::bits::{INV, POW, POW128, TWO_POW_128};
```

`src/lib.cairo` is unchanged (`pub use types::u252::{U252Trait, u252};`). The tests and
benchmarks of `u252` that moved here can be removed there; `bench_u252_expand*`,
`bench_u252_step*`, `test_bits_popcount` and `test_bits_bitwise` stay. A module of
`origami_hexmap` that imports the type `u252` cannot also import from the package `u252`
directly: it goes through `origami_hexmap::types::u252` and `origami_hexmap::helpers::bits`, as
today.

This layout was compiled against this package (a library re-exporting as above, and a package
with a Starknet contract storing a `u252`, depending on both); the type is the same through both
paths.

### A game or any other consumer

```toml
[dependencies]
u252 = "0.1.0"
```

```rust
use u252::{PRIME, U252Trait};

#[storage]
struct Storage {
    value: u252::u252,
}
```

A consumer that already depends on `origami_hexmap` can keep `use origami_hexmap::{U252Trait, u252};`.

## Tests

```sh
cd crates/u252
scarb fmt --check
scarb build
snforge test
```

Every test has a gas budget; the figures are in [GAS.md](GAS.md).

## License

MIT
