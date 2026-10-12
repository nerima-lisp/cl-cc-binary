# Changelog

## 0.2.2 - Unreleased

### Changes

- Align arm64 Mach-O layout to 16 KiB pages and keep user segments and
  `__LINKEDIT` ranges separate.
- Map the Mach-O header and code within `__TEXT`, with segment protections
  appropriate to text, writable data, and read-only constants.
- Stage Mach-O output before signing. A missing signing program, timeout, or
  nonzero exit signals `macho-codesign-error` without replacing an existing
  target. Passing `:codesign nil` explicitly requests unsigned output.
- Export signing-error readers for the filename and failure reason.

### Verification scope

The package suite reported 209 passing tests, one skipped test, and
1,566 assertions. The macOS arm64 Mach-O fixture exited with its expected
status 42; strict code-signature verification exited 0.

These checks cover that fixture and the package suite, not execution of every
ELF, PE, WebAssembly, or Mach-O output. They do not establish Linux/Nix readiness
or full-compiler self-hosting.
