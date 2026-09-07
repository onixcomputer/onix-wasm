{
  runCommand,
  binaryen,
  wizer,
  plugins,
  initialized,
  forbiddenConstructor,
  constructorTimeoutSeconds ? 120,
}:
runCommand "nickel-preinitialization-controls"
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
      timeout ${toString constructorTimeoutSeconds} wizer \
        --init-func prepareNickelStdlib --keep-init-func false \
        --inherit-env false --inherit-stdio false \
        -o repeated.wasm ${plugins}/nickel_plugin.wasm
      cmp repeated.wasm ${initialized}/nickel_plugin.wasm
      cmp ${plugins}/ini_plugin.wasm ${initialized}/ini_plugin.wasm
      cmp ${plugins}/yaml_plugin.wasm ${initialized}/yaml_plugin.wasm

      wasm-as ${forbiddenConstructor} -o forbidden-input.wasm
      if wizer --init-func prepareNickelStdlib \
          --inherit-env false --inherit-stdio false \
          -o forbidden-output.wasm forbidden-input.wasm > rejected.log 2>&1; then
        echo "Wizer accepted an external host call during initialization" >&2
        exit 1
      fi
      grep -Fq "You cannot call arbitrary imported functions" rejected.log
      # Wizer opens the output before initialization, but must publish no image.
    test ! -s forbidden-output.wasm
      touch "$out"
  ''
