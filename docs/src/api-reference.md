# API Reference

Every symbol exported from the `cl-cc/binary` package, as of version 0.1.0 —
153 in total: 96 functions (43 operations plus 53 structure accessors), 1 macro,
3 variables, 36 constants and 17 structure classes.

Symbols not listed here are internal, whatever their visibility from the
package. In particular `binary-buffer`, `byte-buffer`, `build-compression-metadata`
and the `%`-prefixed helpers are implementation detail.

## Emitting object files

### `compile-to-elf64`

```lisp
(compile-to-elf64 code-bytes reloc-entries
                  &key (output-file nil) (arch :x86-64) (bss-size 0) compress)
```

Creates an `ET_REL` ELF64 relocatable object from `code-bytes` and
`reloc-entries` and returns it as a byte vector. `reloc-entries` is a list of
`(byte-offset . symbol-name)` pairs. Writes to `output-file` as well when one is
given.

### `compile-to-elf64-exec`

```lisp
(compile-to-elf64-exec code-bytes reloc-entries
                       &key output-file (arch :x86-64) (bss-size 0) (type :exec)
                            needed-libraries
                            (interpreter +elf64-default-interpreter+))
```

Creates a loadable ELF64 image. `type` is `:exec` for `ET_EXEC` or `:dyn` for a
PIE or shared object. On x86-64 a small `_start` wrapper is prepended before
`code-bytes`, so the image entry point is not byte zero of your code.

### `compile-to-pe`

```lisp
(compile-to-pe code-bytes reloc-entries
               &key output-file (arch :x86-64) dll-p (subsystem :console)
                    exports rdata-bytes data-bytes)
```

Creates a PE32+ executable or DLL. `reloc-entries` may hold plain `.text`-relative
integer offsets or `(offset . symbol)` pairs; only the offset is used, and each
becomes an `IMAGE_REL_BASED_DIR64` base relocation. `exports` names symbols
exported from `.text` at offset zero — use `pe-add-export` when you need a
precise RVA.

### `build-mach-o`

```lisp
(build-mach-o builder code-bytes &key compress)
```

Assembles a complete Mach-O executable from a builder and returns it as a byte
vector. The layout is `__PAGEZERO` + `__TEXT` (fileoff 0, covering the header
through the code) + `__LINKEDIT`, followed by `LC_LOAD_DYLINKER` and `LC_MAIN`.
`__TEXT.fileoff = 0` is required by macOS strict validation for code signing.
Function order within `code-bytes` is preserved exactly, so pipeline-level
function reordering controls the final text layout.

### `build-mach-o-fat-binary`

```lisp
(build-mach-o-fat-binary slices)
```

Builds a universal binary from a list of `mach-o-fat-slice` objects. The fat
header and `fat_arch` table are serialized big-endian as `FAT_MAGIC` requires;
slice payloads are copied verbatim at aligned offsets.

### Writing to disk

```lisp
(write-elf64-file filename bytes)
(write-pe-file filename bytes)
(write-mach-o-fat-file path slices)
(write-mach-o-file filename mach-o-bytes &key (codesign t))
```

