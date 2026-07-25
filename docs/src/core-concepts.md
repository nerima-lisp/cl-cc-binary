# Core Concepts

Four ideas explain the shape of the API: byte buffers, builders, the split
between one-shot and incremental entry points, and the optional logger.

## Byte vectors are the currency

Every emitter takes and returns `(simple-array (unsigned-byte 8) (*))`. There
is no stream abstraction at the boundary and no file handle: `compile-to-elf64`
returns a vector, and `write-elf64-file` is a separate two-line function that
puts a vector on disk. The consequence worth knowing is that images are built
entirely in memory, so a large program's object file exists twice at peak — once
as `*code*` and once as the assembled image.

Internally two buffer types accumulate output. `binary-buffer` is a bare
adjustable byte vector with a fill pointer, and `byte-buffer` is a CLOS wrapper
around one. Neither is exported; they appear here only because the serializer
functions in the [API Reference](api-reference.md) take a `byte-buffer` as their
second argument.

The `with-output-to-vector` macro is the exported way to collect bytes without
touching either type:

```lisp
(cl-cc/binary:with-output-to-vector (out)
  (funcall out #x7f)
  (funcall out #x45))
;; => #(127 69)
```

## Builders hold the parts that are not code

A Mach-O or PE image is code plus a set of tables: segments, sections, symbols,
relocations, imports, exports. A builder is the mutable accumulator for those
tables. You create one, add to it, and then finalize:

```lisp
(let ((builder (cl-cc/binary:make-mach-o-builder :x86-64)))
  (cl-cc/binary:add-text-segment builder code)
  (cl-cc/binary:add-symbol builder "_main")
  (cl-cc/binary:add-entry-point builder 0)
  (cl-cc/binary:build-mach-o builder code))
```

The three builders — `mach-o-builder`, the ELF64 builder from
`make-elf64-executable`, and `pe-builder` from `make-pe32+-builder` — are
independent types with independent operations. They do not share a protocol.

Note that `build-mach-o` takes the code bytes a second time, after
`add-text-segment` already received them. The builder records the segment
layout; the assembly pass re-reads the payload. Pass the same vector to both.

## Two shapes of API

Each format offers a one-shot function, an incremental builder, or both.

| Format | One-shot | Builder |
|---|---|---|
| ELF relocatable | `compile-to-elf64` | — |
| ELF executable | `compile-to-elf64-exec` | `make-elf64-executable` |
| Mach-O | — | `make-mach-o-builder` |
| Mach-O universal | `build-mach-o-fat-binary` | — |
| PE32+ | `compile-to-pe` | `make-pe32+-builder` |

Reach for the one-shot function when the whole program is one code vector and a
list of relocations, which is the common case coming out of a code generator.
Reach for the builder when you need to place things the one-shot signature does
not express: extra `PT_LOAD` segments, `.rodata` constants, PE imports and
exports, precise export RVAs.

The asymmetry is not principled. It reflects which format needed which control
first, and the one-shot functions grew keyword arguments (`:arch`, `:bss-size`,
`:dll-p`, `:subsystem`, `:exports`) as those needs appeared.

## Diagnostics

Some failure paths cannot signal. `write-mach-o-file` shells out to `codesign`,
and a timeout or a non-zero exit there is not fatal to producing the file — the
file is already written. Rather than either ignoring the failure or forcing a
condition on every caller, the library reports it to an optional logger:

```lisp
(setf cl-cc/binary:*binary-logger* (log-kit:make-logger))
```

The default is `nil`, and with `nil` the library emits nothing at all. This
mirrors `cl-process-kit`'s `*process-logger*` convention. It is also the reason
[cl-log-kit](https://nerima-lisp.github.io/cl-log-kit/) is a hard dependency of
a package that is otherwise dependency-free: the binding has to exist even when
nobody uses it.

## Optimization passes

Two passes are exposed rather than applied automatically.

`icf-merge-identical-functions` folds byte-identical functions, returning the
kept functions, a name-to-canonical-name table, and a count. Its `:enabled`
argument defaults to `*icf-enabled*`, which is `nil`, so folding is off until
you ask for it. It rechecks byte equality after hashing, so a hash collision
cannot fold code that merely hashes alike.

`elf64-verify-wx` signals an error if any `PT_LOAD` segment is both writable and
executable. It is a check, not a fix; call it before writing if W^X matters to
you.
