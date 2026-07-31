# Architecture

`src/` is flat — 32 files, 4,622 lines, no subdirectories — and loaded
`:serial t` in the order given by `cl-cc-binary.asd`. The flatness is a
constraint from the org package standard rather than a design choice; the
grouping below is expressed by file name prefix instead.

## Layers

The load order is the dependency order, and it has four bands.

**Primitives.** `package.lisp` defines `cl-cc/binary` and its exports.
`conditions.lisp` defines the `cl-cc-binary-error` condition hierarchy every
other file signals through. `binary-struct.lisp` provides
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

Every file is under, or (`elf-emit-executable.lisp`, at 299) right at, the
300-line target in `CODING_STANDARD.md`; it and `dwarf.lisp` (275) are the
largest. `elf64-finalize-executable`'s section-header-index arithmetic —
seven bindings computing where `.dynsym`/`.dynstr`/`.symtab`/etc. land in the
section header table, themselves independent of everything else the
function computes — is `%elf64-section-header-indices`, a small pure
function with its own direct tests (`t/architecture-test.lisp`) instead of
only being reachable through the full assembly pipeline. The rest of the
function stays one long `let*`: it is a strict, linear chain of ELF file
offsets where each binding depends only on the ones immediately before it,
which is the clearest style available for that shape of computation, not a
readability problem to keep dividing.

## Memory

Images are assembled entirely in memory. `build-mach-o`, `compile-to-elf64` and
`compile-to-pe` each return a fresh byte vector, and the buffers they accumulate
into are adjustable vectors that double as they grow. At peak, a build holds the
input code vector, the growing buffer and the final copy simultaneously. That is
fine for the program sizes cl-cc produces and would need rethinking for
link-time work over large object sets.

## Conditions and diagnostics

Every condition the package signals derives from `cl-cc-binary-error`
(`conditions.lisp`), so a caller can catch every failure this library raises
with one `handler-case` clause. Each condition names the situation it
reports — `value-out-of-range`, `elf-wx-violation`,
`patchable-entry-overflow`, `pe-section-not-found`,
`macho-unknown-architecture` — rather than a generic `-error` suffix, and
carries `:reader`-bearing slots so a handler can inspect what went wrong
without parsing a message string.

Failures that happen after the useful work is already done — a `codesign`
timeout or nonzero exit in `write-mach-o-file` — are a different case: there
is nothing left for a caller to act on, since the binary was already written
successfully and codesigning is best-effort. Those are reported to
`*binary-logger*`, which is `nil` by default, instead of signalled. See
[Core Concepts](core-concepts.md#diagnostics).
