{
  runCommand,
  binaryen,
  zstd,
  plugins,
}:
let
  artifacts = plugins.cargoArtifacts;
in
runCommand "plugin-dependency-cache"
  {
    nativeBuildInputs = [
      binaryen
      zstd
    ];
  }
  ''
    test "${plugins.CARGO_BUILD_TARGET}" = "${artifacts.CARGO_BUILD_TARGET}"
    cmp ${plugins.src}/Cargo.lock ${artifacts.src}/Cargo.lock
    grep -Fq 'nickel-lang-core' ${artifacts.src}/nickel-plugin/Cargo.toml
    grep -Fq 'pub fn main()' ${artifacts.src}/nickel-plugin/src/lib.rs
    if grep -Fq 'prepareNickelStdlib' ${artifacts.src}/nickel-plugin/src/lib.rs; then
      echo "The dependency source contains the real plugin implementation" >&2
      exit 1
    fi
    test -s ${artifacts}/target.tar.zst
    tar --use-compress-program=unzstd -tf ${artifacts}/target.tar.zst > entries
    grep -Eq '/libnickel_lang_core-[[:xdigit:]]+\.rlib$' entries
    grep -Eq '/libnickel_lang_parser-[[:xdigit:]]+\.rlib$' entries
    test ! -e ${plugins}/target.tar.zst
    wasm-dis ${plugins}/nickel_plugin.wasm -o plugin.wat
    if grep -Fq '(export "dependencyCacheProbe"' plugin.wat; then
      echo "The release plugin contains the temporary build probe" >&2
      exit 1
    fi
    touch "$out"
  ''
