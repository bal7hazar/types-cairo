# Changelog

All notable changes to the packages of this repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Numeric results, panics and their
messages are API.

## [Unreleased]

### Added

- Workspace `types-cairo` and its first package, `u252`: the type `u252`, `U252Trait`, `PRIME`,
  the conversions, storage packing, arithmetic, order, bitwise operators and constants of
  `origami_hexmap` 1.8.0 (`dojoengine/origami` at `04ab30c`), with unchanged behaviour.
- Module `u252::bits`: the tables `POW`, `INV`, `POW128`, the constant `TWO_POW_128` and the
  helpers `Bits::{pow, inv, shl, shr_exact, to_felt, get, set, unset}`.
- Tests and gas benchmarks of `u252` and of the extracted helpers, each with a gas budget
  (`crates/u252/GAS.md`). Measured gas is identical to `origami_hexmap` 1.8.0 on every test.
- CI: format check, build, tests and packaging with scarb 2.19.4 and snforge 0.61.0.
