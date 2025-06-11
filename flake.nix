{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      makePackages = (system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
        in
        rec {
          default = pkgs.linkFarmFromDrvs "default" [
            semantic-release
            update-nix-hashes
          ];

          semantic-release = pkgs.writeShellApplication {
            name = "semantic-release";
            text =
              let
                nodeModules = pkgs.importNpmLock.buildNodeModules {
                  inherit (pkgs) nodejs;
                  npmRoot = lib.sourceByRegex ./. [
                    "^package-lock\.json$"
                    "^package\.json$"
                  ];
                };
              in
              ''
                export NODE_PATH=${nodeModules}/node_modules
                ${nodeModules}/node_modules/.bin/semantic-release --extends ${./semantic-release.json} "$@"
              '';
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
              test -z "$OLD_HASH" && exit 1
              test -z "$NEW_HASH" && exit 1
              test "$OLD_HASH" = "$NEW_HASH" && exit 0

              if ! grep -q "$OLD_HASH" flake.nix; then
                echo "couldn't find old hash in flake.nix"
                exit 1
              fi
              sd --fixed-strings "$OLD_HASH" "$NEW_HASH" flake.nix
              if ! grep -q "$NEW_HASH" flake.nix; then
                echo "couldn't find new hash in flake.nix"
                exit 1
              fi
            '';
          };
        }
      );
    in
    builtins.foldl' lib.recursiveUpdate { } (builtins.map
      (system: {
        devShells.${system} = makePackages system;
        packages.${system} = makePackages system;
      })
      lib.systems.flakeExposed);
}
