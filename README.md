# cl-cc-binary

Object-file emission for the [cl-cc](https://github.com/nerima-lisp/cl-cc)
Common Lisp compiler: the `:cl-cc/binary` package — byte buffers, constant
pools, ELF and Mach-O (including fat) writers, GOT/PLT construction, W^X memory
protection, and patchable entry points.

A **dependency-free leaf system** extracted from the cl-cc monorepo as part of
the repository split (see `docs/repo-split-design.md` in cl-cc). It has no
cl-cc dependencies and is consumed by the native code generator.

## Status

Extracted and building standalone, with a cl-weave test suite (78 tests).
Integration tests that drive the emitter from the VM/codegen layer stay in the
monorepo until those packages are extracted.

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
