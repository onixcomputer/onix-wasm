{ plugins }:
let
  wasm = import ../nix/wasm.nix { inherit plugins; };
  rejects = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
  result = wasm.evalNickel ''
    {
      "é" = "unicode",
      z = "last",
      nested = { z = false, a = true },
      a2 = 2,
      a10 = 1,
      "" = "empty",
      hidden | not_exported = fun value => value,
    }
  '';
  expected = {
    "" = "empty";
    a10 = 1;
    a2 = 2;
    nested = {
      a = true;
      z = false;
    };
    z = "last";
    "é" = "unicode";
  };
in
assert result == expected;
assert
  builtins.attrNames result == [
    ""
    "a10"
    "a2"
    "nested"
    "z"
    "é"
  ];
assert result.nested.a && !result.nested.z;
assert !(result ? hidden);
assert wasm.evalNickel "{}" == { };
assert
  wasm.evalNickelMap "fun args => { z = args.value, a = args.value }" [
    { value = 1; }
    { value = 2; }
  ] == [
    {
      a = 1;
      z = 1;
    }
    {
      a = 2;
      z = 2;
    }
  ];
assert rejects (wasm.evalNickel "{ missing | Number }");
assert rejects (wasm.evalNickel "{ z = 1, a | Number = \"wrong\" }");
assert rejects (wasm.evalNickel "{ z = 1, a = fun value => value }");
true
