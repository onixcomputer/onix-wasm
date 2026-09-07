{
  runCommand,
  nickelPlugin,
  yamlPlugin,
  iniPlugin,
}:
runCommand "nix-wasm-plugins-bundle"
  {
    passthru = {
      inherit nickelPlugin yamlPlugin iniPlugin;
      src = nickelPlugin.fullSource;
      cargoArtifacts = nickelPlugin.cargoArtifacts;
      CARGO_BUILD_TARGET = nickelPlugin.CARGO_BUILD_TARGET;
    };
  }
  ''
    mkdir -p "$out"
    cp ${nickelPlugin}/nickel_plugin.wasm "$out/"
    cp ${yamlPlugin}/yaml_plugin.wasm "$out/"
    cp ${iniPlugin}/ini_plugin.wasm "$out/"
  ''
