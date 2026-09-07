{
  runCommand,
  zstd,
  plugins,
}:
let
  ini = plugins.iniPlugin.cargoArtifacts;
  yaml = plugins.yamlPlugin.cargoArtifacts;
  nickel = plugins.nickelPlugin.cargoArtifacts;
in
assert ini.CARGO_BUILD_TARGET == plugins.iniPlugin.CARGO_BUILD_TARGET;
assert yaml.CARGO_BUILD_TARGET == plugins.yamlPlugin.CARGO_BUILD_TARGET;
runCommand "parser-dependency-artifacts"
  {
    nativeBuildInputs = [ zstd ];
  }
  ''
    full_bytes=$(stat -c %s ${nickel}/target.tar.zst)
    for artifacts in ${ini} ${yaml}; do
      test -s "$artifacts/target.tar.zst"
      parser_bytes=$(stat -c %s "$artifacts/target.tar.zst")
      test "$parser_bytes" -lt "$full_bytes"
      tar --use-compress-program=unzstd -tf "$artifacts/target.tar.zst" > entries
      if grep -Eq '/libnickel_lang_.*\.(rlib|rmeta)$' entries; then
        echo "A parser archive contains compiled Nickel libraries" >&2
        exit 1
      fi
    done
    tar --use-compress-program=unzstd -tf ${ini}/target.tar.zst > ini-entries
    tar --use-compress-program=unzstd -tf ${yaml}/target.tar.zst > yaml-entries
    grep -Eq '/libconfigparser-[[:xdigit:]]+\.rlib$' ini-entries
    grep -Eq '/libyaml_rust2-[[:xdigit:]]+\.rlib$' yaml-entries
    if grep -Eq '/libyaml_rust2-[[:xdigit:]]+\.(rlib|rmeta)$' ini-entries \
      || grep -Eq '/libconfigparser-[[:xdigit:]]+\.(rlib|rmeta)$' yaml-entries; then
      echo "A parser archive contains the other parser library" >&2
      exit 1
    fi
    touch "$out"
  ''
