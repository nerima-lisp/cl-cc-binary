;;;; cl-cc-binary.asd — binary-format emitters for the cl-cc compiler.
;;;;
;;;; Both systems live in this one file. System names are written as strings so
;;;; that they do not depend on the reader's current package, and so that a grep
;;;; for a system name has exactly one spelling to match.

(in-package #:asdf-user)

(defsystem "cl-cc-binary"
  :description "cl-cc binary-format emitters — Mach-O, ELF, PE and WebAssembly module bytes"
  :long-description "Object-file emission for the cl-cc Common Lisp compiler:
byte buffers, constant pools, Mach-O (including universal/fat) and ELF writers,
PE tables, GOT/PLT construction, DWARF sections, W^X memory protection and
patchable function entries. SBCL-only. A leaf system: it depends on no other
cl-cc package."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/nerima-lisp/cl-cc-binary"
  :bug-tracker "https://github.com/nerima-lisp/cl-cc-binary/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cc-binary.git")
  ;; cl-log-kit: optional structured diagnostics for otherwise-silent failure
  ;; paths (a timed-out or failed codesign call in WRITE-MACH-O-FILE). Silent
  ;; unless a caller binds CL-CC/BINARY:*BINARY-LOGGER*. This is the system's
  ;; only dependency; DEPENDENCY_POLICY.md caps an L3 package at depth 1.
  :depends-on ("cl-log-kit")
  :pathname "src"
  :serial t
  :components
  ((:file "package")
   (:file "binary-struct")
   (:file "binary-writer")
   (:file "macho")
   (:file "macho-buffer")
   (:file "macho-fat")
   (:file "macho-serialize")
   (:file "macho-build")
   (:file "macho-build-compression")
   (:file "macho-build-assemble")
   (:file "elf")
   (:file "icf")
   (:file "got-plt")
   (:file "patchable-entry")
   (:file "dwarf")
   (:file "dwarf-eh")
   (:file "elf-emit")
   (:file "elf-emit-relocatable")
   (:file "elf-emit-executable")
   (:file "dwarf-dwo")
   (:file "pe")
   (:file "pe-tables")
   (:file "pe-finalize")
   (:file "wasm"))
  :in-order-to ((test-op (test-op "cl-cc-binary/test"))))

(defsystem "cl-cc-binary/test"
  :description "Test system for cl-cc-binary."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/nerima-lisp/cl-cc-binary"
  :bug-tracker "https://github.com/nerima-lisp/cl-cc-binary/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cc-binary.git")
  ;; cl-weave: the org's test framework. cl-log-kit is named explicitly because
  ;; t/macho-build-assemble-logging-test.lisp builds a logger directly rather than reaching it
  ;; through cl-cc-binary.
  :depends-on ("cl-cc-binary" "cl-weave" "cl-log-kit")
  :pathname "t"
  :serial t
  :components
  ((:file "package")
   (:file "macho-buffer-test")
   (:file "elf-constant-pool-test")
   (:file "elf-emit-executable-wxorx-test")
   (:file "architecture-test")
   (:file "got-plt-test")
   (:file "macho-fat-test")
   (:file "macho-build-compression-test")
   (:file "macho-build-assemble-entry-point-test")
   (:file "macho-build-assemble-logging-test")
   (:file "patchable-entry-test"))
  :perform (test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-weave :run-all
                                       :reporter :spec :pass-with-no-tests nil)
               (error "cl-cc-binary tests failed"))))
