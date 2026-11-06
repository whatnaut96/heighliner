{
  description = "Flake for beacon cross-compilation and development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.elixir
            pkgs.erlang_28
            pkgs.rebar3
            pkgs.elixir-ls
          ];
        };

      }
    );
}
