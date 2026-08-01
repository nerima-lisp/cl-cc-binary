# cl-cc-binary

cl-cc-binary turns a vector of machine-code bytes into a file an operating
system will load. It writes Mach-O (including universal/fat binaries), ELF
relocatable objects and executables, PE32+ images and DLLs, and WebAssembly
module bytes, plus the metadata that makes them usable: symbol tables,
relocations, GOT/PLT stubs, DWARF debug and `.eh_frame` unwind sections, and
patchable function entries.

It is the object-file layer of the [cl-cc](https://github.com/nerima-lisp/cl-cc)
compiler, and it is a leaf: it knows nothing about cl-cc's AST, types or
runtime, and depends on no other cl-cc package. SBCL only.

```lisp
;; x86-64: mov edi, 0 / mov eax, 60 / syscall
(let ((code (coerce #(#xbf #x00 #x00 #x00 #x00
                      #xb8 #x3c #x00 #x00 #x00
                      #x0f #x05)
                    '(simple-array (unsigned-byte 8) (*)))))
  (length (cl-cc/binary:compile-to-elf64 code '())))
;; => 1024
```

## Where to go next

- [Getting Started](getting-started.md) — adding the flake input and the
  `:depends-on` entry, then emitting an ELF executable end to end.
- [Core Concepts](guide/core-concepts.md) — buffers, builders and the two shapes of API.
- [Examples](guide/examples.md) — the same bytes as Mach-O, PE and a fat binary.
- [API Reference](reference/api.md) — every exported symbol.
- [Architecture](reference/architecture.md) — how `src/` is divided and why.
- [Development](project/development.md) — building, testing and formatting.

## Stability

The version is 0.2.0 and the exported surface is not yet under a compatibility
promise. Treat the symbol list in the [API Reference](reference/api.md) as the
current state rather than a contract; see the
[release notes](https://github.com/nerima-lisp/cl-cc-binary/releases) for what
has moved.

## Project

Contribution, conduct, security and support policy are org-wide and live in
[nerima-lisp/.github](https://github.com/nerima-lisp/.github):
[Contributing](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md),
[Code of Conduct](https://github.com/nerima-lisp/.github/blob/main/CODE_OF_CONDUCT.md),
[Security](https://github.com/nerima-lisp/.github/blob/main/SECURITY.md),
[Support](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).
