# Architecture

The source files are loaded `:serial t` in the order given by
`cl-cc-binary.asd`. The grouping below follows their file-name prefixes.

## Layers

The load order is the dependency order, and it has four bands.

**Primitives.** `package.lisp` defines `cl-cc/binary` and its exports.
`conditions.lisp` defines the library's `cl-cc-binary-error` condition
hierarchy. `binary-struct.lisp` provides
`define-binary-struct`, `binary-writer.lisp` the `with-output-to-vector`
macro, and `macho-buffer.lisp` the two buffer types, the little-endian
serialization primitives, and the `with-byte-buffer` macro and
`binary-buffer-pad-and-write` function every section/payload builder in the
package is written against. Nothing above this band writes a byte without
going through it.

**Mach-O.** `macho.lisp` holds constants and struct declarations,
`macho-serialize.lisp` turns those records into bytes, `macho-fat.lisp` handles
universal binaries, and `macho-build*.lisp` is the builder and the assembly
pass.

**ELF.** `elf-constants.lisp` holds the ELF spec constants,
`elf-strtab.lisp` the byte-buffer and string-table primitives they and
everything downstream build on, and `elf.lisp` the `elf64-builder`
accumulation API. `icf.lisp`, `got-plt.lisp` and `patchable-entry.lisp` are
independent transformations over sections, `dwarf*.lisp` produce debug and
unwind payloads, and `elf-emit*.lisp`/`elf-compile.lisp` assemble the final
images and expose the public `compile-to-elf64*` entry points.

**Other formats.** `pe*.lisp` and `wasm.lisp` are self-contained.

The bands do not reach sideways: nothing in the Mach-O files calls into the ELF
files or vice versa. `macho-buffer.lisp` is the only shared code, which is why
its four `(safety 1)` primitives sit on every hot path in the package.

## `define-binary-struct`

Most on-disk records are a fixed sequence of fixed-width little-endian fields.
Writing a `defstruct` and a matching `serialize-` function by hand for each of
them made up most of the original `macho-serialize.lisp`, and the two halves
could drift.

`define-binary-struct` takes the record as data — `(slot default wire-width)`
triples, where the width is `:u8`, `:u32`, `:u64` or `:string16` — and generates
both the `defstruct` and a field-by-field serializer that writes slots in
declaration order.

It deliberately does not cover every record. `dylib-command` carries a
variable-length string, `relocation-info` bitpacks several fields into one word,
and `nlist` has an on-wire `n-desc` narrower than its declared slot. Those three
stay hand-written; stretching the macro to fit them would have made the
generated code harder to check than the code it replaced.

The macro derives the serializer name from the struct name, so
`entry-point-command` yields `serialize-entry-point-command`. That renaming is
what broke `build-mach-o` when the hand-written `serialize-entry-point` was
replaced and the call site was not updated — see the
[release notes](https://github.com/nerima-lisp/cl-cc-binary/releases).

## Why the files split the way they do

`elf-emit`, `macho-build` and `pe` each grew past 500 lines, which
`CODING_STANDARD.md` treats as the point at which a file stops being reviewable.
They were divided along the seams that already existed in them:

| Original | Now | Seam |
|---|---|---|
| `elf-emit` | `elf-emit`, `elf-emit-relocatable`, `elf-emit-executable`, `elf-compile` | `ET_REL` and `ET_EXEC`/`ET_DYN` share almost no layout logic; `elf-compile` is the public entry points over both |
| `macho-build` | `macho-build`, `macho-build-assemble`, `macho-build-compression`, `macho-build-text-segment`, `macho-build-dyld`, `macho-build-layout`, `macho-build-serialize`, `macho-codesign` | accumulating the builder, the single assembly pass over it, and each concern that pass composes |
| `pe` | `pe`, `pe-tables`, `pe-finalize` | builder state, import/export/relocation tables, image assembly |
| `elf` | `elf-constants`, `elf-strtab`, `elf` | spec constants, buffer/string-table primitives, the builder accumulation API |

The section-header-index arithmetic used by `elf64-finalize-executable`
is factored into `%elf64-section-header-indices`, with direct tests in
`t/architecture-test.lisp`. The remaining `let*` computes file offsets in
dependency order.

## Memory

Images are assembled entirely in memory. `build-mach-o`, `compile-to-elf64` and
`compile-to-pe` each return a fresh byte vector, and the buffers they accumulate
into are adjustable vectors that double as they grow. At peak, a build holds the
input code vector, the growing buffer and the final copy simultaneously.
Peak memory therefore grows with the image size; this is not a streaming
linker interface.

## Conditions and diagnostics

Library-defined errors derive from `cl-cc-binary-error`
(`conditions.lisp`). Their readers expose details such as the rejected value,
section name, or signing failure reason. Filesystem and argument-type failures
may use host condition classes instead.

`write-mach-o-file` stages the output and signs it before replacing the target.
A missing signing program, timeout, or nonzero exit signals
`macho-codesign-error` and leaves an existing target unchanged.
Passing `:codesign nil` explicitly bypasses signing and writes unsigned bytes.
The optional logger does not replace this error contract. See
[Core Concepts](../guide/core-concepts.md#diagnostics).
