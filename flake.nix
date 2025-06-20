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
            replace-versions
            semantic-release
            update-nix-hashes
          ];

          replace-versions = pkgs.writeShellApplication {
            name = "replace-versions";
            runtimeInputs = with pkgs; [
              coreutils
              gnugrep
              sd
            ];
            text = ''
              NEW_VERSION="$1"
              test -z "$NEW_VERSION" && echo 'NEW_VERSION missing' && exit 1
              test -z "$REPLACE_FILES" && echo 'REPLACE_FILES missing' && exit 1
              test -z "$PACKAGE_NAME" && echo 'PACKAGE_NAME missing' && exit 1

              IFS=$'\n'
              for path in $REPLACE_FILES; do
                echo "Replacing version in $path"
                filename="$(basename "$path")"
                if test "$filename" = "Cargo.toml" || test "$filename" = "Cargo.lock"; then
                  sd \
                    "(name = \"''${PACKAGE_NAME}[^\"]*\"\nversion = \")[^\"]+(\")" \
                    "\''${1}''${NEW_VERSION}\''${2}" \
                    "$path"
                elif test "$filename" = "package.json" || test "$filename" = "package-lock.json"; then
                  sd \
                    "(\s+\"name\": \"''${PACKAGE_NAME}[^\"]*\",\n\s+\"version\": \")[^\"]+(\")" \
                    "\''${1}''${NEW_VERSION}\''${2}" \
                    "$path"
                else
                  echo "Unsupported filename: $filename"
                  exit 1
                fi
              done
            '';
          };

          semantic-release = pkgs.writeShellApplication {
            name = "semantic-release";
            runtimeInputs = with pkgs; [
              coreutils
              jq
            ];
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
                merged_extends="$(mktemp --suffix .json)"
                trap 'rm -f "$merged_extends"' EXIT

                cat ${./semantic-release.json} > "$merged_extends"

                if test -n "''${REPLACE_FILES-}"; then
                  temp1="$(mktemp)"
                  jq -n \
                    --arg script "nix run github:SpiralP/github-reusable-workflows/''${WORKFLOW_SHA-main}#replace-versions --print-build-logs --" \
                    --arg assets "$REPLACE_FILES" \
                    '{
                      plugins: [
                        [
                          "@semantic-release/exec",
                          {
                            prepareCmd: "\($script) ''${nextRelease.version}"
                          }
                        ],
                        [
                          "@semantic-release/git",
                          {
                            assets: $assets | split("\n") | map(select(length > 0)),
                            message: "chore(release): ''${nextRelease.version}\n\n''${nextRelease.notes}"
                          }
                        ]
                      ]
                    }' > "$temp1"
                  
                  temp2="$(mktemp)"
                  jq -s \
                    '(.[0] * .[1]) * { plugins: (.[0].plugins + .[1].plugins) }' \
                    "$merged_extends" \
                    "$temp1" \
                    > "$temp2"
                  rm -f "$temp1"

                  cat "$temp2" > "$merged_extends"
                  rm -f "$temp2"
                fi

                if test -n "''${EXTENDS-}"; then
                  temp1="$(mktemp)"
                  jq -s \
                    '(.[0] * .[1]) * { plugins: (.[0].plugins + .[1].plugins) }' \
                    "$merged_extends" \
                    "$EXTENDS" \
                    > "$temp1"
                  cat "$temp1" > "$merged_extends"
                  rm -f "$temp1"
                fi
                unset EXTENDS

                jq . "$merged_extends"

                export NODE_PATH=${nodeModules}/node_modules
                ${nodeModules}/node_modules/.bin/semantic-release --extends "$merged_extends" "$@"
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
