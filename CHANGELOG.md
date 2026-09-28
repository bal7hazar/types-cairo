# Changelog

All notable changes to the packages of this repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Numeric results, panics and their
messages are API.

## [Unreleased]

## uint252 [0.1.0] - 2026-09-28

Published on scarbs.xyz: <https://scarbs.xyz/packages/uint252>, from commit `daf5576`.

### Added

- Workspace `types-cairo` and its first package, `uint252` (`crates/u252`): the type `u252`, `U252Trait`, `PRIME`,
  the conversions, storage packing, arithmetic, order, bitwise operators and constants of
  `origami_hexmap` 1.8.0 (`dojoengine/origami` at `04ab30c`), with unchanged behaviour.
- Module `uint252::bits`: the tables `POW`, `INV`, `POW128`, the constant `TWO_POW_128` and the
  helpers `Bits::{pow, inv, shl, shr_exact, to_felt, get, set, unset}`.
- Tests and gas benchmarks of `u252` and of the extracted helpers, each with a gas budget
  (`crates/u252/GAS.md`). Measured gas is identical to `origami_hexmap` 1.8.0 on every test.
- The package is named `uint252` and not `u252`: a package named like its type cannot be
  imported with `use u252::{U252Trait, u252};` (Cairo 2.19.4).
- CI: format check, build, tests and packaging with scarb 2.19.4 and snforge 0.61.0.
