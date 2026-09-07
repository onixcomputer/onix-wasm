{
  plugins,
  prepared ? false,
}:
let
  wasm = import ../nix/wasm.nix { inherit plugins; };
  apply =
    source: args:
    if prepared then
      wasm.evalNickelMap source args
    else
      wasm.evalNickelWithBatch (
        builtins.map (value: {
          inherit source;
          args = value;
        }) args
      );
  applyImport =
    source: args: base:
    if prepared then
      wasm.evalNickelMapImport source args base
    else
      wasm.evalNickelWithBatch (
        builtins.map (value: {
          inherit source base;
          args = value;
        }) args
      );
  rejects = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  raw = builtins.wasm {
    path = "${plugins}/nickel_plugin.wasm";
    function = "evalNickelMap";
  };
  source = "let helper = fun x => x + 1 in fun args => { values = std.array.map helper args.values, name = args.name }";
  drv = derivation {
    name = "nickel-map-context";
    system = builtins.currentSystem;
    builder = "/bin/sh";
  };
  opaque = {
    function = x: x;
    path = ./.;
    package = drv;
    string = "${drv}";
  };
  values = apply "fun args => args" [
    opaque
    { value = 1; }
    opaque
  ];
in
assert apply "not valid Nickel" [ ] == [ ];
assert apply (throw "empty map forced source") [ ] == [ ];
assert applyImport (throw "empty map forced source") [ ] (throw "empty map forced base") == [ ];
assert !prepared || rejects (raw { });
assert
  !prepared
  || rejects (raw {
    args = [ { } ];
  });
assert !prepared || rejects (raw false);
assert !prepared || rejects (apply "fun args => args" false);
assert rejects (apply false [ { } ]);
assert
  apply source [
    {
      name = "first";
      values = [
        1
        2
      ];
    }
    {
      name = "second";
      values = [ 4 ];
    }
    {
      name = "empty";
      values = [ ];
    }
  ] == [
    {
      name = "first";
      values = [
        2
        3
      ];
    }
    {
      name = "second";
      values = [ 5 ];
    }
    {
      name = "empty";
      values = [ ];
    }
  ];
assert (builtins.head values).function "same" == "same";
assert (builtins.head values).path == opaque.path;
assert (builtins.head values).package.drvPath == drv.drvPath;
assert builtins.getContext (builtins.elemAt values 2).string == builtins.getContext opaque.string;
assert
  applyImport "fun args => (import \"value.ncl\") + args.value" [
    { value = 0; }
    { value = 1; }
  ] ./left/value.ncl == [
    1
    2
  ];
assert
  applyImport "fun args => (import \"value.ncl\") + args.value" [ { value = 0; } ] ./right/value.ncl
  == [ 2 ];
assert rejects (
  apply "fun args => (args.value | Number) + 1" [
    { value = 1; }
    { value = "wrong"; }
  ]
);
assert rejects (apply "fun args => args.missing" [ { } ]);
assert rejects (apply "let =" [ { } ]);
assert rejects (apply "1" [ { } ]);
assert rejects (apply "fun args => import \"value.ncl\"" [ { } ]);
assert apply "fun args => args.value" [ { value = 3; } ] == [ 3 ];
true
