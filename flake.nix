{
  description = "onix-wasm: WASM plugins for builtins.wasm (Nickel evaluator, YAML/INI parsers)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane/b556d7bbae5ff86e378451511873dfd07e4504cd";
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
      crane,
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
        { pkgs, system, ... }:
        {
          default = self.packages.${system}.wasm-plugins;
          wasm-plugins = self.packages.${system}.wasm-plugins-preinitialized;
          # Retain the previous cached workspace build for controlled comparisons.
          wasm-plugins-monolithic = pkgs.callPackage ./default.nix {
            inherit nickel-wasm-vendor;
            craneLib = crane.mkLib pkgs;
          };
          nickel-plugin = self.packages.${system}.wasm-plugins-monolithic.override {
            plugin = "nickel-plugin";
          };
          yaml-plugin = self.packages.${system}.wasm-plugins-monolithic.override {
            plugin = "yaml-plugin";
          };
          ini-plugin = self.packages.${system}.wasm-plugins-monolithic.override {
            plugin = "ini-plugin";
          };
          wasm-plugins-uninitialized = pkgs.callPackage ./nix/bundle-plugins.nix {
            nickelPlugin = self.packages.${system}.nickel-plugin;
            yamlPlugin = self.packages.${system}.yaml-plugin;
            iniPlugin = self.packages.${system}.ini-plugin;
          };
          wasm-plugins-preinitialized = pkgs.callPackage ./nix/preinitialize.nix {
            plugins = self.packages.${system}.wasm-plugins-uninitialized;
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
          nickel-batch = pkgs.callPackage ./nix/check-plugin.nix {
            name = "nickel-batch";
            source = self;
            nixHost = nix-wasm-host.packages.${system}.nix-cli;
            plugins = self.packages.${system}.wasm-plugins-uninitialized;
          };
          nickel-preinitialized = pkgs.callPackage ./nix/check-plugin.nix {
            name = "nickel-preinitialized";
            source = self;
            nixHost = nix-wasm-host.packages.${system}.nix-cli;
            plugins = self.packages.${system}.wasm-plugins-preinitialized;
          };

          nickel-preinitialization-controls = pkgs.callPackage ./nix/check-preinitialize.nix {
            plugins = self.packages.${system}.wasm-plugins-uninitialized;
            initialized = self.packages.${system}.wasm-plugins-preinitialized;
            forbiddenConstructor = ./tests/preinit-external.wat;
          };

          plugin-build-scope = pkgs.callPackage ./nix/check-plugin-scope.nix {
            plugins = self.packages.${system}.wasm-plugins-uninitialized;
            monolithic = self.packages.${system}.wasm-plugins-monolithic;
          };

          plugin-dependency-cache = pkgs.callPackage ./nix/check-dependency-cache.nix {
            plugins = self.packages.${system}.wasm-plugins-uninitialized;
          };

          plugin-source-scope = pkgs.runCommand "plugin-source-scope" { } ''
            source=${self.packages.${system}.wasm-plugins-uninitialized.src}
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
