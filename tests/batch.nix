{
  plugins,
  batch ? false,
}:
let
  wasm = import ../nix/wasm.nix { inherit plugins; };
  evalMany = if batch then wasm.evalNickelBatch else builtins.map wasm.evalNickel;
  applyMany =
    if batch then
      wasm.evalNickelWithBatch
    else
      builtins.map (
        request:
        if request ? base then
          wasm.evalNickelWithImport request.source request.args request.base
        else
          wasm.evalNickelWith request.source request.args
      );
  rejects = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  drv = derivation {
    name = "nickel-batch-context";
    system = builtins.currentSystem;
    builder = "/bin/sh";
  };
  opaque = {
    function = x: x;
    path = ./.;
    package = drv;
    string = "${drv}";
  };
  outputs = applyMany [
    {
      source = "fun args => args";
      args = opaque;
    }
    {
      source = "fun args => args.value + 1";
      args.value = 1;
    }
    {
      source = "fun args => args.value + 1";
      args.value = 2;
    }
  ];
  first = builtins.head outputs;
in
# Native map type errors are not catchable by tryEval. These assertions cover
# the batch API's own input admission, not the map-based baseline.
assert !batch || rejects (evalMany false);
assert !batch || rejects (applyMany { });
assert evalMany [ ] == [ ];
assert applyMany [ ] == [ ];
assert
  evalMany [
    "std.array.length [1, 2]"
    "let value = 1 in value"
    "let value = 2 in value"
  ] == [
    2
    1
    2
  ];
assert
  evalMany [
    {
      source = "import \"value.ncl\"";
      base = ./left/value.ncl;
    }
    {
      source = "import \"value.ncl\"";
      base = ./right/value.ncl;
    }
  ] == [
    1
    2
  ];
assert first.function "preserved" == "preserved";
assert first.path == opaque.path;
assert first.package.drvPath == drv.drvPath;
assert builtins.getContext first.string == builtins.getContext opaque.string;
assert
  builtins.tail outputs == [
    2
    3
  ];
assert rejects (evalMany [
  "1"
  "1 | String"
  "2"
]);
assert rejects (evalMany [
  "1"
  "let ="
]);
assert rejects (evalMany [
  "let hidden = 1 in hidden"
  "hidden"
]);
assert rejects (evalMany [
  {
    source = "import \"value.ncl\"";
    base = ./left/value.ncl;
  }
  "import \"value.ncl\""
]);
assert rejects (evalMany [
  "1"
  false
]);
assert rejects (applyMany [ { source = "fun args => args"; } ]);
assert rejects (applyMany [ { args = { }; } ]);
assert rejects (applyMany [
  {
    source = "fun args => args.value | Number";
    args.value = "wrong";
  }
]);
assert
  applyMany [
    {
      source = "fun args => import \"value.ncl\"";
      args = { };
      base = ./left/value.ncl;
    }
    {
      source = "fun args => import \"value.ncl\"";
      args = { };
      base = ./right/value.ncl;
    }
  ] == [
    1
    2
  ];
assert evalMany [ "3" ] == [ 3 ];
true
