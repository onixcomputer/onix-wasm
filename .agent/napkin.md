# Napkin

## Corrections
| Date | Source | What Went Wrong | What To Do Instead |
|------|--------|----------------|-------------------|
| 2026-04-03 | self | Tried editing /home/brittonr/git/nix-wasm instead of /home/brittonr/git/nix (the actual onix nix fork is onixcomputer/nix at /home/brittonr/git/nix) | Always check git remote to confirm which fork a repo is |
| 2026-04-03 | self | Assumed $dict_dyn comes from Term::App or function arg binding | $dict_dyn comes from Nickel stdlib type annotations on record introspection functions, baked into the pre-compiled stdlib in the WASM binary |
| 2026-04-03 | self | Assumed std.record.fields has a type annotation generating $dict_dyn | std.record.fields is `fun r => %record/fields% r` with no type. But the stdlib record namespace field access still triggers $dict_dyn through the pre-compiled stdlib's internal contract propagation |

## Patterns That Don't Work
- Pre-evaluating args before Term::App: args are already concrete NickelValues, contracts aren't attached to args
- Manual beta-reduction (Let instead of App): $dict_dyn comes from stdlib imports, not function application
- Replacing std.record.fields with std.record.to_array: to_array calls fields internally
- Patching to_array's type annotation in stdlib std.ncl: stdlib is pre-compiled into WASM binary, and the $dict_dyn propagation comes from a deeper mechanism than function type annotations

## Patterns That Work
- Prefixing let-bindings with `_` to avoid RecRecord self-reference: `let _root = ... in { root = _root }`
- Extracting nested `%{...}` expressions to let-bindings to avoid quoting issues in Nickel string interpolation
- Selectively extracting interface fields in evalService (only providers+packages) to avoid EnumVariant WASM conversion failures

## Domain Notes
- evalService reads mod.interface through WASM to get providers/packages — must NOT eval the full interface because enum variants (lifecycle controllers) can't convert to Nix via nickel_to_nix
- onix-modules eval tests live at tests/integration/eval-tests.nix, run with onix nix fork
- All 38 eval tests pass with nix fork 854b77d (ThrownError fix)
- System nix: /run/current-system/sw/bin/nix (2.33.3, HAS builtins.wasm but NOT string context ABI)
- Onix nix fork: built from /home/brittonr/git/nix (onixcomputer/nix), has string context ABI + ThrownError. Build: `nix build .#nix-cli`
- Onix nix binary: /nix/store/59g5z7fgc271imf1fz2iz0rsmsmdw06z-nix-2.33.3/bin/nix
- WASM vendor source: /nix/store/y8a929nfr9wggps03iczqb3adbw73vcm-7c3c2bb1e6c4e2a3b3e7d9ce5df863b944e8ca7d.tar.gz (from nickel-wasm-vendor flake input)
- Dev build: `nix develop --command bash -c 'cargo check --target wasm32-unknown-unknown -p nickel-plugin'` (needs `rustup toolchain install stable --force` first to fix stale ld wrappers)
- Nix build: `nix build` (uses default.nix with postUnpack for vendor)
