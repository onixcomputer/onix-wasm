# Snapshot only Nickel. Parser-only changes must not repeat this step.
{
  runCommand,
  binaryen,
  wizer,
  plugin,
  constructorTimeoutSeconds ? 120,
}:
runCommand "nickel-plugin-preinitialized"
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
    wasm-dis ${plugin}/nickel_plugin.wasm -o before.wat
    grep -Fq "(export \"$constructor\" " before.wat

    mkdir "$out"
    timeout ${toString constructorTimeoutSeconds} wizer \
      --init-func "$constructor" --keep-init-func false \
      --inherit-env false --inherit-stdio false \
      -o "$out/nickel_plugin.wasm" ${plugin}/nickel_plugin.wasm

    wasm-dis "$out/nickel_plugin.wasm" -o after.wat
    if grep -Fq "(export \"$constructor\" " after.wat; then
      echo "Nickel standard-library constructor did not finish" >&2
      exit 1
    fi
    test -s "$out/nickel_plugin.wasm"
  ''