All four write bytes and do not set the execute bit. `write-mach-o-file`
additionally invokes `codesign` unless `:codesign nil` is passed; a timeout or a
failure there does not prevent the file from being written, and is reported
through [`*binary-logger*`](#binary-logger) rather than signalled.

`write-mach-o-fat-file` takes slices rather than bytes, building the image
itself.

## The Mach-O builder

```lisp
(make-mach-o-builder arch)
```

Creates a `mach-o-builder` for `arch`, which is `:x86-64` or `:arm64`.

| Operation | Effect |
|---|---|
| `(add-text-segment builder code-bytes &key base-addr)` | `__TEXT` segment holding the code. Byte order is preserved exactly. |
| `(add-data-segment builder data-bytes &key base-addr)` | Read-write `__DATA` segment. |
| `(add-data-const-segment builder const-bytes &key base-addr)` | Read-only `__DATA_CONST` (`r--` max and init protections), for string literals and constant pools. |
| `(add-symbol builder name &key value type sect)` | Appends to the symbol table. |
| `(add-relocation builder offset symbol-name &key pcrel length extern type section)` | Relocation against `symbol-name` at section-relative `offset`. `type` defaults to `+x86-64-reloc-branch+`; pass a GOT or ARM64 page relocation type as needed. |
| `(add-entry-point builder offset)` | `LC_MAIN` at file `offset`. |

## The ELF64 builder

```lisp
(make-elf64-executable &key (machine +elf-machine-x86-64+) (entry-point 0))
```

| Operation | Effect |
|---|---|
| `(elf64-add-load-segment builder vaddr memsz &key flags filesz align)` | `PT_LOAD` over `[vaddr, vaddr+memsz)`. `filesz` defaults to `memsz` (no `.bss` tail), `align` to 4 KiB, `flags` to `PF_R \| PF_X`. |
| `(elf64-add-gnu-stack-segment builder &optional flags)` | `PT_GNU_STACK`, defaulting to RW with no exec. Linux requires it for a non-executable stack. |
| `(elf64-add-rodata-bytes builder bytes)` | Appends constants to `.rodata`, returning the section offset. Allocated but not writable, so the mapping can protect them. |
| `(elf64-add-rodata-string builder string)` | Adds to mergeable `.rodata.str`, returning the section offset. |
| `(elf64-add-got-entry builder symbol-name)` | Reserves an 8-byte GOT slot in `.data`, returning its offset. |
| `(elf64-add-plt-stub builder symbol-name)` | Appends a conservative x86-64 PLT-style jump stub. |

## The PE32+ builder

```lisp
(make-pe32+-builder &key (arch :x86-64) dll-p (subsystem :console) image-base)
```

`arch` is `:x86-64`, `:arm64` or `:aarch64`.

| Operation | Effect |
|---|---|
| `(pe-add-text-bytes builder bytes)` | Sets the `.text` payload. |
| `(pe-add-rdata-bytes builder bytes)` | Sets the `.rdata` payload. |
| `(pe-add-data-bytes builder bytes)` | Sets the `.data` payload. |
| `(pe-add-import builder dll-name function-names)` | Imports from a DLL. |
| `(pe-add-export builder name rva &key ordinal)` | Exports `name` at a precise RVA. |
| `(pe-add-base-relocation builder rva)` | One `IMAGE_REL_BASED_DIR64` entry. |
| `(pe-finalize builder)` | Assembles the image and returns a byte vector. |

`(pe-x86-64-stack-adjustment stack-argument-count)` returns the byte count to
reserve before a Windows x86-64 call: 32 bytes of shadow space, plus stack
arguments, plus padding to keep RSP 16-byte aligned at the call boundary.

## Universal binary slices

```lisp
(make-mach-o-fat-slice &key cputype cpusubtype (align 14) bytes)
```

`align` is a power of two exponent, defaulting to 14 (16 KiB). Accessors:
`mach-o-fat-slice-cputype`, `-cpusubtype`, `-align`, `-bytes`.

## Debug and unwind information

### `build-dwarf-debug-sections`

```lisp
(build-dwarf-debug-sections compile-unit)
```

Builds the `.debug_info`, `.debug_abbrev`, `.debug_line`, `.debug_str` and
`.debug_loc` payloads.

### `build-dwarf-eh-frame`

```lisp
(build-dwarf-eh-frame fde-list
                      &key (code-alignment-factor 1) (data-alignment-factor -8)
                           (return-address-register +dwarf-reg-x86-64-rip+))
```

Builds a `.eh_frame` payload from a list of FDEs, each describing a protected PC
range and optional frame-state transitions. The emitted CIE uses augmentation
string `zPLR`, x86-64 data alignment `-8`, and RIP (DWARF register 16) as the
return-address register.

### `build-dwarf-eh-lsda`

```lisp
(build-dwarf-eh-lsda call-sites)
```

Builds a compact Itanium ABI LSDA. LPStart and TType encodings are
`DW_EH_PE_omit`; the call-site table is ULEB128 tuples of start, length,
landing-pad and action. The trailing action/type extension is cl-cc-specific and
lets a personality routine check Common Lisp condition types without C++ RTTI
objects.

### FDE and call-site records

```lisp
(make-dwarf-eh-fde &key initial-location address-range instructions personality lsda)
(make-dwarf-eh-call-site &key start length landing-pad action (type t) cleanup-p)
```

Accessors: `dwarf-eh-fde-personality`, `dwarf-eh-fde-lsda`,
`dwarf-eh-call-site-start`, `-length`, `-landing-pad`, `-action`, `-type`.

## Optimization and verification

### `icf-merge-identical-functions`

```lisp
(icf-merge-identical-functions functions &key (enabled *icf-enabled*))
```

Merges byte-identical functions. `functions` may be `icf-function-section`
instances or plists/alists carrying `:name` and `:bytes`. Returns three values:
the kept functions, a name-to-canonical hash table, and the number merged.
Bytes are compared for equality after hashing, so a hash collision cannot fold
code that is not in fact identical.

### `elf64-verify-wx`

```lisp
(elf64-verify-wx segments)
```

Signals an error if any `PT_LOAD` segment is both writable and executable. It
verifies; it does not repair.

## Buffers and serialization

### `with-output-to-vector`

```lisp
(with-output-to-vector (stream-var) &body body)
```

Binds `stream-var` to a byte-accumulator closure and returns the collected bytes
as a `(simple-array (unsigned-byte 8) (*))`. Call the closure with one byte at a
time.

### Primitives

```lisp
(align-up value alignment)         ; => value rounded up to a multiple of alignment
(serialize-uint32-le value buffer)
(serialize-uint64-le value buffer)
```

The two serializers append to a `byte-buffer`. All three declare
`(optimize (speed 3) (safety 1))`, so their argument type declarations are
checked at runtime.

## Wire-record structures

These mirror on-disk records field for field. Each has a `make-` constructor and
one reader per slot; only the slots are listed.

| Structure | Slots |
|---|---|
| `mach-header` | `magic` `cputype` `cpusubtype` `filetype` `ncmds` `sizeofcmds` `flags` `reserved` |
| `segment-command` | `cmd` `cmdsize` `segname` `vmaddr` `vmsize` `fileoff` `filesize` `maxprot` `initprot` `nsects` `flags` `sections` |
| `section` | `sectname` `segname` `addr` `size` `offset` `align` `reloff` `nreloc` `flags` `reserved1` `reserved2` `reserved3` |
| `entry-point-command` | `cmd` `cmdsize` `entryoff` `stacksize` |
| `relocation-info` | `r-address` `r-symbolnum` `r-pcrel` `r-length` `r-extern` `r-type` |
| `symtab-command`, `dysymtab-command`, `dylib-command`, `dyld-info-command`, `linkedit-data-command`, `nlist` | see `src/macho-serialize.lisp` |
| `mach-o-builder`, `pe-builder`, `pe-section`, `pe-import`, `pe-export` | builder state; use the operations above rather than the slots |

## Variables

### `*binary-logger*`

Optional [cl-log-kit](https://nerima-lisp.github.io/cl-log-kit/) logger for
structured Mach-O, ELF and PE emission diagnostics. `nil` by default, which
keeps the library completely silent. Bind it to a `log-kit:make-logger` instance
to observe failure paths that cannot signal — a timed-out or failed `codesign`
invocation in `write-mach-o-file` being the motivating case.

### `*icf-enabled*`

When true, identical function-sized code sections may be folded by
`icf-merge-identical-functions`. `nil` by default.

### `*pe-x86-64-argument-registers*`

The Windows x86-64 ABI integer and pointer argument registers, in order.

## Constants

### Mach-O header

| Constant | Value |
|---|---|
| `+mh-magic-64+` | `#xFEEDFACF` |
| `+fat-magic+` | `#xCAFEBABE` (big-endian on disk) |
| `+mh-execute+` | 2 |
| `+mh-noundefs+` | 1 |
| `+mh-dyldlink+` | 4 |
| `+mh-pie+` | `#x200000` |

### CPU types

| Constant | Value |
|---|---|
| `+cpu-type-x86-64+`, `+fat-cputype-x86-64+` | `#x1000007` |
| `+cpu-type-arm64+`, `+fat-cputype-arm64+` | `#x100000C` |
| `+cpu-subtype-x86-64-all+` | 3 |
| `+cpu-subtype-arm64-all+` | 0 |

### Load commands

| Constant | Value |
|---|---|
| `+lc-symtab+` | 2 |
| `+lc-load-dylib+` | 12 |
| `+lc-segment-64+` | 25 |
| `+lc-code-signature+` | 29 |
| `+lc-dyld-info-only+` | `#x80000022` |
| `+lc-main+` | `#x80000028` |

### Section attributes and unwind

| Constant | Value |
|---|---|
| `+s-attr-pure-instructions+` | `#x80000000` |
| `+s-attr-some-instructions+` | `#x400` |
| `+compact-unwind-encoding-none+` | 0 |
| `+compact-unwind-x86-64-mode-stack-immd+` | `#x2000000` |

### Relocation types

| x86-64 | Value | ARM64 | Value |
|---|---|---|---|
| `+x86-64-reloc-unsigned+` | 0 | `+arm64-reloc-unsigned+` | 0 |
| `+x86-64-reloc-signed+` | 1 | `+arm64-reloc-branch26+` | 2 |
| `+x86-64-reloc-branch+` | 2 | `+arm64-reloc-page21+` | 3 |
| `+x86-64-reloc-got-load+` | 3 | `+arm64-reloc-pageoff12+` | 4 |

### PE32+

| Constant | Value |
|---|---|
| `+pe-magic-pe32-plus+` | `#x20B` |
| `+pe-machine-amd64+` | `#x8664` |
| `+pe-machine-arm64+` | `#xAA64` |
| `+pe-file-alignment+` | 512 |
| `+pe-section-alignment+` | 4096 |
| `+pe-x86-64-shadow-space-size+` | 32 |
