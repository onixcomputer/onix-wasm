{ plugins }:
let
  wasm = import ../nix/wasm.nix { inherit plugins; };
  rejects = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
in
assert wasm.fromINI "[section]\nkey=value\n" == { section.key = "value"; };
assert wasm.fromYAML "answer: true\n" == [ { answer = true; } ];
assert wasm.fromYAML (wasm.toYAML [ { answer = true; } ]) == [ { answer = true; } ];
assert rejects (wasm.fromINI "[unterminated");
assert rejects (wasm.fromYAML "[unterminated");
true
