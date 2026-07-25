{
  description = "cl-cc binary-format emitters — Mach-O, ELF, PE and WebAssembly module bytes";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Sibling packages are pinned to a release tag and pulled with
    # `flake = false` (DEPENDENCY_POLICY.md). The tag is what keeps an upstream
    # push to main from breaking this repository's CI without warning;
    # `flake = false` is what keeps their input closures out of this lock,
    # since all that is wanted here is the source tree ASDF reads.
    #
    # They carry no `inputs.nixpkgs.follows`. The reason the standard requires
    # it — one nixpkgs per input otherwise — cannot arise for an input whose
    # own flake is never evaluated, and stating it anyway makes Nix print
    # "has an override for a non-existent input 'nixpkgs'" on every command.

    # Runtime: optional structured-logging sink for Mach-O/ELF/PE emission
    # diagnostics. Silent unless a caller binds CL-CC/BINARY:*BINARY-LOGGER*.
    # This is the system's only dependency.
    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit/v1.0.0";
      flake = false;
    };

    # Test-only: the org's test framework.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.0.0";
      flake = false;
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      cl-log-kit,
      cl-weave,
      treefmt-nix,
      ...
    }:
    let
      # Only the two platforms that are actually verified: CI builds
      # x86_64-linux, and development machines are Darwin arm64 so every local
      # `nix flake check` exercises aarch64-darwin. aarch64-linux and
      # x86_64-darwin are declared by nobody who tests them, so they are not
      # declared here either (ADR-0078). ci.yml does not pass --all-systems.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # What the shipped system needs: cl-log-kit and this tree.
      runtimeRegistry = "${cl-log-kit}//:${self}//";
      # What the test system additionally needs.
      testRegistry = "${cl-weave}//:${runtimeRegistry}";

      # Single source of truth for the package version: the `:version` form in
      # cl-cc-binary.asd. A release edits that one line and every Nix package
      # follows. Nix regexes are whole-string anchored and `.` never spans
      # newlines, so the version is extracted line-by-line rather than with one
      # multi-line match.
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile ./cl-cc-binary.asd);
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "[[:space:]]*:version \"[^\"]*\"" line != null) lines
          );
        in
        builtins.head (builtins.match "[[:space:]]*:version \"([^\"]*)\"" versionLine);

      # treefmt drives `nix fmt` and the `checks.<system>.formatting` gate.
      # Scope is Nix only: nixfmt is a zero-footgun, low-diff formatter,
      # whereas a YAML formatter mangles the GitHub Actions `on:` key and
      # Markdown reformatting would churn the whole docs tree.
      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        rec {
          cl-cc-binary = pkgs.stdenvNoCC.mkDerivation {
            pname = "cl-cc-binary";
            inherit version;
            src = self;
            nativeBuildInputs = [ pkgs.sbcl ];
            # Compiles and loads the shipped system without the test framework
            # present, so a stray dependency on cl-weave from src/ fails here
            # rather than at a consumer's site.
            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              export CL_SOURCE_REGISTRY="${runtimeRegistry}"
              sbcl --script scripts/run-compile-check.lisp
              runHook postBuild
            '';
            installPhase = ''
              runHook preInstall
              mkdir -p "$out/share/common-lisp/source/cl-cc-binary"
              cp -R . "$out/share/common-lisp/source/cl-cc-binary"
              runHook postInstall
            '';
            meta = {
              description = "cl-cc binary-format emitters — Mach-O, ELF, PE and WebAssembly module bytes";
              homepage = "https://github.com/nerima-lisp/cl-cc-binary";
              license = pkgs.lib.licenses.mit;
              platforms = pkgs.lib.platforms.unix;
            };
          };
          default = cl-cc-binary;

          # Rendered documentation site (Material for MkDocs).
          # Builds fully offline: Material bundles all of its assets, so no
          # network access is required inside the sandbox. --strict promotes a
          # broken link or a page missing from the nav to a build failure.
          #
          # The fileset roots at ./. rather than ./docs because
          # docs/src/changelog.md is a pymdownx.snippets include of the root
          # CHANGELOG.md, and mkdocs is invoked from the repository root so
          # that snippets' base_path of "." resolves to it.
          docs = pkgs.stdenvNoCC.mkDerivation {
            pname = "cl-cc-binary-docs";
            inherit version;
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                ./docs/mkdocs.yml
                ./docs/src
                ./CHANGELOG.md
              ];
            };
            nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
            buildPhase = ''
              runHook preBuild
              mkdocs build --strict --config-file docs/mkdocs.yml --site-dir "$out"
              runHook postBuild
            '';
            dontInstall = true;
            meta = {
              description = "Rendered MkDocs (Material) documentation for cl-cc-binary";
              homepage = "https://github.com/nerima-lisp/cl-cc-binary";
              license = pkgs.lib.licenses.mit;
            };
          };
        }
      );

      # `nix fmt` entry point.
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching. Add a check here rather than a job in ci.yml.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # The cl-weave suite. `sbcl --script` and nothing before it: SBCL
          # acts on --non-interactive before it reaches the script, so
          # `sbcl --noinform --non-interactive --script run-tests.lisp` — what
          # this check used to run — exits 0 without loading anything.
          default =
            pkgs.runCommand "cl-cc-binary-tests"
              {
                nativeBuildInputs = [
                  pkgs.sbcl
                  pkgs.coreutils
                ];
                CL_SOURCE_REGISTRY = testRegistry;
              }
              ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME" "$out"
                timeout 300 sbcl --script ${self}/run-tests.lisp
                touch "$out/passed"
              '';

          # The shipped system compiles and loads without cl-weave present.
          compile = self.packages.${system}.cl-cc-binary;

          # Fails `nix flake check` when any tracked Nix file is unformatted,
          # turning the formatter into an enforced gate.
          formatting = treefmtEval.${system}.config.build.check self;

          # Without this the docs are only ever built by the publish workflow,
          # which runs after a merge to main — so a broken link surfaces as a
          # failed deploy rather than as a failed pull request.
          docs = self.packages.${system}.docs;
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          test = pkgs.writeShellApplication {
            name = "cl-cc-binary-test";
            runtimeInputs = [
              pkgs.sbcl
              pkgs.coreutils
            ];
            text = ''
              export CL_SOURCE_REGISTRY="${testRegistry}"
              exec timeout 300 sbcl --script ${self}/run-tests.lisp
            '';
          };
        in
        {
          default = {
            type = "app";
            program = "${test}/bin/cl-cc-binary-test";
          };
          test = {
            type = "app";
            program = "${test}/bin/cl-cc-binary-test";
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.sbcl ];
            CL_SOURCE_REGISTRY = testRegistry;
          };
        }
      );
    };
}
