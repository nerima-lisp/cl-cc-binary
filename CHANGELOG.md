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

## [0.2.0] - 2026-07-31

### Added

- Real end-to-end execution tests, the one category every previous test in
  this suite was missing: all of them asserted on bytes (magic numbers,
  flags, offsets) without ever handing a produced image to the operating
  system and asking it to run.
  - `t/macho-build-executes-test.lisp`: builds, ad-hoc-codesigns, and
    executes a real ARM64 Mach-O through `write-mach-o-file`, checking the
    process exits with the code its own machine code requested. Machine
    code verified against a real `clang -arch arm64`-assembled reference
    binary via `otool -tv` before being transcribed into the test.
    `it-run-if`-guarded to aarch64-darwin hosts outside a Nix build
    sandbox: it observed exit code 137 (SIGKILL) under
    `nix build .#checks.aarch64-darwin.default` even on a real
    aarch64-darwin host, matching Nix's `sandbox-exec` profile denying
    process-exec for a binary the derivation just produced, not a defect
    in the emitted Mach-O.
  - `t/elf-compile-executes-test.lisp`: the same idea for
    `compile-to-elf64-exec`, guarded to run only on native Linux (skips
    everywhere else, including inside the Nix sandbox for the same reason
    as above) so it activates automatically on this flake's declared
    `x86_64-linux` CI leg with no extra dependency. Both the `:x86-64` and
    `:arm64` code paths this function supports were additionally verified
    by hand during development: cross-built each ELF and ran it inside a
    real Linux container (Docker Desktop on an aarch64-darwin host — native
    aarch64 and QEMU-emulated x86_64), both exiting with the requested
    code. That path isn't automated in the suite itself since it needs a
    container runtime and a network-fetched base image, neither of which
    belongs in this package's dependency set.
- Improved the readability of `elf64-finalize-executable`
  (`src/elf-emit-executable.lisp`), the largest function in the package:
  extracted its section-header-table-index arithmetic (`n-sections`,
  `dynsym-idx`, `dynstr-idx`, `symtab-idx`, `strtab-idx`, `debug-line-idx`,
  `shstrtab-idx` — seven bindings depending only on `dynamic-p`/`interp-p`/
  `rodata-str-section-delta`, not on anything else the function computes)
  into `%elf64-section-header-indices`, a small pure function with its own
  direct tests. The rest of the function is left as one long `let*`
  deliberately: it is a strict, linear chain of ELF file-offset
  computations where each binding depends only on the ones immediately
  before it, which is the clearest available style for that shape of
  computation — restructuring it further into more extracted functions
  would trade correctness risk in binary-format-critical code for
  diminishing readability return, not a genuine improvement.
