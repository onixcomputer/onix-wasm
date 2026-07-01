{
  description = "onix-wasm: WASM plugins for builtins.wasm (Nickel evaluator, YAML/INI parsers)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
        { pkgs, ... }:
        {
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
