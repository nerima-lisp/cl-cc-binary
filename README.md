# cl-cc-binary

Object-file emission for the [cl-cc](https://github.com/nerima-lisp/cl-cc)
Common Lisp compiler: the `:cl-cc/binary` package — byte buffers, constant
pools, ELF and Mach-O (including fat) writers, GOT/PLT construction, W^X memory
protection, and patchable entry points.

A **leaf system** extracted from the cl-cc monorepo as part of the repository
split (see `docs/repo-split-design.md` in cl-cc). It has no dependencies on
other cl-cc systems and is consumed by the native code generator. Its only
runtime dependency is [`cl-log-kit`](https://github.com/nerima-lisp/cl-log-kit),
used directly for optional structured diagnostics: binding
`cl-cc/binary:*binary-logger*` to a `log-kit:make-logger` instance observes
otherwise-silent failure paths (such as a timed-out or failed `codesign`
invocation in `write-mach-o-file`); the default `nil` logger keeps the
library silent.

## Status

Extracted and building standalone, with a cl-weave test suite. Integration
tests that drive the emitter from the VM/codegen layer stay in the monorepo
until those packages are extracted.

## Usage

```lisp
(asdf:load-system :cl-cc-binary)
```

## Development

```bash
nix develop            # sbcl dev shell
nix flake check        # compile check + cl-weave test suite
```

## License

MIT — see [LICENSE](LICENSE).
