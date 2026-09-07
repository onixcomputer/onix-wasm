{
  plugins,
  prepared ? false,
  requestCount ? 500,
  fieldCount ? 100,
}:
let
  wasm = import ../nix/wasm.nix { inherit plugins; };
  fields = builtins.genList (
    index: "field${toString index} = args.value + ${toString index}"
  ) fieldCount;
  source = "fun args => { ${builtins.concatStringsSep ", " fields} }";
  args = builtins.genList (index: { value = index; }) requestCount;
  expected = builtins.genList (
    value:
    builtins.listToAttrs (
      builtins.genList (index: {
        name = "field${toString index}";
        value = value + index;
      }) fieldCount
    )
  ) requestCount;
  result =
    if prepared then
      wasm.evalNickelMap source args
    else
      wasm.evalNickelWithBatch (
        builtins.map (value: {
          inherit source;
          args = value;
        }) args
      );
in
assert requestCount > 0 && fieldCount > 0;
assert result == expected;
builtins.length result
