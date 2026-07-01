# Nickel WASM Josh sync pilot

`nickel-wasm-vendor` is the authoritative Nickel source input for the Nickel evaluator plugin. Onix WASM keeps a local ignored `vendor/` tree for Cargo development, while Nix builds copy the same selected Nickel crates from the pinned flake input.

## Josh filter

The pilot filter lives at `josh/nickel-wasm.josh` and selects the Nickel crates used by the WASM plugin:

- `core/`
- `parser/`
- `vector/`

The local vendor layout renames those crates to `vendor/nickel-lang-core`, `vendor/nickel-lang-parser`, and `vendor/nickel-lang-vector`. The verifier applies the same manifest rewrites as `default.nix`: inter-crate paths are adjusted to the vendor layout, and `core/Cargo.toml` dev-dependencies are stripped because the utility crate is not vendored for WASM builds.

## Local workflow

Validate only the filter, verifier unit tests, and `flake.lock` revision metadata:

```bash
nix build .#checks.$(nix eval --raw --impure --expr builtins.currentSystem).nickel-wasm-josh-sync-config --no-link
```

Refresh the ignored local vendor snapshot from the sibling Nickel checkout at the locked revision:

```bash
nix shell nixpkgs#rustc nixpkgs#gcc -c rustc --edition=2024 scripts/check-nickel-wasm-josh-sync.rs -o /tmp/check-nickel-wasm-josh-sync
/tmp/check-nickel-wasm-josh-sync --source-repo ../nickel-wasm --refresh
```

Verify the ignored local vendor snapshot against the locked Nickel revision:

```bash
/tmp/check-nickel-wasm-josh-sync --source-repo ../nickel-wasm
```

`.pre-commit-config.yaml` runs the focused config-only Nix check. It intentionally does not require `../nickel-wasm`, GitHub, or any remote token.

## Graduation criteria

Keep this as a local filter-plus-verifier pilot until Nickel and Onix WASM changes repeatedly need bidirectional atomic review. Graduate to a dedicated generic Josh sync wrapper only when the workflow needs to push local vendor edits back into Nickel history, pull Nickel changes into the ignored vendor snapshot with conflict handling, and preserve this filter as the single source of truth for selected paths.
