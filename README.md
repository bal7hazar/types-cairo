# types-cairo

Types for Cairo, one package per type, published on [scarbs.xyz](https://scarbs.xyz).

| Package | Path | Content |
|---|---|---|
| [`u252`](crates/u252) | `crates/u252` | An unsigned integer with the value set of `felt252`, held in one field element |

## Rules

- **Numeric results are API.** Changing a result, a panic or its message is a breaking change.
- **Execution cost first.** Every test carries `#[available_gas(l2_gas: N)]` with
  `N = ceil(1.05 * measured)`; benchmarks are tests; the figures are in the `GAS.md` of each
  package. A budget exceeded fails the build.
- No `u256` without a written reason.

## Development

Toolchain (`.tool-versions`): scarb 2.19.4, starknet-foundry 0.61.0.

```sh
scarb fmt --check          # workspace
cd crates/u252
scarb build
snforge test
```

The pull-request CI runs the same three checks and `scarb package`; a pull request is merged on
green CI only.

## License

[MIT](LICENSE)
