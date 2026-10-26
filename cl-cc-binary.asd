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
  :version "0.2.2"
  :homepage "https://github.com/nerima-lisp/cl-cc-binary"
  :bug-tracker "https://github.com/nerima-lisp/cl-cc-binary/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-cc-binary.git")
  ;; cl-log-kit: optional structured diagnostics for otherwise-silent failure
  ;; paths (a timed-out or failed codesign call in WRITE-MACH-O-FILE). Silent
  ;; unless a caller binds CL-CC/BINARY:*BINARY-LOGGER*.
  ;; cl-process-kit: timeout-guarded subprocess execution (SIGTERM->SIGKILL
  ;; escalation) for the codesign invocation in WRITE-MACH-O-FILE, replacing a
  ;; hand-rolled SB-EXT:RUN-PROGRAM + SB-EXT:WITH-TIMEOUT pair with the org's
  ;; dedicated toolkit for exactly this problem. L2, depth 2; pulls in
  ;; cl-boundary-kit transitively, bringing this system's depth to 3 (DEPENDENCY_POLICY.md
  ;; caps L3 at depth 4).
  :depends-on ("cl-log-kit" "cl-process-kit")
  :pathname "src"
  :serial t
  :components
  ((:module "buffer" :pathname "buffer" :serial t :components
  ((:file "package") (:file "conditions") (:file "binary-struct")
   (:file "binary-writer") (:file "binary-buffer") (:file "string-table")))
   (:module "macho" :pathname "macho" :serial t :components
  ((:file "package") (:file "macho") (:file "macho-fat") (:file "macho-serialize")
   (:file "macho-build") (:file "macho-build-compression")
   (:file "macho-build-text-segment") (:file "macho-build-dyld")
   (:file "macho-build-layout") (:file "macho-build-serialize")
   (:file "macho-build-assemble") (:file "macho-codesign")))
   (:module "dwarf" :pathname "dwarf" :serial t :components
  ((:file "package") (:file "dwarf") (:file "dwarf-eh") (:file "dwarf-dwo")))
   (:module "elf" :pathname "elf" :serial t :components
  ((:file "package") (:file "elf-constants") (:file "elf") (:file "elf-emit")
   (:file "elf-emit-relocatable") (:file "elf-emit-executable")
   (:file "elf-compile")))
   (:module "linking" :pathname "linking" :serial t :components
  ((:file "package") (:file "got-plt") (:file "icf") (:file "patchable-entry")))
   (:module "pe" :pathname "pe" :serial t :components
  ((:file "package") (:file "pe") (:file "pe-tables") (:file "pe-finalize")))
   (:module "wasm" :pathname "wasm" :serial t :components
  ((:file "package") (:file "wasm") (:file "wasm-module")))
   (:file "facade-package"))
  :in-order-to ((test-op (test-op "cl-cc-binary/test"))))

(defsystem "cl-cc-binary/test"
  :description "Test system for cl-cc-binary."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.2.2"
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
  ((:module "buffer" :pathname "buffer" :serial t :components
  ((:file "package") (:file "byte-reader-test-support")
   (:file "macho-buffer-test")))
   (:module "macho" :pathname "macho" :serial t :components
  ((:file "package") (:file "macho-architecture-test")
   (:file "macho-constant-pool-test") (:file "macho-build-assemble-entry-point-test")
   (:file "macho-build-assemble-logging-test") (:file "macho-build-compression-test")
   (:file "macho-build-executes-test") (:file "macho-fat-test")))
   (:module "dwarf" :pathname "dwarf" :serial t :components
  ((:file "package") (:file "dwarf-test") (:file "dwarf-eh-test")
   (:file "dwarf-dwo-test")))
   (:module "elf" :pathname "elf" :serial t :components
  ((:file "package") (:file "elf-image-test-support")
   (:file "dwo-container-test") (:file "elf-strtab-test")
   (:file "elf-builder-test") (:file "elf-constant-pool-test")
   (:file "elf-emit-executable-wxorx-test") (:file "elf-compile-executes-test")
   (:file "architecture-test")))
   (:module "linking" :pathname "linking" :serial t :components
  ((:file "package") (:file "got-plt-test") (:file "icf-test")
   (:file "patchable-entry-test")))
   (:module "pe" :pathname "pe" :serial t :components
  ((:file "package") (:file "pe-finalize-test")))
   (:module "wasm" :pathname "wasm" :serial t :components
  ((:file "package") (:file "wasm-test") (:file "wasm-module-test"))))
  :perform (test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-weave :run-all
                                       :reporter :spec :pass-with-no-tests nil)
               (error "cl-cc-binary tests failed"))))
