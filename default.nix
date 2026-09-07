# Build wasm plugins for builtins.wasm.
#
# Produces .wasm files (wasm32-unknown-unknown) that work with the
# nix fork's builtins.wasm. Output is platform-independent — the
# same .wasm binaries run on any host architecture.
{
  lib,
  rustPlatform,
  lld,
  binaryen,
  nickel-wasm-vendor,
  craneLib ? null,
  plugin ? null,
  sharedParserArtifacts ? false,
}:
let
  pluginNames = [
    "nickel-plugin"
    "yaml-plugin"
    "ini-plugin"
  ];
  common = {
    pname = "nix-wasm-plugins";
    version = "0.1.0";

    # Documentation, wrappers, and fixtures do not affect the plugin binaries.
    # Nickel vendor sources enter separately through nickel-wasm-vendor below.
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./Cargo.toml
        ./Cargo.lock
        ./nix-wasm-rust
        ./nickel-plugin
        ./yaml-plugin
        ./ini-plugin
      ];
    };

    postUnpack = ''
      mkdir -p $sourceRoot/vendor
      # Cargo compares source timestamps with the restored dependency artifacts.
      cp -r --preserve=timestamps ${nickel-wasm-vendor}/core   $sourceRoot/vendor/nickel-lang-core
      cp -r --preserve=timestamps ${nickel-wasm-vendor}/parser $sourceRoot/vendor/nickel-lang-parser
      cp -r --preserve=timestamps ${nickel-wasm-vendor}/vector $sourceRoot/vendor/nickel-lang-vector
      chmod -R u+w $sourceRoot/vendor

      # Fix inter-crate paths: monorepo layout (../parser) -> vendor layout (../nickel-lang-parser)
      substituteInPlace $sourceRoot/vendor/nickel-lang-core/Cargo.toml \
        --replace-fail 'path = "../parser"'  'path = "../nickel-lang-parser"' \
        --replace-fail 'path = "../vector"'  'path = "../nickel-lang-vector"'
      substituteInPlace $sourceRoot/vendor/nickel-lang-parser/Cargo.toml \
        --replace-fail 'path = "../vector"'  'path = "../nickel-lang-vector"'

      # Strip dev-dependencies (nickel-lang-utils etc.) — not vendored for wasm builds
      sed -i '/^\[dev-dependencies\]/,/^\[/{/^\[dev-dependencies\]/d;/^\[/!d}' \
        $sourceRoot/vendor/nickel-lang-core/Cargo.toml

      # The same patches run in both stages. Keep their timestamps stable too.
      # A changed vendor pin or patch still changes the dependency derivation.
      touch -r ${nickel-wasm-vendor}/core/Cargo.toml $sourceRoot/vendor/nickel-lang-core/Cargo.toml
      touch -r ${nickel-wasm-vendor}/parser/Cargo.toml $sourceRoot/vendor/nickel-lang-parser/Cargo.toml
    '';

    CARGO_BUILD_TARGET = "wasm32-unknown-unknown";

    nativeBuildInputs = [
      lld
      binaryen
    ];

    doCheck = false; # Runtime integration checks use the Wasm host separately.
  };

  buildCommand = "cargo build --release --target wasm32-unknown-unknown --locked";
  installPlugins = ''
    mkdir -p $out
    for f in target/wasm32-unknown-unknown/release/*.wasm; do
      [ -f "$f" ] || continue
      name=$(basename "$f")
      # Skip deps artifacts (only top-level crate outputs)
      case "$name" in
        yaml_plugin.wasm|ini_plugin.wasm)
          wasm-opt -O3 --enable-bulk-memory -o "$out/$name" "$f"
          ;;
        nickel_plugin.wasm)
          # Nickel's malachite (big numbers) uses trunc_sat instructions
          wasm-opt -O3 --enable-bulk-memory --enable-nontrapping-float-to-int -o "$out/$name" "$f"
          ;;
      esac
    done
  '';

  cached = common // {
    cargoVendorDir = craneLib.vendorCargoDeps { cargoLock = ./Cargo.lock; };
    buildPhaseCargoCommand = buildCommand;
  };
  # Only the plugin workspace members become stubs. postUnpack adds the real,
  # pinned Nickel sources to both stages, so their compilation can be reused.
  cargoArtifacts = craneLib.buildDepsOnly (
    cached
    // lib.optionalAttrs (plugin != null && plugin != "nickel-plugin" && !sharedParserArtifacts) {
      pname = plugin;
      buildPhaseCargoCommand = buildCommand + selectedBuild;
    }
  );
  otherPlugins = lib.filter (name: name != plugin) pluginNames;
  selectedSource = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions (
      [
        ./Cargo.toml
        ./Cargo.lock
        ./nix-wasm-rust
        (./. + "/${plugin}")
      ]
      ++ map (name: ./. + "/${name}/Cargo.toml") otherPlugins
    );
  };
  selectedBuild =
    if plugin == "nickel-plugin" then
      # Preserve the vendor feature selection used by the shared dependency build.
      " --workspace --exclude yaml-plugin --exclude ini-plugin"
    else
      " --package ${plugin}";
  pluginFile = lib.replaceStrings [ "-" ] [ "_" ] plugin + ".wasm";
  selectedInstall = ''
    mkdir -p "$out"
    wasm-opt -O3 --enable-bulk-memory ${
      lib.optionalString (plugin == "nickel-plugin") "--enable-nontrapping-float-to-int"
    } \
      -o "$out/${pluginFile}" "target/wasm32-unknown-unknown/release/${pluginFile}"
  '';
in
assert builtins.isBool sharedParserArtifacts;
assert plugin == null || (craneLib != null && builtins.elem plugin pluginNames);
if craneLib == null then
  rustPlatform.buildRustPackage (
    common
    // {
      cargoLock.lockFile = ./Cargo.lock;
      buildPhase = buildCommand;
      installPhase = installPlugins;
    }
  )
else
  craneLib.mkCargoDerivation (
    cached
    // {
      inherit cargoArtifacts;
      doInstallCargoArtifacts = false;
      installPhaseCommand = installPlugins;
      passthru.fullSource = common.src;
    }
    // lib.optionalAttrs (plugin != null) {
      pname = plugin;
      src = selectedSource;
      # Cargo must discover every workspace target, including unselected crates.
      # Only their generated stubs enter this build, never their real source.
      postUnpack =
        common.postUnpack
        + lib.concatMapStrings (name: ''
          cp -r ${cargoArtifacts.src}/${name}/src "$sourceRoot/${name}/src"
        '') otherPlugins;
      buildPhaseCargoCommand = buildCommand + selectedBuild;
      installPhaseCommand = selectedInstall;
    }
  )
