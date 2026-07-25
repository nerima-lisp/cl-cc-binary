{
  description = "cl-cc-binary: object-file (ELF/Mach-O) emission for the cl-cc Common Lisp compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # Test-only: cl-weave is the test framework. Pulled as a plain source tree
    # and handed to the test runner via CL_CC_BINARY_CL_WEAVE_ROOT.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave";
      flake = false;
    };
    # Runtime: optional structured-logging sink for Mach-O/ELF/PE emission
    # diagnostics (silent unless a caller binds *BINARY-LOGGER*). Pulled as a
    # plain source tree and handed to both the compile check and the test
    # runner via CL_CC_BINARY_CL_LOG_KIT_ROOT.
    cl-log-kit = {
      url = "github:nerima-lisp/cl-log-kit";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-weave,
      cl-log-kit,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems =
        function: nixpkgs.lib.genAttrs systems (system: function (import nixpkgs { inherit system; }));
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.sbcl ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);

      packages = forAllSystems (pkgs: {
        default = pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-cc-binary";
          version = "0.1.0";
          src = self;
          nativeBuildInputs = [ pkgs.sbcl ];
          buildPhase = ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            export CL_SOURCE_REGISTRY="${cl-log-kit}//"
            sbcl --script scripts/run-compile-check.lisp
          '';
          installPhase = ''
            mkdir -p "$out/share/common-lisp/source/cl-cc-binary"
            cp -R . "$out/share/common-lisp/source/cl-cc-binary"
          '';
          meta = {
            description = "cl-cc object-file (ELF/Mach-O) emission";
            homepage = "https://github.com/nerima-lisp/cl-cc-binary";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.unix;
          };
        };
      });

      checks = forAllSystems (pkgs: {
        compile = self.packages.${pkgs.stdenv.hostPlatform.system}.default;

        test = pkgs.stdenvNoCC.mkDerivation {
          name = "cl-cc-binary-test";
          src = self;
          nativeBuildInputs = [ pkgs.sbcl ];
          buildPhase = ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            export CL_SOURCE_REGISTRY="${cl-weave}//:${cl-log-kit}//"
            sbcl --script run-tests.lisp
          '';
          installPhase = "touch $out";
        };
      });
    };
}
