# Binary format glossary

This glossary is a routing index to the feature packages and selected public types and functions. See the [API reference](api.md) for signatures and usage.

## buffer

Byte buffers are adjustable byte vectors shared by the emitters. ELF string tables use those buffers to store deduplicated, NUL-terminated strings and return each string's byte offset. The `value-out-of-range` condition reports when an encoded operand is outside the range supported by its format.

- Package: `cl-cc/binary/buffer`
- Key types: `byte-buffer`, `strtab-builder`, `value-out-of-range`
- Key functions: `make-byte-buffer`, `binary-buffer-write-u8`, `binary-buffer-write-bytes`, `binary-buffer-to-array`, `buffer-get-bytes`

## elf

ELF emits relocatable objects and executable files. A Global Offset Table (GOT) holds address slots for symbols; Procedure Linkage Table (PLT) stubs provide calls through those slots. ELF also checks that load segments do not have both write and execute permissions. The `elf-wx-violation` condition reports a segment that requests both.

- Package: `cl-cc/binary/elf`
- Key types: `elf-wx-violation`
- Key functions: `compile-to-elf64`, `compile-to-elf64-exec`, `elf64-add-got-entry`, `elf64-add-plt-stub`, `elf64-verify-wx`, `write-elf64-file`

## macho

Mach-O builds object files and universal binaries from headers, segments, sections, and load commands.

- Package: `cl-cc/binary/macho`
- Key types: `mach-o-builder`, `mach-o-fat-slice`, `mach-header`, `segment-command`, `section`
- Key functions: `make-mach-o-builder`, `build-mach-o`, `build-mach-o-fat-binary`, `write-mach-o-file`, `write-mach-o-fat-file`

## pe

PE builds executable images with sections, imports, exports, and base relocations. The `pe-section-not-found` condition reports when finalization needs a section that the builder was not given.

- Package: `cl-cc/binary/pe`
- Key types: `pe-builder`, `pe-section`, `pe-import`, `pe-export`, `pe-section-not-found`
- Key functions: `make-pe32+-builder`, `compile-to-pe`, `pe-add-text-bytes`, `pe-add-import`, `pe-finalize`, `write-pe-file`

## dwarf

DWARF builds debug and unwind section payloads that ELF emitters place inside object files and executables. It also provides split-DWARF skeleton data and GNU debuglink records for separate debug files. This package exports no public type names.

- Package: `cl-cc/binary/dwarf`
- Key types: None.
- Key functions: `build-dwarf-debug-sections`, `build-dwarf-skeleton-cu`, `build-dwarf-eh-frame`, `build-gnu-debuglink-section`, `dwarf-crc32`

## linking

Identical Code Folding (ICF) merges byte-identical functions. A patchable function entry reserves NOP bytes for runtime patches; `patchable-entry-overflow` signals when a patch payload is larger than that reservation. Its `patchable-entry-overflow-size` and `patchable-entry-overflow-reserved` readers return the payload size and reserved byte count. ELF owns the format-specific GOT and PLT emitters.

- Package: `cl-cc/binary/linking`
- Key types: `patchable-entry-overflow`
- Key functions: `icf-merge-identical-functions`, `patchable-entry-overflow-reserved`, `patchable-entry-overflow-size`

## wasm

Wasm provides binary encoders for signed and unsigned LEB128 values. `portable-double-float-bits` returns an IEEE 754 binary64 bit pattern as an integer, not bytes in host byte order. This package exports no public type names.

- Package: `cl-cc/binary/wasm`
- Key types: None.
- Key functions: `encode-uleb128`, `encode-sleb128`, `portable-double-float-bits`
