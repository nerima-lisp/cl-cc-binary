# Development

Everything below runs through the flake, so the SBCL version and the sibling
package revisions are the same on a laptop and in CI.

## Commands

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix run .#test       # run the test suite
nix flake check      # tests + formatting + docs — the gate CI uses
nix fmt              # format Nix sources (treefmt/nixfmt)
nix build .#docs     # render this site to ./result
nix build .#coverage # SB-COVER HTML report to ./result/cover-index.html
```

`nix build .#coverage` is not part of `nix flake check`: `sb-cover` instrumentation forces a full recompile of `cl-cc-binary` and every dependency it shares a source registry with, which is too slow for the fast path every check run takes, and a coverage percentage is a number to read rather than a pass/fail gate. Run it on demand and open `result/cover-index.html`; the subheading for `.../source/src/` in that report is this package's own code, the others are `cl-log-kit`/`cl-weave`/etc. picking up incidental coverage from whatever of their surface the test suite happens to exercise.

`nix flake check` is the only command whose result matters for a pull request.
It runs three derivations in parallel:

| Check | What it does |
|---|---|
| `checks.default` | `sbcl --script run-tests.lisp` — the cl-weave suite |
| `checks.formatting` | fails if any tracked Nix file is unformatted |
| `checks.docs` | `mkdocs build --strict`, so a broken link or a page missing from `nav` fails the build |

New granularity belongs here as another `checks.*` attribute, not as another
GitHub Actions job. `nix flake check` already schedules them in parallel with
build caching; a second job would duplicate that and lose the cache sharing.

## Declared systems

The flake declares `x86_64-linux` and `aarch64-darwin`, and nothing else. Those
are the two that are actually verified: CI builds the first, and development
machines are Darwin arm64 so the second is exercised by every local
`nix flake check`. `ci.yml` does not pass `--all-systems`.

## Running the tests without Nix

```sh
export CL_SOURCE_REGISTRY="/path/to/cl-weave//:/path/to/cl-log-kit//:/path/to/cl-date-kit//:/path/to/cl-concurrent-kit//:/path/to/cl-host-kit//:/path/to/cl-process-kit//:/path/to/cl-boundary-kit//"
sbcl --script run-tests.lisp
```

The trailing `//` makes ASDF search recursively. `run-tests.lisp` adds its own
directory to `asdf:*central-registry*`, so it does not matter what your working
directory is.

Do not write `sbcl --noinform --non-interactive --script run-tests.lisp`. SBCL
acts on `--non-interactive` before it reaches the script, so that command exits
0 without running anything — which is exactly how a broken `build-mach-o` sat on
`main` under a green `nix flake check`.

## Writing tests

Tests live in `t/`, named after the source file they cover:
`src/got-plt.lisp` is tested by `t/got-plt-test.lisp`. When one source file has
several distinct concerns, add the concern to the name —
`t/macho-build-assemble-entry-point-test.lisp` and
`t/macho-build-assemble-logging-test.lisp` both cover
`src/macho-build-assemble.lisp`. Every file is listed in the
`cl-cc-binary/test` system in `cl-cc-binary.asd`. A file that is not listed is
not run.

The framework is [cl-weave](https://nerima-lisp.github.io/cl-weave/) — nested
`describe`, `it`, and `expect`. Do not introduce FiveAM, parachute, rove or
prove.

```lisp
(in-package :cl-cc-binary/test)

(describe "align-up"
  (it "rounds up to the next multiple"
    (expect (= (cl-cc/binary:align-up 4097 4096) 8192))))
```

Reach for internal symbols with the double-colon `cl-cc/binary::` prefix when a
test needs one; several existing files do, and that is preferred over widening
the export list for the sake of a test.

## Optimization declarations

`PERFORMANCE_STANDARD.md` fixes the declaration form as
`(optimize (speed 3) (safety 1))`. `(safety 0)` is not permitted anywhere in
`src/`: under it SBCL trusts type declarations without checking them, so a
caller's mistake becomes a corrupt object file rather than a `type-error` at the
call site.

`declaim (optimize ...)` is global to everything compiled after it in the same
image, so it is either at the top of every file in the system or in none of
them. This system uses none; scope an optimization to a single function with
`declare` instead.

## Releasing

Bump `:version` in `cl-cc-binary.asd`, move the `## [Unreleased]` entries into a
new `## [X.Y.Z] - YYYY-MM-DD` section in `CHANGELOG.md`, then push the matching
`vX.Y.Z` tag. `release.yml` refuses a tag that disagrees with the `.asd`
version, and builds the release body from the changelog section with that exact
heading, so a deviation in either place fails the release.
