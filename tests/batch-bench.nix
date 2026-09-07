{
  plugins,
  batch ? false,
  requestCount ? 20,
}:
let
  wasm = import ../nix/wasm.nix { inherit plugins; };
  requests = builtins.genList (index: {
    source = "fun args => { value = args.value + 1, length = std.array.length [1, 2] }";
    args.value = index;
  }) requestCount;
  expected = builtins.genList (index: {
    value = index + 1;
    length = 2;
  }) requestCount;
  results =
    if batch then
      wasm.evalNickelWithBatch requests
    else
      builtins.map (request: wasm.evalNickelWith request.source request.args) requests;
in
assert requestCount > 0;
assert results == expected;
builtins.length results
