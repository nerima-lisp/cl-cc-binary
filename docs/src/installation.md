# Installation

cl-cc-binary is an ASDF system for SBCL. It is distributed as a Nix flake and
consumed as a source tree; there is no Quicklisp release.

## Requirements

- SBCL. The system uses `sb-ext` for optional code compression and for the
  `codesign` invocation in `write-mach-o-file`, and is not portable to other
  implementations.
- [cl-log-kit](https://nerima-lisp.github.io/cl-log-kit/), the only runtime
  dependency. It is required at load time but does nothing unless
  `cl-cc/binary:*binary-logger*` is bound; see
  [Core Concepts](core-concepts.md#diagnostics).

## Flake input

Add the input, pinned to a release tag. A bare `github:nerima-lisp/cl-cc-binary`
follows the default branch, which means a push here can break your build
without warning.

```nix
# flake.nix
inputs.cl-cc-binary = {
  url = "github:nerima-lisp/cl-cc-binary/v0.1.0";
  flake = false;
};
```

`flake = false` pulls the source tree only. That is all ASDF needs, and it keeps
this repository's own inputs out of your `flake.lock`.

Put the resulting store path on `CL_SOURCE_REGISTRY` along with cl-log-kit:

```nix
CL_SOURCE_REGISTRY = "${cl-cc-binary}//:${cl-log-kit}//:${self}//";
```

The trailing `//` tells ASDF to search the tree recursively.

## ASDF dependency

```lisp
(defsystem "your-system"
  :depends-on ("cl-cc-binary")
  ...)
```

## Verifying

```lisp
(asdf:load-system "cl-cc-binary")
(asdf:component-version (asdf:find-system "cl-cc-binary"))
;; => "0.1.0"
```

`cl-cc-binary.asd` is the single source of truth for the version: `flake.nix`
reads the `:version` form out of it, and the release workflow refuses to publish
a tag that disagrees with it.

## Package name

The ASDF system is `cl-cc-binary`; the Lisp package it defines is
`cl-cc/binary`, with the nickname `binary`. The two names differ because the
package predates the split of cl-cc into separate repositories and callers
already qualify symbols as `cl-cc/binary:`.
