{
  description = "Flake for heighliner development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        beamPkgs = pkgs.beam29Packages;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            beamPkgs.elixir_1_20
            beamPkgs.erlang
            pkgs.rebar3
          ];
        };
      }
    );
}
