{
  runCommand,
  plugins,
  monolithic,
}:
let
  variants = [
    plugins.nickelPlugin
    plugins.yamlPlugin
    plugins.iniPlugin
  ];
  rejects = args: !(builtins.tryEval ((monolithic.override args).drvPath)).success;
in
assert builtins.all (p: p.cargoArtifacts.drvPath == monolithic.cargoArtifacts.drvPath) variants;
assert rejects { plugin = "missing-plugin"; };
assert rejects { plugin = false; };
assert rejects {
  plugin = "ini-plugin";
  craneLib = null;
};
runCommand "plugin-build-scope" { } ''
  test -f ${plugins.nickelPlugin.src}/nickel-plugin/src/lib.rs
  test ! -e ${plugins.nickelPlugin.src}/yaml-plugin/src
  test ! -e ${plugins.nickelPlugin.src}/ini-plugin/src
  test -f ${plugins.yamlPlugin.src}/yaml-plugin/src/lib.rs
  test ! -e ${plugins.yamlPlugin.src}/nickel-plugin/src
  test ! -e ${plugins.yamlPlugin.src}/ini-plugin/src
  test -f ${plugins.iniPlugin.src}/ini-plugin/src/lib.rs
  test ! -e ${plugins.iniPlugin.src}/nickel-plugin/src
  test ! -e ${plugins.iniPlugin.src}/yaml-plugin/src
  for source in ${builtins.toString (map (p: p.src) variants)}; do
    test -f "$source/nix-wasm-rust/src/lib.rs"
    for crate in nickel-plugin yaml-plugin ini-plugin; do
      test -f "$source/$crate/Cargo.toml"
    done
  done
  touch "$out"
''
