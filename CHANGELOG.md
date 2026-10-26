# Changelog

## 0.2.2 - Unreleased

- Align arm64 Mach-O layout to 16 KiB pages and keep user-provided segments and
  `__LINKEDIT` ranges separate.
- Map the Mach-O header and code within `__TEXT`, with segment protections
  appropriate to text, writable data, and read-only constants.
- Stage Mach-O output before signing. A missing signing program, timeout, or
  nonzero exit signals `macho-codesign-error` without replacing an existing
  target. Passing `:codesign nil` explicitly requests unsigned output.
- Export `macho-codesign-error-filename` and `macho-codesign-error-reason`
  readers.

### Binary encoder facade additions

- Reexport `make-byte-buffer`, `buffer-write-byte`, `buffer-write-bytes`, and
  `buffer-get-bytes` from `cl-cc/binary` for code-generation clients.
- Reexport the DWARF constructors `make-dwarf-compile-unit`,
  `make-dwarf-subprogram`, and `make-dwarf-variable-location`, plus the
  `dwarf-debug-sections-info`, `dwarf-debug-sections-abbrev`,
  `dwarf-debug-sections-line`, `dwarf-debug-sections-str`, and
  `dwarf-debug-sections-loc` readers.

### Verification scope

The package suite, run with `sbcl --script run-tests.lisp`, reported 209
passing tests, one skipped test, and 1,566 assertions. The
`macho-build-executes-test.lisp` fixture's generated program exited with its
expected status 42.

These checks cover that fixture and the package suite, not execution of every
ELF, PE, WebAssembly, or Mach-O output.
