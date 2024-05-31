{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
  };

  outputs = { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      makePackages = (pkgs:
        let
          rustManifest = lib.importTOML ./Cargo.toml;
          nodeManifest = lib.importJSON ./package.json;
        in
        {
          rust = pkgs.rustPlatform.buildRustPackage {
            name = rustManifest.package.name;
            version = rustManifest.package.version;

            src = lib.sourceByRegex ./. [
              "^\.cargo(/.*)?$"
              "^build\.rs$"
              "^Cargo\.(lock|toml)$"
              "^src(/.*)?$"
            ];

            cargoLock = {
              lockFile = ./Cargo.lock;
              outputHashes = { };
            };

            buildInputs = with pkgs; [
              openssl
            ];

            nativeBuildInputs = with pkgs; [
              pkg-config
            ];
          };

          node = pkgs.buildNpmPackage {
            name = nodeManifest.name;
            version = nodeManifest.version;

            src = lib.sourceByRegex ./. [
              "^package-lock\.json$"
              "^package\.json$"
              "^web(/.*)?$"
            ];

            npmDepsHash = "sha256-yoF9h/rDPtpU/4DqZO/pwICNOxgG+dPTk/Vv1ZNVM8s=";
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
            text = ''
              NPM_ATTRIBUTE="$1"
              PACKAGE_LOCK_PATH="$2"

              OLD_HASH="$(nix eval --no-update-lock-file --raw ".#$NPM_ATTRIBUTE.npmDepsHash")"
              NEW_HASH="$(prefetch-npm-deps "$PACKAGE_LOCK_PATH" 2>/dev/null)"

              echo "$OLD_HASH" "$NEW_HASH"
              test "$OLD_HASH" = "$NEW_HASH" && exit 0

              grep -q "$OLD_HASH" flake.nix || { echo "couldn't find old hash in flake.nix"; exit 1; }
              sd --fixed-strings "$OLD_HASH" "$NEW_HASH" flake.nix
              grep -q "$NEW_HASH" flake.nix || { echo "couldn't find new hash in flake.nix"; exit 1; }
            '';
          };
        }
      );
    in
    builtins.foldl' lib.recursiveUpdate { } (builtins.map
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };

          packages = makePackages pkgs;
        in
        {
          devShells.${system} = packages // {
            default =
              let
                allDrvsIn = (name:
                  lib.lists.flatten (
                    builtins.map
                      (drv: drv.${name} or [ ])
                      (builtins.attrValues packages)
                  ));
              in
              pkgs.mkShell {
                name = "github-reusable-workflows-dev-shell";
                packages = with pkgs; [
                  clippy
                  rustfmt
                  rust-analyzer
                ];
                buildInputs = allDrvsIn "buildInputs";
                nativeBuildInputs = allDrvsIn "nativeBuildInputs";
                propagatedBuildInputs = allDrvsIn "propagatedBuildInputs";
                propagatedNativeBuildInputs = allDrvsIn "propagatedNativeBuildInputs";
              };
          };
          packages.${system} = packages // {
            default = pkgs.linkFarmFromDrvs "github-reusable-workflows-link-farm" (builtins.attrValues packages);
          };
        })
      lib.systems.flakeExposed);
}
