{
  description = "onix-wasm: WASM plugins for builtins.wasm (Nickel evaluator, YAML/INI parsers)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Verified host ABI, including string-context admission checks.
    nix-wasm-host.url = "github:onixcomputer/nix/388dea6acc4d45c7d47c9debcc105435ed0a995e";
    nickel-wasm-vendor = {
      url = "github:brittonr/nickel-wasm/wasm-vendor";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nickel-wasm-vendor,
      nix-wasm-host,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            pkgs = nixpkgs.legacyPackages.${system};
            inherit system;
          }
        );
    in
    {
      packages = forAllSystems (
        { pkgs, ... }:
        {
          default = pkgs.callPackage ./default.nix {
            inherit nickel-wasm-vendor;
          };
          wasm-plugins = pkgs.callPackage ./default.nix {
            inherit nickel-wasm-vendor;
          };
        }
      );

      # lib.<system> exposes the Nix wrappers (evalNickelFileWith, fromYAML, etc.)
      lib = forAllSystems (
        { system, ... }:
        import ./nix/wasm.nix {
          plugins = self.packages.${system}.wasm-plugins;
        }
      );

      checks = forAllSystems (
        { pkgs, system, ... }:
        {
          nickel-batch =
            pkgs.runCommand "nickel-batch"
              {
                nativeBuildInputs = [ nix-wasm-host.packages.${system}.nix-cli ];
              }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                export NIX_CONFIG="experimental-features = nix-command wasm-builtin"
                nix eval --store "$TMPDIR/store" --json --impure --file ${self}/tests/batch.nix \
                  --apply 'f: f { plugins = ${self.packages.${system}.wasm-plugins}; }' > single.json
                nix eval --store "$TMPDIR/store" --json --impure --file ${self}/tests/batch.nix \
                  --apply 'f: f { plugins = ${self.packages.${system}.wasm-plugins}; batch = true; }' > batch.json
                grep -qx true single.json
                grep -qx true batch.json
                nix eval --store "$TMPDIR/store" --json --impure --file ${self}/tests/map.nix \
                  --apply 'f: f { plugins = ${self.packages.${system}.wasm-plugins}; }' > map-baseline.json
                nix eval --store "$TMPDIR/store" --json --impure --file ${self}/tests/map.nix \
                  --apply 'f: f { plugins = ${self.packages.${system}.wasm-plugins}; prepared = true; }' > map.json
                grep -qx true map-baseline.json
                grep -qx true map.json
                touch "$out"
              '';

          plugin-source-scope = pkgs.runCommand "plugin-source-scope" { } ''
            source=${self.packages.${system}.wasm-plugins.src}
            test -f "$source/Cargo.toml"
            test -f "$source/Cargo.lock"
            for crate in nix-wasm-rust nickel-plugin yaml-plugin ini-plugin; do
              test -f "$source/$crate/Cargo.toml"
              test -f "$source/$crate/src/lib.rs"
            done
            test ! -e "$source/README.md"
            test ! -e "$source/flake.nix"
            test ! -e "$source/flake.lock"
            test ! -e "$source/nix"
            test ! -e "$source/tests"
            test ! -e "$source/vendor"
            touch "$out"
          '';

          nickel-wasm-josh-sync-config =
            pkgs.runCommand "onix-wasm-nickel-wasm-josh-sync-config"
              {
                nativeBuildInputs = [
                  pkgs.rustc
                  pkgs.stdenv.cc
                ];
              }
              ''
                rustc --edition=2024 --test ${./scripts/check-nickel-wasm-josh-sync.rs} -o nickel-wasm-josh-sync-tests
                ./nickel-wasm-josh-sync-tests
                rustc --edition=2024 ${./scripts/check-nickel-wasm-josh-sync.rs} -o nickel-wasm-josh-sync
                ./nickel-wasm-josh-sync --lock-file ${./flake.lock} --filter-file ${./josh/nickel-wasm.josh} --config-only
                touch $out
              '';
        }
      );

      devShells = forAllSystems (
        { pkgs, ... }:
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              rustup
              lld
              binaryen
            ];
          };
        }
      );
    };
}
