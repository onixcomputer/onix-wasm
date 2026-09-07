# Separate, deterministic initialization stage. Wizer must complete without
# imported host calls; no WASI, environment, files, or preload stubs are enabled.
{
  runCommand,
  binaryen,
  wizer,
  plugins,
  constructorTimeoutSeconds ? 120,
}:
runCommand "nix-wasm-plugins-preinitialized"
  {
    nativeBuildInputs = [
      binaryen
      wizer
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$HOME" "$XDG_CACHE_HOME"
    constructor=prepareNickelStdlib
    wasm-dis ${plugins}/nickel_plugin.wasm -o before.wat
    grep -Fq "(export \"$constructor\" " before.wat

    mkdir "$out"
    cp ${plugins}/ini_plugin.wasm ${plugins}/yaml_plugin.wasm "$out/"
    timeout ${toString constructorTimeoutSeconds} wizer \
      --init-func "$constructor" --keep-init-func false \
      --inherit-env false --inherit-stdio false \
      -o "$out/nickel_plugin.wasm" ${plugins}/nickel_plugin.wasm

    wasm-dis "$out/nickel_plugin.wasm" -o after.wat
    if grep -Fq "(export \"$constructor\" " after.wat; then
      echo "Nickel standard-library constructor did not finish" >&2
      exit 1
    fi
    test -s "$out/nickel_plugin.wasm"
  ''
