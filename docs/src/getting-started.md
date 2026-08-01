# Getting Started

cl-cc-binary is an ASDF system for SBCL. It is distributed as a Nix flake and
consumed as a source tree; there is no Quicklisp release.

## Requirements

- SBCL. The system uses `sb-ext` for optional code compression and is not
  portable to other implementations.
- [cl-log-kit](https://nerima-lisp.github.io/cl-log-kit/), a runtime
  dependency. It is required at load time but does nothing unless
  `cl-cc/binary:*binary-logger*` is bound; see
  [Core Concepts](guide/core-concepts.md#diagnostics).
- [cl-process-kit](https://nerima-lisp.github.io/cl-process-kit/), a runtime
  dependency that guards the `codesign` invocation in `write-mach-o-file`
  with a timeout. It pulls in `cl-boundary-kit` transitively.

## Flake input

Add the input, pinned to a release tag. A bare `github:nerima-lisp/cl-cc-binary`
follows the default branch, which means a push here can break your build
without warning.

```nix
# flake.nix
inputs.cl-cc-binary = {
  url = "github:nerima-lisp/cl-cc-binary/v0.2.0";
  flake = false;
};
```

`flake = false` pulls the source tree only. That is all ASDF needs, and it keeps
this repository's own inputs out of your `flake.lock`.

Put the resulting store path on `CL_SOURCE_REGISTRY` along with its runtime
dependencies and their own transitive dependencies (see this repository's
`flake.nix` for the full, current list):

```nix
CL_SOURCE_REGISTRY =
  "${cl-cc-binary}//:${cl-log-kit}//:${cl-date-kit}//:${cl-concurrent-kit}//"
  + ":${cl-host-kit}//:${cl-process-kit}//:${cl-boundary-kit}//:${self}//";
```

The trailing `//` tells ASDF to search the tree recursively.

## ASDF dependency

```lisp
(defsystem "your-system"
  :depends-on ("cl-cc-binary")
  ...)
```

## Verifying

```lisp
(asdf:load-system "cl-cc-binary")
(asdf:component-version (asdf:find-system "cl-cc-binary"))
;; => "0.2.0"
```

`cl-cc-binary.asd` is the single source of truth for the version: `flake.nix`
reads the `:version` form out of it, and the release workflow refuses to publish
a tag that disagrees with it.

## One task end to end

The rest of this page walks one task all the way through: taking twelve bytes
of x86-64 machine code and writing them out as a Linux ELF executable. The last
section shows the whole thing as a single form.

Everything below was run against version 0.2.0; the byte counts are the actual
output.

### The input

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

### A relocatable object

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

### An executable

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

### Writing it out

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

## Next steps

- [Examples](guide/examples.md) for the same bytes in the three other
  containers.
- [Core Concepts](guide/core-concepts.md) for buffers, builders and diagnostics.
- [API Reference](reference/api.md) for symbols, relocations and debug sections.
