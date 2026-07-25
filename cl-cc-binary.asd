;;;; cl-cc-binary.asd — independent ASDF system for binary-format emitters
;;;;
;;;; Phase 2 of the package-by-feature monorepo migration. Files live in the
;;;; :cl-cc/binary package and are accessed by callers via the qualified
;;;; cl-cc/binary: prefix. Truly leaf — no dependencies on other cl-cc systems.

(asdf:defsystem :cl-cc-binary
  :description "cl-cc binary-format emitters — Mach-O, ELF, WebAssembly module bytes"
  :author "takeokunn"
  :license "MIT"
  :version "0.1.0"
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
     (:file "wasm")))
