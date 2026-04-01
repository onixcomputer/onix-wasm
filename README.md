# onix-wasm

WASM plugins for `builtins.wasm` in the
[onix CppNix fork](https://github.com/brittonr/nix/tree/onix).

Provides a Nickel evaluator, YAML parser, and INI parser that run
inside the Nix evaluator via wasmtime. No IFD, no JSON round-trip.

## Plugins

| Plugin | Entry points | Description |
|--------|-------------|-------------|
| `nickel_plugin.wasm` | `evalNickel`, `evalNickelFile`, `evalNickelFileWith`, `evalNickelWith` | Nickel evaluator with ForeignId passthrough |
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

## ForeignId passthrough

Nix values that aren't simple data types (functions, paths, derivations)
pass through the Nickel evaluator as opaque `ForeignId` handles. They're
never serialized -- `nickel_to_nix` recovers the original Nix value via
`Value::from_raw()`. String contexts are preserved.

## Building

```
nix build  # produces .wasm files in result/
```

Requires the `nickel-wasm-vendor` input (vendored nickel-lang-core
patched for wasm32).
