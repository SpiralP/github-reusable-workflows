{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # `build-and-download.sh` relies on gh >= 2.87.0, which prints the
    # dispatched run's URL on stdout in non-TTY mode (cli/cli#12695,
    # released 2026-02-18). nixos-25.11 ships gh 2.83.2, so pull just
    # gh from unstable via an overlay below.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { nixpkgs, nixpkgs-unstable, ... }:
    let
      inherit (nixpkgs) lib;

      makePackages = (pkgs: pkgsUnstable: {
        release-success = pkgs.writeShellApplication {
          name = "release-success";
          runtimeInputs = with pkgs; [
            coreutils
          ];
          text = builtins.readFile ./release-success.sh;
        };

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

        build-and-download = pkgs.writeShellApplication {
          name = "build-and-download";
          runtimeInputs = with pkgs; [
            coreutils
            findutils
            pkgsUnstable.gh
            git
          ];
          text = builtins.readFile ./build-and-download.sh;
        };

        semantic-release = pkgs.writeShellApplication {
          name = "semantic-release";
          runtimeInputs = with pkgs; [
            coreutils
            pkgsUnstable.gh
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
              MERGE_JQ_PATH = ./merge.jq;
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
          pkgsUnstable = nixpkgs-unstable.legacyPackages.${system};
          packages = makePackages pkgs pkgsUnstable;
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
