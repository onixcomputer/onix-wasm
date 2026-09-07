# Keep the Nickel snapshot separate from the bundle of independent plugins.
{
  runCommand,
  callPackage,
  plugins,
  constructorTimeoutSeconds ? 120,
}:
let
  nickelSnapshot = callPackage ./preinitialize-nickel.nix {
    plugin = plugins.nickelPlugin or plugins;
    inherit constructorTimeoutSeconds;
  };
in
runCommand "nix-wasm-plugins-preinitialized"
  {
    passthru = { inherit nickelSnapshot; };
  }
  ''
    mkdir -p "$out"
    cp ${plugins}/ini_plugin.wasm ${plugins}/yaml_plugin.wasm "$out/"
    cp ${nickelSnapshot}/nickel_plugin.wasm "$out/"
  ''
