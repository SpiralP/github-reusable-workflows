{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      makePackages = (pkgs: {
        replace-versions = pkgs.writeShellApplication {
          name = "replace-versions";
          runtimeInputs = with pkgs; [
            coreutils
            git
            gnugrep
            sd
          ];
          text = builtins.readFile ./replace-versions.sh;
        };

        semantic-release = pkgs.writeShellApplication {
          name = "semantic-release";
          runtimeInputs = with pkgs; [
            coreutils
            jq
          ];
          runtimeEnv =
            let
              nodeModules = pkgs.importNpmLock.buildNodeModules {
                inherit (pkgs) nodejs;
                npmRoot = lib.sourceByRegex ./. [
                  "^package-lock\.json$"
                  "^package\.json$"
                ];
              };
            in
            {
              NODE_PATH = "${nodeModules}/node_modules";
              BASE_CONFIG_PATH = ./semantic-release.json;
            };
          text = builtins.readFile ./semantic-release.sh;
        };

        update-nix-hashes = pkgs.writeShellApplication {
          name = "update-nix-hashes";
          runtimeInputs = with pkgs; [
            coreutils
            gnugrep
            nix
            prefetch-npm-deps
            sd
          ];
          text = builtins.readFile ./update-nix-hashes.sh;
        };
      });
    in
    builtins.foldl' lib.recursiveUpdate { } (builtins.map
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
          packages = makePackages pkgs;
          packagesWithDefault = packages // {
            default = pkgs.linkFarmFromDrvs "default" (builtins.attrValues packages);
          };
        in
        {
          devShells.${system} = packagesWithDefault;
          packages.${system} = packagesWithDefault;
        })
      lib.systems.flakeExposed);
}
