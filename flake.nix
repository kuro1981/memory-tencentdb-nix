{
  description = "Nix packaging for @tencentdb-agent-memory/memory-tencentdb — local long-term memory plugin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      overlay = final: prev: {
        memory-tencentdb = final.callPackage ./package.nix {
          # 上流は node >= 18 を要求する。nixpkgs 既定の node が上がっても
          # 追随して壊れないよう明示的に固定する。
          nodejs = final.nodejs_22;
        };
      };
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ overlay ];
        };
      in
      {
        packages = {
          default = pkgs.memory-tencentdb;
          inherit (pkgs) memory-tencentdb;
        };

        formatter = pkgs.nixpkgs-fmt;

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            memory-tencentdb
            nodejs_22
            nixpkgs-fmt
            gh
            jq
          ];
        };
      }) // {
      overlays.default = overlay;
    };
}
