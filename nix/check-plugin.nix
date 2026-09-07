{
  runCommand,
  nixHost,
  plugins,
  source,
  name ? "nickel-plugin-check",
}:
runCommand name
  {
    nativeBuildInputs = [ nixHost ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export NIX_CONFIG="experimental-features = nix-command wasm-builtin"
    nix eval --store "$TMPDIR/store" --json --impure --file ${source}/tests/batch.nix \
      --apply 'f: f { plugins = ${plugins}; }' > single.json
    nix eval --store "$TMPDIR/store" --json --impure --file ${source}/tests/batch.nix \
      --apply 'f: f { plugins = ${plugins}; batch = true; }' > batch.json
    nix eval --store "$TMPDIR/store" --json --impure --file ${source}/tests/map.nix \
      --apply 'f: f { plugins = ${plugins}; }' > map-baseline.json
    nix eval --store "$TMPDIR/store" --json --impure --file ${source}/tests/map.nix \
      --apply 'f: f { plugins = ${plugins}; prepared = true; }' > map.json
    nix eval --store "$TMPDIR/store" --json --impure --file ${source}/tests/parsers.nix \
      --apply 'f: f { plugins = ${plugins}; }' > parsers.json
    grep -qx true parsers.json
    grep -qx true single.json
    grep -qx true batch.json
    grep -qx true map-baseline.json
    grep -qx true map.json
    touch "$out"
  ''
