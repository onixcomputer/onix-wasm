{
  description = "onix-wasm: WASM plugins for builtins.wasm (Nickel evaluator, YAML/INI parsers)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nickel-wasm-vendor = {
      url = "github:brittonr/nickel-wasm/wasm-vendor";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, nickel-wasm-vendor, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = nixpkgs.legacyPackages.${system};
        inherit system;
      });
    in
    {
      packages = forAllSystems ({ pkgs, ... }: {
        default = pkgs.callPackage ./default.nix {
          inherit nickel-wasm-vendor;
        };
        wasm-plugins = pkgs.callPackage ./default.nix {
          inherit nickel-wasm-vendor;
        };
      });

      # lib.<system> exposes the Nix wrappers (evalNickelFileWith, fromYAML, etc.)
      lib = forAllSystems ({ system, ... }: 
        import ./nix/wasm.nix {
          plugins = self.packages.${system}.wasm-plugins;
        }
      );

      devShells = forAllSystems ({ pkgs, ... }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            rustup
            lld
            binaryen
          ];
        };
      });
    };
}
