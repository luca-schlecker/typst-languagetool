{
  description = "LanguageTool Integration for Typst for spell and grammer check";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    crane.url = "github:ipetkov/crane";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        inherit (pkgs) lib;

        craneLib = crane.mkLib pkgs;
        src = craneLib.cleanCargoSource ./.;

        # Common arguments can be set here to avoid repeating them later
        commonArgs = {
          inherit src;
          strictDeps = true;
          nativeBuildInputs = with pkgs; [ pkg-config makeWrapper ];
          buildInputs = with pkgs; [ openssl ];
          PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
          JAR_LOCATION = "${jar}/share/${jar.pname}-${jar.version}.jar";
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        individualCrateArgs = commonArgs // {
          inherit cargoArtifacts;
          inherit (craneLib.crateNameFromCargoToml { inherit src; }) version;
        };

        fileSetForCrate =
          crate:
          lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [
              ./Cargo.toml
              ./Cargo.lock
              (craneLib.fileset.commonCargoSources ./cli)
              (craneLib.fileset.commonCargoSources ./lsp)
              (craneLib.fileset.commonCargoSources ./src)
              (craneLib.fileset.commonCargoSources ./lt-world)
            ];
          };

        # Build the top-level crates of the workspace as individual derivations.
        # This allows consumers to only depend on (and build) only what they need.
        # Though it is possible to build the entire workspace as a single derivation,
        # so this is left up to you on how to organize things
        #
        # Note that the cargo workspace must define `workspace.members` using wildcards,
        # otherwise, omitting a crate (like we do below) will result in errors since
        # cargo won't be able to find the sources for all members.
        jar = pkgs.maven.buildMavenPackage rec {
          pname = "typst-languagetool";
          version = "1";
          src = ./maven;
          mvnHash = "sha256-vn6BlDFXrTRVnbJtrbvIHqdEdxy5m7DLGzi37Ai183c=";
          installPhase = ''
            runHook preInstall

            mkdir -p $out/share/
            install -Dm644 target/${pname}-${version}-jar-with-dependencies.jar $out/share/${pname}-${version}.jar

            runHook postInstall
          '';
        };
        cli = craneLib.buildPackage (
          individualCrateArgs
          // {
            pname = "typst-languagetool";
            cargoExtraArgs = "-p cli --features jar";
            src = fileSetForCrate ./cli;
            postFixup = ''
              wrapProgram $out/bin/typst-languagetool \
                --set PATH ${lib.makeBinPath (with pkgs; [ openjdk which ])}
            '';
          }
        );
        lsp = craneLib.buildPackage (
          individualCrateArgs
          // {
            pname = "typst-languagetool-lsp";
            cargoExtraArgs = "-p lsp --features jar";
            src = fileSetForCrate ./lsp;
            postFixup = ''
              wrapProgram $out/bin/typst-languagetool-lsp \
                --set PATH ${lib.makeBinPath (with pkgs; [ openjdk which ])}
            '';
          }
        );
      in
      {
        packages = {
          inherit cli lsp;
        };

        apps = {
          cli = flake-utils.lib.mkApp {
            drv = cli;
          };
          lsp = flake-utils.lib.mkApp {
            drv = lsp;
          };
        };

        devShells.default = craneLib.devShell {};
      }
    );
}
