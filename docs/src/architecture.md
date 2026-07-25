# Architecture

`src/` is flat — 24 files, 4,639 lines, no subdirectories — and loaded
`:serial t` in the order given by `cl-cc-binary.asd`. The flatness is a
constraint from the org package standard rather than a design choice; the
grouping below is expressed by file name prefix instead.

## Layers

The load order is the dependency order, and it has four bands.

**Primitives.** `package.lisp` defines `cl-cc/binary` and its exports.
`binary-struct.lisp` provides `define-binary-struct`, `binary-writer.lisp` the
`with-output-to-vector` macro, and `macho-buffer.lisp` the two buffer types and
the little-endian serialization primitives. Nothing above this band writes a
byte without going through it.

**Mach-O.** `macho.lisp` holds constants and struct declarations,
`macho-serialize.lisp` turns those records into bytes, `macho-fat.lisp` handles
universal binaries, and `macho-build*.lisp` is the builder and the assembly
pass.

**ELF.** `elf.lisp` holds constants and the builder, `icf.lisp`,
`got-plt.lisp` and `patchable-entry.lisp` are independent transformations over
sections, `dwarf*.lisp` produce debug and unwind payloads, and `elf-emit*.lisp`
assemble the final images.

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
[changelog](changelog.md).

## Why the files split the way they do

`elf-emit`, `macho-build` and `pe` each grew past 500 lines, which
`CODING_STANDARD.md` treats as the point at which a file stops being reviewable.
They were divided along the seams that already existed in them:

| Original | Now | Seam |
|---|---|---|
| `elf-emit` | `elf-emit`, `elf-emit-relocatable`, `elf-emit-executable` | `ET_REL` and `ET_EXEC`/`ET_DYN` share almost no layout logic |
| `macho-build` | `macho-build`, `macho-build-assemble`, `macho-build-compression` | accumulating the builder versus the single assembly pass over it |
| `pe` | `pe`, `pe-tables`, `pe-finalize` | builder state, import/export/relocation tables, image assembly |

`elf-emit-executable.lisp` (429 lines) and `macho-build-assemble.lisp` (457) are
still the two largest files and are the natural next candidates if either grows.

## Memory

Images are assembled entirely in memory. `build-mach-o`, `compile-to-elf64` and
`compile-to-pe` each return a fresh byte vector, and the buffers they accumulate
into are adjustable vectors that double as they grow. At peak, a build holds the
input code vector, the growing buffer and the final copy simultaneously. That is
fine for the program sizes cl-cc produces and would need rethinking for
link-time work over large object sets.

## Diagnostics, not conditions

The package exports no condition types. Errors that the caller can act on are
signalled with plain `error`; failures that happen after the useful work is
already done — a `codesign` timeout in `write-mach-o-file` — are reported to
`*binary-logger*`, which is `nil` by default. See
[Core Concepts](core-concepts.md#diagnostics).
