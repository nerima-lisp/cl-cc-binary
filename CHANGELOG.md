# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!--
Heading format is fixed across the org:

    ## [X.Y.Z] - YYYY-MM-DD

release.yml extracts the section matching the pushed tag as the GitHub Release
body, so a heading that deviates makes the release fail. Keep `## [Unreleased]`
at the top at all times.

Use only these subsection names, and omit the ones that are empty:
Added / Changed / Deprecated / Removed / Fixed / Security
-->

## [Unreleased]

### Added

- Documentation site under `docs/`, published to
  <https://nerima-lisp.github.io/cl-cc-binary/> by the `docs` workflow and
  built with `mkdocs --strict` as part of `nix flake check`.
- `docs`, `release` and `flake-update` workflows, plus the shared
  `.github/actions/nix-setup` composite action.
- `checks.formatting` (treefmt/nixfmt) and `checks.docs` in the flake, and an
  `apps.test` entry point.
- This changelog.

### Changed

- Test files are named after the source file they cover
  (`t/<source>-test.lisp`), per `CODING_STANDARD.md`. The `<subject>-tests.lisp`
  names are gone; where a name did not identify a source file it was replaced
  by one that does, e.g. `binary-buffer-tests.lisp` →
  `macho-buffer-test.lisp`. No test content changed.
- `(:use :cl)` is now `(:use #:cl)`, and the `:binary` nickname was removed.
  Nothing referenced the nickname; callers that want a short name can declare
  it with `:local-nicknames`.
- The ELF, Mach-O and PE emitters were split into per-format modules
  (`elf-emit-executable`, `elf-emit-relocatable`, `macho-build-assemble`,
  `macho-build-compression`, `pe-tables`, `pe-finalize`), with
  `binary-struct` and `binary-writer` extracted as shared primitives. No
  exported symbol changed.
- The test system moved from a separate `cl-cc-binary-test.asd` into
  `cl-cc-binary.asd` as `cl-cc-binary/test`, and the suite moved from `tests/`
  to `t/`. `run-tests.lisp` is now at the repository root.
- Sibling systems are located through `CL_SOURCE_REGISTRY` instead of the
  `CL_CC_BINARY_CL_WEAVE_ROOT` and `CL_CC_BINARY_CL_LOG_KIT_ROOT` variables,
  which are gone.
- `flake.nix` tracks `nixos-unstable`, pins `cl-weave` and `cl-log-kit` to
  `v1.0.0`, declares `x86_64-linux` and `aarch64-darwin` only, and reads the
  version from `cl-cc-binary.asd` rather than repeating it.
- Every `uses:` in CI carries a `# vX` comment alongside its commit SHA.

### Fixed

- `align-up`, `serialize-uint32-le`, `serialize-uint64-le` and
  `serialize-bytes` declared `(safety 0)`, which made SBCL trust their type
  declarations without checking them. They now declare `(safety 1)`, matching
  `serialize-string-16` in the same file.
- The flake ran its test and compile checks as
  `sbcl --noinform --non-interactive --script ...`. SBCL processes
  `--non-interactive` before reaching the script, so both checks exited 0
  without loading anything: `nix flake check` had been green while running no
  tests at all.

## [0.1.0] - 2026-07-23

### Added

- Initial extraction from the `cl-cc` monorepo as a standalone system:
  byte buffers and constant pools, Mach-O writers including universal/fat
  binaries and compression metadata, ELF executable and relocatable writers,
  PE tables and finalization, WebAssembly module bytes, DWARF and DWARF/EH
  sections, GOT/PLT construction, ICF, W^X memory protection, and patchable
  function entries. Exported from the `cl-cc/binary` package.
- Optional structured diagnostics via `cl-cc/binary:*binary-logger*`, backed
  by [cl-log-kit](https://github.com/nerima-lisp/cl-log-kit). The default `nil`
  logger keeps the library silent.
- A [cl-weave](https://github.com/nerima-lisp/cl-weave) test suite.
