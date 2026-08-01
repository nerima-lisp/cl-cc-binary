# Examples

## The other formats

[Getting Started](../getting-started.md) writes twelve bytes of x86-64 machine
code out as a Linux ELF executable. Here are the same twelve bytes in the three
other containers. Each has its own entry point rather than a shared
abstraction; see [Core Concepts](core-concepts.md#two-shapes-of-api) for why.

The byte counts are the actual output of version 0.2.0, with `*code*` bound as
in [Getting Started](../getting-started.md#the-input).

```lisp
;; Mach-O executable, via the builder API
(let ((builder (cl-cc/binary:make-mach-o-builder :arm64)))
  (cl-cc/binary:add-text-segment builder *code*)
  (cl-cc/binary:add-entry-point builder 0)
  (length (cl-cc/binary:build-mach-o builder *code*)))
;; => 8192

;; PE32+ console executable
(length (cl-cc/binary:compile-to-pe *code* '() :subsystem :console))
;; => 2048

;; Mach-O universal binary with two slices
(let ((x86 (cl-cc/binary:make-mach-o-fat-slice
            :cputype cl-cc/binary:+fat-cputype-x86-64+
            :cpusubtype cl-cc/binary:+cpu-subtype-x86-64-all+
            :bytes *code*))
      (arm (cl-cc/binary:make-mach-o-fat-slice
            :cputype cl-cc/binary:+fat-cputype-arm64+
            :cpusubtype cl-cc/binary:+cpu-subtype-arm64-all+
            :bytes *code*)))
  (length (cl-cc/binary:build-mach-o-fat-binary (list x86 arm))))
;; => 32780
```

See [API Reference](../reference/api.md) for symbols, relocations and debug
sections in each container.
