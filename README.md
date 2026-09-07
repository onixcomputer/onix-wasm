# onix-wasm

WASM plugins for `builtins.wasm` in the
[onix CppNix fork](https://github.com/brittonr/nix/tree/onix).

Provides a Nickel evaluator, YAML parser, and INI parser that run
inside the Nix evaluator via wasmtime. No IFD, no JSON round-trip.

## Plugins

| Plugin | Entry points | Description |
|--------|-------------|-------------|
| `nickel_plugin.wasm` | `evalNickel`, `evalNickelFile`, `evalNickelFileWith`, `evalNickelWith`, `evalNickelBatch`, `evalNickelWithBatch`, `evalNickelMap` | Nickel evaluator with ForeignId passthrough |
| `yaml_plugin.wasm` | `fromYAML`, `toYAML` | YAML parser/serializer |
| `ini_plugin.wasm` | `fromINI` | INI parser |

## Nix wrapper

`nix/wasm.nix` exposes the plugins as regular Nix functions:

```nix
let wasm = onix-wasm.lib.${system}; in
{
  config = wasm.evalNickelFile ./config.ncl;
  data = wasm.evalNickelFileWith ./module.ncl { name = "world"; pkg = pkgs.hello; };
  parsed = builtins.head (wasm.fromYAML (builtins.readFile ./config.yaml));
}
```

## Batch evaluation

`evalNickelBatch` accepts a list of inputs with the same shape as `evalNickel`.
`evalNickelWithBatch` accepts records with `source`, `args`, and optional `base` fields.

```nix
wasm.evalNickelWithBatch [
  { source = "fun args => args.value + 1"; args.value = 1; }
  { source = "fun args => args.value + 1"; args.value = 2; }
]
# => [ 2 3 ]
```

A batch uses one prepared standard-library cache within one Wasm instance.
Each request still gets a fresh Nickel evaluation cache and import provider.
Bindings and imported files do not carry over between requests.
Opaque Nix values and string contexts retain their existing behavior.

A batch evaluates every request in order before it returns the result list.
An error aborts the whole batch without a partial result.
This differs from a lazy Nix `map`: even an unselected result can cause the batch to fail.
Use individual calls for independent error recovery or lazy result selection.
An empty batch returns an empty list without standard-library preparation.

Batch size is caller-controlled. Large batches retain Nix value handles until the call ends.
This change does not reuse live instances between calls or remove module compilation across processes.
It targets evaluation overhead, not the compilation time of derivations.

### Repeated applications of one source

`evalNickelMap source args` prepares one source once and applies it to each argument in the list.
`evalNickelMapImport source args base` also supplies a file-import base, with the same interpretation as `evalNickelWithImport`.

```nix
wasm.evalNickelMap "fun args => args.value + 1" [
  { value = 1; }
  { value = 2; }
]
# => [ 2 3 ]
```

The prepared template contains parsed and transformed source and imports, not evaluated closures.
Each application receives a cloned template, a cloned position table, and a fresh VM.
The template never stores result thunks or VM cache indices.
This saves repeated parsing and preparation on top of standard-library reuse.
An empty argument list returns an empty list without forcing the source or import base.
A nonempty list evaluates eagerly and fails as a whole on an error.

Use `evalNickelWithBatch` for different sources or import bases.
Use `evalNickelMap` for one common source and import base.
Both APIs keep state within one Wasm call and preserve opaque Nix handles.

#### Prepared-source measurements (2026-09-06)

The comparison uses the existing `evalNickelWithBatch` as its baseline, not separate Wasm calls.
Both modes use the same source, arguments, host, and plugin.
Each row used one warmup and three measured processes per mode, with exact result assertions.

| Applications × fields | Order | Existing batch | Prepared source |
|---|---|---|---|
| 500 × 100 | Batch first | 5.661 ± 0.538 seconds | 4.949 ± 0.578 seconds |
| 200 × 1,000 | Prepared first | 10.653 ± 0.591 seconds | 7.075 ± 0.973 seconds |
| 200 × 1,000 | Batch first | 7.789 ± 2.368 seconds | 4.106 ± 0.065 seconds |

The uncertainties are sample standard deviations. The shared host had variable load.
The larger-source workload favored preparation in both orders. The smaller-source timings overlap.
These measurements do not establish a universal speedup or lower peak memory.

- Host: `/nix/store/6rwk5j1qqk7na4la5m2ka34p734braxa-nix-2.36.0/bin/nix`
- Plugin: `/nix/store/wz4ca05sszvaw65fci410yxndlkfyj7j-nix-wasm-plugins-0.1.0/nickel_plugin.wasm`
- Plugin BLAKE3: `b000f4d4bb8fce5c71c82458b87e0c96f164bea966f293aa4b04fa5fe024a479`

```sh
"$NIX_BINARY" eval --json --impure \
  --extra-experimental-features 'nix-command wasm-builtin' \
  --file tests/map-bench.nix \
  --apply "f: f { plugins = $PLUGINS; prepared = true; requestCount = 200; fieldCount = 1000; }"
```

Set `prepared = false` for the batch baseline.

### Verification

`nix flake check -L` runs the batch and individual-call controls with a pinned Wasm-capable Nix host.
The controls cover result order, import isolation, opaque values, contracts, malformed input, and calls after errors.
`tests/map.nix` compares prepared-source applications with the existing batch API.
`tests/map-bench.nix` compares the same source and arguments in both modes, with an exact result assertion.
The benchmark in `tests/batch-bench.nix` asserts exact output equality before it returns the request count.

```sh
"$NIX_BINARY" eval --json --impure \
  --extra-experimental-features 'nix-command wasm-builtin' \
  --file tests/batch-bench.nix \
  --apply "f: f { plugins = $PLUGINS; batch = true; requestCount = 20; }"
```

Use `batch = false` for the individual-call comparison with the same host and plugin.
Both modes include module compilation once per process.
No new host capability or system service is involved, so direct evaluator tests cover this change without a VM.

### Measured result (2026-09-06)

These batch measurements used the raw plugin before preinitialization became the default.
They do not establish the incremental batch benefit on the current default image.
For 500 small function evaluations, both benchmark orders favored the batch.
Each row used one warmup and three measured processes per mode on the same x86_64-linux host.
Every process asserted exact result equality.

| Order | Individual calls | Batch |
|---|---|---|
| Batch first | 21.940 ± 3.556 seconds | 4.933 ± 0.890 seconds |
| Individual first | 19.167 ± 1.245 seconds | 7.299 ± 0.693 seconds |

The uncertainties are sample standard deviations.
The shared host had variable load. These results do not establish a universal speedup or a benefit for single requests.
Initial probes at 1, 20, and 100 requests had substantial variance.
Batching retains result handles for the entire call, so this result is not a peak-memory guarantee.

Measured artifacts:

- Host: `/nix/store/6rwk5j1qqk7na4la5m2ka34p734braxa-nix-2.36.0/bin/nix`
- Plugin: `/nix/store/0y2y4wvfa22w51gq42lsbk8840b16jfl-nix-wasm-plugins-0.1.0/nickel_plugin.wasm`
- Plugin BLAKE3: `8efba1d5b32bc1353844b58674f1267e596d425edc1acb5bc172140ca6d25f3f`

The plugin derivation stayed at `b3zyyg16bhggzkx0hir3i6mgrr4r2vxy` after documentation and check-definition changes.
The source-scope change avoids those rebuilds rather than making Rust compilation faster.

## ForeignId passthrough

Nix values that aren't simple data types (functions, paths, derivations)
pass through the Nickel evaluator as opaque `ForeignId` handles. They're
never serialized -- `nickel_to_nix` recovers the original Nix value via
`Value::from_raw()`. String contexts are preserved.

## Building

```
nix build  # produces .wasm files in result/
```

Requires the `nickel-wasm-vendor` input (vendored Nickel crates patched for wasm32).

Plugin source inputs include only the workspace manifests and the four plugin/binding crates.
The pinned vendor input supplies the Nickel crates separately.
Documentation, Nix wrappers, and test fixtures do not invalidate the plugin build.
The `plugin-source-scope` check verifies included and excluded paths.

## Build-time standard-library preparation

The default `wasm-plugins` package now uses a preinitialized Nickel image.
Wizer 10.0.0 runs `prepareNickelStdlib` during the build and snapshots its memory.
The existing `evalNickel`, file, batch, and map APIs consume that image without caller changes.
Every Wasm call still starts a fresh instance. User sources and arguments never enter the build-time cache.

The build enables no WASI, environment inheritance, standard streams, directory mappings, or preload stubs for the guest.
Wizer rejects imported host calls during initialization.
Its host-side compilation cache stays inside the temporary build directory.
A timeout bounds the constructor step. The build verifies that Wizer removed the constructor export.
The runtime panic hook remains in `nix_wasm_init_v1` and runs normally.

Package variants:

- `wasm-plugins` and `default`: the preinitialized image.
- `wasm-plugins-preinitialized`: an explicit alias for that image.
- `wasm-plugins-uninitialized`: the raw plugin for comparisons and debugging.

`nix flake check -L` runs the same single-call, batch, and map controls against both images.
A separate check repeats initialization and compares the complete output bytes.
It also verifies unchanged YAML/INI binaries and rejects a constructor that calls an imported function.
Binaryen constructor evaluation was rejected because it stopped at `memory.grow` with a successful exit status.
Wizer completes the initialization instead of retaining partially evaluated code.

### Preinitialization measurements (2026-09-06)

The workload uses individual `evalNickelWith` calls, not the batch API.
Each timing uses one warmup and three measured processes, with exact output assertions.

| Calls | Raw image | Preinitialized image |
|---|---|---|
| 1 | 5.769 ± 1.760 seconds | 3.647 ± 0.144 seconds |
| 500 | 18.727 ± 2.319 seconds | 7.655 ± 0.618 seconds |
| 500, reverse order | 20.083 ± 3.990 seconds | 15.990 ± 9.065 seconds |

The first 500-call comparison reduced mean user CPU time from 12.494 to 3.397 seconds.
The reverse-order comparison reduced it from 12.971 to 4.497 seconds, despite substantial elapsed-time variance.
The uncertainties are sample standard deviations. Shared-host load varied, and Hyperfine reported outliers.
These measurements do not establish a universal speedup, and ratios from earlier batch benchmarks must not be multiplied by these ratios.

One direct GNU Time probe at 500 calls reported peak RSS of 263,564 KiB for the raw image and 257,884 KiB for the initialized image.
This is one workload observation, not a general memory guarantee.
The Nickel module increased from 3,880,876 to 5,703,567 bytes.
The build adds a snapshot step. It does not make Rust compilation faster or remove native Wasm compilation from evaluation startup.

Measured host: `/nix/store/6rwk5j1qqk7na4la5m2ka34p734braxa-nix-2.36.0/bin/nix`.
Measured raw package: `/nix/store/7qwrdslhgl2fdyqbwjkp27ii74p87wjx-nix-wasm-plugins-0.1.0`.
Measured initialized package: `/nix/store/4aybqsf0gjiscainnlsssrnbqsrcccyf-nix-wasm-plugins-preinitialized`.
Initialized Nickel BLAKE3: `0abd65136629edfd03a5fc19ed0f6324ab8f753706ba8e4866e9bfd03290d21e`.
Wizer comes from the existing locked nixpkgs input. No unpinned runtime tool is required.

## Nickel vendor sync

`josh/nickel-wasm.josh` is the local Josh path-selection pilot for the Nickel crates copied from the sibling `../nickel-wasm` checkout. The ignored local `vendor/` tree can be refreshed and verified with `scripts/check-nickel-wasm-josh-sync.rs`; see `docs/nickel-wasm-josh-sync.md`. The pre-commit hook runs only the local config check and does not require GitHub or a sibling checkout.
