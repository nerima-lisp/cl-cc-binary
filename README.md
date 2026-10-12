# cl-cc-binary

[![CI](https://github.com/nerima-lisp/cl-cc-binary/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-cc-binary/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-0a7a5a)](https://nerima-lisp.github.io/cl-cc-binary/)

cl-cc-binary packages machine-code bytes as Mach-O (including universal
binaries), ELF relocatable objects and executables, PE32+ images and DLLs, and
WebAssembly module bytes, with symbol tables, relocations, GOT/PLT stubs,
DWARF and `.eh_frame` sections, and patchable function entries. Executing an
image also depends on the target architecture, loader, and runtime. It is the object-file layer of
the [cl-cc](https://github.com/nerima-lisp/cl-cc) compiler, and a leaf: SBCL
only, with [cl-log-kit](https://github.com/nerima-lisp/cl-log-kit) and
[cl-process-kit](https://github.com/nerima-lisp/cl-process-kit) its only two
direct dependencies and no ties to any other cl-cc package.

Full documentation is published at <https://nerima-lisp.github.io/cl-cc-binary/>.
The source for that site lives in [docs/src/](docs/src/).
Release changes and verification scope are in [CHANGELOG.md](CHANGELOG.md).

## Quick Start

```lisp
(asdf:load-system "cl-cc-binary")

;; x86-64: mov edi, 0 / mov eax, 60 / syscall
(let ((code (coerce #(#xbf #x00 #x00 #x00 #x00
                      #xb8 #x3c #x00 #x00 #x00
                      #x0f #x05)
                    '(simple-array (unsigned-byte 8) (*)))))
  (cl-cc/binary:write-elf64-file
   "/tmp/exit0"
   (cl-cc/binary:compile-to-elf64-exec code '() :type :exec)))
;; Historical 0.2.0 output: a 13184-byte statically linked ELF64 executable
```

## Install

```nix
# flake.nix
inputs.cl-cc-binary = {
  url = "github:nerima-lisp/cl-cc-binary/v0.2.1";
  flake = false;
};
```

Pin a release tag rather than following the default branch. This example uses
v0.2.1; version 0.2.2 is an unreleased candidate.

## Dependencies

```
cl-cc-binary -> cl-log-kit -> cl-date-kit
cl-cc-binary -> cl-log-kit -> cl-concurrent-kit
cl-cc-binary -> cl-log-kit -> cl-host-kit
cl-cc-binary -> cl-process-kit -> cl-boundary-kit -> cl-log-kit
cl-cc-binary -> cl-process-kit -> cl-log-kit
```

`cl-log-kit` is required at load time but silent unless
`cl-cc/binary:*binary-logger*` is bound; since v2.0.0 it pulls in
`cl-date-kit`, `cl-concurrent-kit` and `cl-host-kit` as its own runtime
dependencies. `cl-process-kit` guards the `codesign` subprocess
`write-mach-o-file` invokes with a timeout and SIGTERM->SIGKILL escalation,
and depends on `cl-boundary-kit` and `cl-log-kit` directly. `cl-weave` is a
test-only dependency and is not in the shipped system.

## Documentation

- [Getting started](docs/src/getting-started.md)
- [Core concepts](docs/src/guide/core-concepts.md)
- [API reference](docs/src/reference/api.md)
- [Architecture](docs/src/reference/architecture.md)

## Development

```sh
nix develop          # SBCL with CL_SOURCE_REGISTRY already set
nix run .#test       # run the test suite
nix flake check      # tests + compile + formatting + docs, the same gate CI uses
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under [cl-weave](https://github.com/nerima-lisp/cl-weave),
the org's test framework.

## Contributing

See the org-wide [CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the [package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](LICENSE).
