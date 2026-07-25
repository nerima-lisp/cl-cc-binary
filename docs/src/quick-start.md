# Quick Start

This walks one task all the way through: taking twelve bytes of x86-64 machine
code and writing them out as a Linux ELF executable. The last section shows the
whole thing as a single form.

Everything below was run against version 0.1.0; the byte counts are the actual
output.

## The input

cl-cc-binary does not generate code. It takes code you already have, as a
`(simple-array (unsigned-byte 8) (*))`, and wraps it in a container. Here is a
program that exits with status 0:

```lisp
(asdf:load-system "cl-cc-binary")

(defparameter *code*
  ;; mov edi, 0   ; status
  ;; mov eax, 60  ; __NR_exit
  ;; syscall
  (coerce #(#xbf #x00 #x00 #x00 #x00
            #xb8 #x3c #x00 #x00 #x00
            #x0f #x05)
          '(simple-array (unsigned-byte 8) (*))))
```

Use exactly that type. The top-level entry points do not check their argument,
but several primitives below them declare it, and a value that is merely
sequence-like will either be rejected deep in the call stack or produce an
object file whose byte counts do not match its headers.

## A relocatable object

`compile-to-elf64` produces an `ET_REL` object — the thing you would hand to
`ld`. Its second argument is a list of relocations, as `(byte-offset .
symbol-name)` pairs; this program calls nothing, so the list is empty.

```lisp
(defparameter *object* (cl-cc/binary:compile-to-elf64 *code* '()))

(length *object*)
;; => 1024

(subseq *object* 0 4)
;; => #(127 69 76 70)      ; 0x7F 'E' 'L' 'F'
```

## An executable

`compile-to-elf64-exec` produces something the kernel can run directly. For
x86-64 it prepends a small `_start` wrapper before your code, so the entry
point is set up before control reaches byte zero of `*code*`.

```lisp
(defparameter *exe* (cl-cc/binary:compile-to-elf64-exec *code* '() :type :exec))

(length *exe*)
;; => 13184
```

Pass `:type :dyn` instead for a position-independent executable or shared
object:

```lisp
(length (cl-cc/binary:compile-to-elf64-exec *code* '() :type :dyn))
;; => 13848
```

## Writing it out

```lisp
(cl-cc/binary:write-elf64-file "/tmp/exit0" *exe*)
```

`write-elf64-file` writes bytes and nothing else — it does not set the execute
bit, so `chmod +x` is on you before a Linux kernel will run the result.

## The whole thing

```lisp
(asdf:load-system "cl-cc-binary")

(let ((code (coerce #(#xbf #x00 #x00 #x00 #x00
                      #xb8 #x3c #x00 #x00 #x00
                      #x0f #x05)
                    '(simple-array (unsigned-byte 8) (*)))))
  (cl-cc/binary:write-elf64-file
   "/tmp/exit0"
   (cl-cc/binary:compile-to-elf64-exec code '() :type :exec)))
```

## The other formats

The same twelve bytes, in the three other containers. Each has its own entry
point rather than a shared abstraction; see
[Core Concepts](core-concepts.md#two-shapes-of-api) for why.

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

## Next

- [Core Concepts](core-concepts.md) for buffers, builders and diagnostics.
- [API Reference](api-reference.md) for symbols, relocations and debug sections.
