# The benchmark temporarily adds a pass-through export to the plugin source.
# This check rejects a no-op build or an output from the unchanged source.
{ originalPlugins, changedPlugins }:
let
  invoke =
    plugins:
    builtins.wasm {
      path = "${plugins}/nickel_plugin.wasm";
      function = "dependencyCacheProbe";
    };
  expected = {
    source = "changed plugin";
    values = [
      true
      null
    ];
  };
in
assert invoke changedPlugins expected == expected;
assert !(builtins.tryEval (invoke originalPlugins expected)).success;
true