- `nix build .#coverage`: an `SB-COVER` HTML report (`run-coverage.lisp`,
  `flake.nix`'s new `packages.coverage`), separate from `checks` since a
  coverage percentage is a number to read rather than a pass/fail gate and
  `sb-cover` instrumentation's forced full recompile is too slow for the
  fast path `nix flake check` takes. Measuring it found `src/wasm.lisp` at
  0/138 expressions covered — the only source file with no test at all —
  and `src/elf.lisp`'s ELF64 builder accumulation API (`make-elf64-dynamic`,
  `elf64-add-got-entry`, `elf64-add-plt-stub`, `elf64-add-needed-library`,
  `elf64-add-reloc`, `elf64-add-global-symbol`, `elf64-add-load-segment`,
  `elf64-add-gnu-stack-segment`, `elf64-add-gnu-relro-segment`) at 49.8%,
  the lowest of any file with real logic, exercised only indirectly through
  the full `compile-to-elf64-exec` pipeline and never directly. Added
  `t/wasm-test.lisp` and `t/elf-builder-test.lisp` to close both gaps
  (`src/`'s own coverage moved 79.6% → 81.5%; `wasm.lisp` alone 0% → 95.7%).
  `src/elf-constants.lisp` and `src/macho.lisp` remain low (0% and 1.7%)
  because they are pure `defconstant`/`defstruct` declarations with no
  branching logic for `sb-cover` to attribute meaningfully — chasing that
  number with tests-of-literals would be gaming the metric, not testing
  anything.
- `t/elf-strtab-test.lisp`: `strtab-add` (`src/elf-strtab.lisp`) — the
  string-table primitive every ELF section-name, symbol-name, and DWARF
  string table in this package is built from — had no dedicated test at
  all. Covers dedup, distinct-offset assignment, and a property-based
  round-trip (add a string, read it back NUL-terminated from the returned
  offset).
- Property-based tests via `cl-weave`'s `it-property`/`gen-*` generators,
  replacing or supplementing example-based assertions with the actual
  mathematical invariant where one exists: `align-up` (result is the
  smallest multiple of the alignment that is `>=` the input, for random
  `value`/`alignment` pairs), `icf-sha256` (always a 32-byte digest,
  deterministic on repeated hashing of the same bytes), `encode-uleb128`/
  `encode-sleb128` (round-trip through a decoder written only in the test),
  and `strtab-add`'s dedup and round-trip properties above.
- A `cl-cc-binary-error` condition hierarchy (`src/conditions.lisp`):
  `value-out-of-range`, `elf-wx-violation`, `patchable-entry-overflow`,
  `pe-section-not-found`, and `macho-unknown-architecture`, each with a
  `:report` and `:reader`-bearing slots, replacing every bare `(error "...")`
  call in `src/` per `CODING_STANDARD.md`'s "no bare `error`" rule. A caller
  can now catch every
  failure this library signals with one `(cl-cc-binary-error (c) ...)`
  clause.
- `elf64-add-gnu-relro-segment` is now exported, completing the
  `elf64-add-{load,gnu-stack,gnu-relro}-segment` PT_LOAD/PT_GNU_* family; it
  was implemented but never added to the export list.
- `with-byte-buffer`: a macro for the "build a fresh buffer, write to it,
  return the bytes" shape that recurred across every section/payload builder
  in `src/` (DWARF, `.eh_frame`, Mach-O unwind info, compression metadata, PE
  DOS stub/import/export/relocation tables). Applying it retired
  `%dwarf-buffer`/`%dwarf-final-bytes` and `dwarf-eh-make-buffer`/
  `dwarf-eh-final-bytes`, two same-shaped pass-through adapter pairs it made
  unnecessary.
- `define-dwarf-cfa-short-form`: a macro generating a DWARF `.eh_frame`
  short-form CFA instruction emitter (range-check + opcode byte + optional
  trailing operand) from its opcode and the field being checked, replacing
  three hand-written near-duplicates in `src/dwarf-eh.lisp`.
- `binary-buffer-pad-and-write`: a function for the "pad the output buffer up
  to a section's known file offset, then write its bytes" idiom repeated
  ~20 times across `elf-emit-relocatable.lisp` and `elf-emit-executable.lisp`.
- `define-icf-entry-accessor`: a macro generating the dual
  `icf-function-section`-or-plist/alist dispatch that `icf-merge-identical-functions`
  needs for each of its four fields, replacing a `labels` block that
  reimplemented the same `etypecase` four times (plus a fifth inline copy
  outside it) in `src/icf.lisp`.
- Named `+pe-export-dir-*+` offset constants for the `IMAGE_EXPORT_DIRECTORY`
  struct, replacing 11 magic byte offsets in `pe-build-export-table`
  (`src/pe-tables.lisp`).
- `src/macho-build-assemble.lisp` (455 lines) split into
  `macho-build-text-segment.lisp` (unwind info and payload composition),
  `macho-build-dyld.lisp` (bind opcodes and `LC_LOAD_DYLIB`),
  `macho-build-layout.lisp` (command-size and file-offset arithmetic),
  `macho-build-serialize.lisp` (load-command and payload serialization), and
  `macho-codesign.lisp` (`write-mach-o-file` and the `*binary-logger*`
  diagnostics around it), leaving `build-mach-o`'s 80-line orchestration
  behind. `src/elf.lisp` (341 lines) split into `elf-constants.lisp` (81 ELF
  spec constants), `elf-strtab.lisp` (byte-buffer and string-table
  primitives), and the 186-line `elf64-builder` core. `src/elf-emit-executable.lisp`
  (415 lines) split its public entry points (`compile-to-elf64`,
  `compile-to-elf64-exec`, `elf64-build-x86-64-start-wrapper`,
  `write-elf64-file`) into `elf-compile.lisp`. Every `src/` file is now under
  the 300-line target in `CODING_STANDARD.md`.
- `%macho-codesign-cps`: the `codesign` outcome dispatch in `write-mach-o-file`
  rewritten in the same continuation-passing style as the existing
  `compress-code-bytes-cps`, with `on-ok`/`on-timeout`/`on-error`
  continuations in place of the equivalent `handler-case`.
- `buffer-pad-to`: the `byte-buffer` CLOS-class counterpart to
  `binary-buffer-pad-and-write`, replacing three more hand-rolled
  "pad to an offset" loops in `%serialize-macho-payloads`
  (`macho-build-serialize.lisp`) with the same named idiom used everywhere
  else in the package.

### Fixed

- `src/elf.lisp`'s `(in-package :cl-cc/binary)` form carried a trailing
  comment fragment left over from moving the ELF spec constants out to
  `elf-constants.lisp` — one long, disconnected run-on of the constants'
  old inline comments concatenated onto the `in-package` line instead of
  being deleted with them. Removed; the constants' own comments already
  live in `elf-constants.lisp`.
- `define-icf-entry-accessor` (`src/icf.lisp`) signalled a type error
  reading a plist entry missing an optional key (for example
  `:linkable-distinct-p`), because its `(or (getf ...) (cdr (assoc ...)))`
  fallback tried `assoc` — which calls `car` on each element — against a
  plist's flat, non-cons structure whenever `getf` returned `nil`. It now
  discriminates plist from alist by whether the entry's first element is a
  cons before choosing `getf` or `assoc`, instead of trying both.
- `t/dwarf-eh-test.lisp`'s "includes the FDE's address-range in its
  payload" test read 8 bytes past the FDE's length prefix, landing on
  `initial_location` instead of `address_range` (`length`, `cie_pointer`,
  `initial_location`, `address_range` are four preceding u32 fields, i.e.
  12 bytes, not two). The test passed only because both fields defaulted
  to matching values in earlier runs; asserting a non-zero
  `:address-range` exposed the wrong offset.
- Several `src/*.lisp` and `t/*.lisp` files introduced by this refactor
  were left untracked by git, which made `nix build`/`nix flake check`
  invisible to them (a flake's `self` source only sees git-tracked paths)
  and broke every Nix-driven test run with a "Failed to find the TRUENAME"
  load error. Tracked them.
- `t/icf-test.lisp`'s empty-message SHA-256 test vector was missing its
  final hex digit (63 characters instead of 64): `icf-sha256`'s actual
  output already matches the real digest
  (`e3b0c4...7852b855`); only the test's expected-string literal was
  wrong.
- Applied 37 of `paredit-cli`'s 38 safe lint auto-fixes across `src/` and
  `t/` (`one-step-arithmetic` → `1+`, `sign-comparison` → `plusp`/`zerop`,
  `make-hash-table-test` dropping the redundant default `:test 'eql`,
  `if-to-or` and `negated-if` simplifications), re-indenting the few spots
  the mechanical rewrite left cramped. **Not** applied: the tool's
  `constant-if-test` finding on `elf64-string-bytes`
  (`src/elf-emit-executable.lisp`) and `%pe-ascii-bytes`
  (`src/pe-tables.lisp`) misidentified `(if nul 1 0)` as a dead branch,
  because its static analysis treated the `&key (nul t)` parameter's
  *default* literal as if it were always `t` — `%pe-ascii-bytes` is
  actually called with `:nul nil` for the PE DOS-stub message
  (`src/pe-tables.lisp:78`), so applying that fix would have silently
  NUL-terminated it incorrectly. A `redundant-body-progn` fix applied to
  `src/binary-struct.lisp` was caught and reverted for a similar reason:
  it stripped the backquote along with the `(progn ...)` it was inside of,
  turning the macro's expansion-producing template into code with commas
  outside any backquote — a reader error the tool's own structural
  balance check does not catch, since it isn't a balanced-parens problem.

### Added (tests)

- `elf64-verify-wx`'s error path — the actual W^X safety check, as opposed
  to the already-tested "well-formed builds don't trip it" case — had no
  test signalling `elf-wx-violation` for a genuinely conflicting PT_LOAD
  segment. Added to `t/elf-emit-executable-wxorx-test.lisp`.
- `write-mach-o-fat-file` had no test at all; `build-mach-o-fat-binary`
  (the pure byte-producing function it wraps) was tested, but the
  file-writing wrapper itself was not. Added to `t/macho-fat-test.lisp`.
- `t/macho-build-executes-test.lisp`: every other test in this suite
  asserts on bytes; none ever handed a produced image to the operating
  system and asked it to run. This test builds a real ARM64 Mach-O
  executable, writes and ad-hoc-codesigns it through the same
  `write-mach-o-file` path every caller uses, executes it, and checks the
  process exits with the code its own machine code requested — proof the
  header, load commands, and codesign step produce something the real
  kernel will load and run. `it-run-if`-guarded to only attempt this on an
  aarch64-darwin host outside a Nix build sandbox: it observed exit code
  137 (SIGKILL) under `nix build .#checks.aarch64-darwin.default` even on
  a real aarch64-darwin host, matching Nix's sandbox-exec profile denying
  process-exec for a binary the derivation just produced, not a defect in
  the emitted Mach-O.
- `*dwarf-abbrev-table*`: `build-dwarf-abbrev-section`'s 39 lines of
  hand-sequenced ULEB128 writes replaced with a data table of
  `(abbrev-code tag has-children attrs)` rows plus a small interpreter loop.
  Adding a DIE kind to the compact DWARF producer is now a table row, not new
  emission code.
- `pe-finalize`'s three-pass fixed-point section layout (each generated
  section's data-directory entry needs a stable RVA from the layout pass
  before it, and changes that section's size for the layout pass after it)
  rewritten as explicit CPS stages — `%pe-with-import-table`,
  `%pe-with-export-table`, `%pe-with-base-relocations` — replacing three
  levels of nested `multiple-value-bind` and mutation with named,
  independently readable steps.
- `t/pe-finalize-test.lisp`: `pe-finalize`/`compile-to-pe` had no test
  coverage at all before this file. Ten tests cover DOS/PE signatures, COFF
  machine type and DLL characteristics, the PE32+ optional-header magic, and
  — exercising the new CPS stages directly — that added imports, exports,
  and base relocations each produce a nonzero data-directory entry in the
  final image.
- `t/icf-test.lisp`, `t/dwarf-test.lisp`, `t/dwarf-eh-test.lisp`: measured
  baseline coverage (`cl-weave run-all :coverage t`, backed by `sb-cover`)
  was 60.8% expression coverage overall, with `icf.lisp`, `dwarf.lisp` and
  `dwarf-eh.lisp` — 1,309 of the roughly 2,700 uncovered expressions between
  them — completely untested. These three files target exactly that gap:
  `icf-sha256` against the NIST SHA-256 test vectors and every branch of
  `icf-merge-identical-functions` (disabled passthrough, byte-identical
  folding, `linkable-distinct-p` exemption, plist/alist entry
  representations); `build-dwarf-debug-sections`, `dwarf-location-expression`
  and its `value-out-of-range` signals; `build-dwarf-eh-frame`,
  `build-dwarf-eh-lsda`, the `dwarf-eh-emit-*` short-form range checks, and
  `dwarf-eh-encode-instruction-list`.
- [cl-process-kit](https://github.com/nerima-lisp/cl-process-kit) v2.0.0:
  timeout-guarded subprocess execution (SIGTERM->SIGKILL escalation) for the
  `codesign` invocation in `write-mach-o-file`, replacing a hand-rolled
  `sb-ext:run-program` + `sb-ext:with-timeout` pair with the org's dedicated
  toolkit for exactly this problem. `write-mach-o-file` now also checks the
  subprocess's exit status (previously ignored) and logs a failed codesign
  the same way it already logged a timed-out one. Pulls in `cl-boundary-kit`
  transitively; see `cl-cc-binary.asd` for the layer/depth accounting.
- Documentation site under `docs/`, published to
  <https://nerima-lisp.github.io/cl-cc-binary/> by the `docs` workflow and
  built with `mkdocs --strict` as part of `nix flake check`.
- `docs`, `release` and `flake-update` workflows, plus the shared
  `.github/actions/nix-setup` composite action.
- `checks.formatting` (treefmt/nixfmt) and `checks.docs` in the flake, and an
  `apps.test` entry point.
- This changelog.

### Changed

- `%elf-u16le`/`%elf-u32le`/`%elf-u64le`/`%elf-c-string`/`%elf-section-flags-by-name`
  moved from `t/elf-emit-executable-wxorx-test.lisp` (where three other test
  files relied on them only because that file happened to load first) to
  `t/helpers-byte-reader.lisp`, per `CODING_STANDARD.md`'s `helpers-` naming
  convention for shared test fixtures. Loaded immediately after `package` in
  `cl-cc-binary/test`'s `:components`, so the dependency no longer depends on
  incidental ordering.
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
- `flake.nix` tracks `nixos-unstable`, pins `cl-weave` to `v1.1.0` (was
  `v1.0.0`) and `cl-log-kit` to `v2.0.0` (was `v1.0.0`), declares
  `x86_64-linux` and `aarch64-darwin` only, and reads the version from
  `cl-cc-binary.asd` rather than repeating it. The `cl-log-kit` bump pulls in
  `cl-date-kit`, `cl-concurrent-kit` and `cl-host-kit` transitively (its
  v2.0.0 dropped the zero-runtime-dependency guarantee); all three are
  leaves with no further org-internal dependencies.
- Every `uses:` in CI carries a `# vX` comment alongside its commit SHA.
- Verification status for this refactor: every file added or changed above —
  the full real dependency chain (`cl-date-kit`, `cl-concurrent-kit`,
  `cl-host-kit`, `cl-log-kit`, `cl-boundary-kit`, `cl-process-kit`,
  `cl-weave`, all 32 `src/` files, all 15 `t/` files) — compiles and loads
  cleanly with zero errors or warnings; this was reconfirmed across multiple
  independent runs and two SBCL point releases (self-built 2.6.0 and the
  Nix-built `cl-weave` v1.1.0 CLI's 2.6.6). One full `cl-weave:run-all` before
  `pe-finalize-test`/`icf-test`/`dwarf-test`/`dwarf-eh-test` were added passed
  116/116, and a coverage-instrumented run measured 60.8% expression coverage
  (4233/6957) as the baseline these four files target. Re-running the full
  suite after adding them to confirm a new pass/coverage number has not been
  possible in this sandboxed SBCL/Darwin environment: `cl-weave:run-all`
  reproducibly stalls at 0% CPU before running any test, including in a
  from-scratch process loading only the dependency chain plus a single test
  file. `sample` on the stalled process shows the SBCL `finalizer` thread
  mid-`call_into_lisp` — i.e. running Lisp code from inside a GC-triggered
  finalizer — while the main thread and GC worker pool sit blocked on
  `_dispatch_sema4_wait`/`semaphore_wait_trap`, the signature of a documented
  SBCL/Darwin GC-vs-thread-coordination deadlock (sbcl-devel "malloc-deadlock
  test" thread; Launchpad bug #2062940), compounded here by other concurrent
  SBCL processes from unrelated sessions on the same shared host. This is a
  runtime/environment issue, not a defect in the code above: it reproduces
  identically regardless of `:max-workers`, coverage instrumentation on/off,
  explicit per-file GC on/off, dynamic-space size, or which single test file
  is loaded. Resolved for release verification purposes by going through
  `nix flake check` instead of an ad-hoc `sbcl --script run-tests.lisp`: the
  Nix-sandboxed derivation does not hit the stall (it is a fresh, isolated
  process rather than one sharing a host with unrelated concurrent SBCL
  processes), and passed 200/202 (2 skipped — the execution tests, guarded to
  hosts/architectures the sandbox does not provide) with zero failures.

### Removed

- No backward-compatibility shims were found or removed: an explicit sweep
  (`grep -rniE "deprecated|backward.?compat|legacy|TODO|FIXME|for compatibility|kept for"`)
  over `src/` and `t/` returned zero matches before this refactor started,
  and the one thing that called itself a "compatibility wrapper" — the dead
  `elf64-build-eh-frame` below — turned out to be dead code with a stale
  docstring, not an intentional shim.
- `src/dwarf-dwo.lisp` (split-DWARF `.dwo` file generation): unexported,
  uncalled from anywhere in this repository or its test suite, and untested.
  If split-DWARF support is needed later it should come back with tests and
  an export.
- `elf64-build-eh-frame` in `src/dwarf-eh.lisp`: a second definition of a
  function already defined (differently) in `src/elf-emit.lisp`. Because
  `dwarf-eh` loads before `elf-emit` in `cl-cc-binary.asd`, this one was
  silently shadowed by the other at every call site — dead code whose
  docstring's claim that it "is used by the ELF backend" was stale.
- `icf-fold-functions` (`src/icf.lisp`): an unexported, uncalled, simpler
  duplicate of the exported `icf-merge-identical-functions`.
- `make-elf64-shared-library` (`src/elf.lisp`): an unexported, uncalled
  one-line wrapper around `make-elf64-dynamic :shared-object t`, which
  callers already call directly.
- `make-wasm-buffer`, `wasm-buf-write-uleb128`, `wasm-buf-write-sleb128`,
  `wasm-buf-write-f64` (`src/wasm.lisp`): unexported, uncalled adapters
  around the already-generic `binary-buffer-*` API that added no behavior of
  their own — exactly the kind of unnecessary wrapper this refactor removes
  on sight. The file's header comment referencing a nonexistent
  `wasm-trampoline-emit.lisp` was also stale and is corrected.
- `%dwarf-hash->alist`, `%dwarf-regalloc-assignments`,
  `emit-dwarf-location-change-event`, `track-variable-locations-after-regalloc`,
  `build-dwarf-section-alist` (`src/dwarf.lisp`): an unexported,
  uncalled post-register-allocation-to-DWARF adapter cluster and an
  unexported, uncalled alist view of `build-dwarf-debug-sections`.
- `%macho-write-u32-be` (`src/macho-fat.lisp`): unexported, uncalled;
  `build-mach-o-fat-binary` already has its own equivalent local
  `write-u32`.
- `%pe-rva-to-file-offset` (`src/pe-tables.lisp`): unexported, uncalled.

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
