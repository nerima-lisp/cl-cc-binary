;;;; t/architecture-test.lisp — cross-architecture and ET_DYN coverage
;;;;
;;;; Every existing test exercised only :x86-64 and ET_EXEC output, leaving
;;;; the :arm64 code paths and the ET_DYN (PIE/shared-object) branch of
;;;; elf64-finalize-executable completely untested. describe-each drives the
;;;; same assertions across both Mach-O and ELF architecture variants instead
;;;; of duplicating near-identical test bodies by hand.

(in-package :cl-cc-binary/test)

(defun %elf64-machine-of (bytes)
  (%elf-u16le bytes 18))

;;; describe-each/it-each embed each case-tuple element as literal data
;;; rather than evaluating it, so named constants cannot be looked up in the
;;; table itself; the table only selects the architecture keyword, and each
;;; expected constant is resolved by ordinary evaluation inside the case.

(describe-each ((:x86-64) (:arm64))
    "make-mach-o-builder for ~A"
    (arch)
  (it "sets the header cputype and cpusubtype for the requested architecture"
    (let* ((builder (cl-cc/binary:make-mach-o-builder arch))
           (header (cl-cc/binary::mach-o-builder-header builder))
           (expected-cputype (ecase arch
                               (:x86-64 cl-cc/binary:+cpu-type-x86-64+)
                               (:arm64 cl-cc/binary:+cpu-type-arm64+)))
           (expected-cpusubtype (ecase arch
                                  (:x86-64 cl-cc/binary:+cpu-subtype-x86-64-all+)
                                  (:arm64 cl-cc/binary:+cpu-subtype-arm64-all+))))
      (expect (cl-cc/binary::mach-header-cputype header) :to-be expected-cputype)
      (expect (cl-cc/binary::mach-header-cpusubtype header) :to-be expected-cpusubtype))))

(describe-each ((:x86-64) (:arm64))
    "compile-to-elf64 for ~A"
    (arch)
  (it "writes the requested e_machine into the ELF header"
    (let ((bytes (cl-cc/binary::compile-to-elf64 #(195) nil :arch arch))
          (expected-e-machine (ecase arch
                                (:x86-64 cl-cc/binary::+elf-machine-x86-64+)
                                (:arm64 cl-cc/binary::+elf-machine-aarch64+))))
      (expect (%elf64-machine-of bytes) :to-be expected-e-machine))))

(describe "ET_DYN (PIE) ELF executables"
  (it "sets e_type to ET_DYN and includes a PT_DYNAMIC program header"
    (let ((bytes (cl-cc/binary::compile-to-elf64-exec #(195) nil :type :dyn)))
      (expect (%elf-u16le bytes 16) :to-be cl-cc/binary::+elf-type-dyn+)
      (expect (%elf-has-phdr-type-p bytes cl-cc/binary::+pt-dynamic+) :to-be-truthy)))

  (it "sets e_type to ET_DYN and includes PT_INTERP for a default (non-shared) PIE"
    (let ((bytes (cl-cc/binary::compile-to-elf64-exec #(195) nil :type :dyn)))
      (expect (%elf-has-phdr-type-p bytes cl-cc/binary::+pt-interp+) :to-be-truthy)))

  (it "omits PT_INTERP for a :shared library (no runtime interpreter needed)"
    (let ((bytes (cl-cc/binary::compile-to-elf64-exec #(195) nil :type :shared)))
      (expect (%elf-has-phdr-type-p bytes cl-cc/binary::+pt-interp+) :to-be-falsy))))

(describe "%elf64-section-header-indices"
  (it "for a static executable with no .rodata.str: 11 fixed sections, no ET_DYN group"
    (multiple-value-bind (n-sections dynsym-idx dynstr-idx symtab-idx strtab-idx
                          debug-line-idx shstrtab-idx)
        (cl-cc/binary::%elf64-section-header-indices nil nil 0)
      (expect n-sections :to-be 11)
      (expect dynsym-idx :to-be-null)
      (expect dynstr-idx :to-be-null)
      (expect symtab-idx :to-be 7)
      (expect strtab-idx :to-be 8)
      (expect debug-line-idx :to-be 9)
      (expect shstrtab-idx :to-be 10)))

  (it "for a static executable with .rodata.str present: every index after it shifts by 1"
    (multiple-value-bind (n-sections dynsym-idx dynstr-idx symtab-idx strtab-idx
                          debug-line-idx shstrtab-idx)
        (cl-cc/binary::%elf64-section-header-indices nil nil 1)
      (declare (ignore dynsym-idx dynstr-idx))
      (expect n-sections :to-be 12)
      (expect symtab-idx :to-be 8)
      (expect strtab-idx :to-be 9)
      (expect debug-line-idx :to-be 10)
      (expect shstrtab-idx :to-be 11)))

  (it "for a PIE (ET_DYN with PT_INTERP): 17 sections, dynsym/dynstr placed before symtab"
    (multiple-value-bind (n-sections dynsym-idx dynstr-idx symtab-idx strtab-idx
                          debug-line-idx shstrtab-idx)
        (cl-cc/binary::%elf64-section-header-indices t t 0)
      (expect n-sections :to-be 17)
      (expect dynsym-idx :to-be 8)
      (expect dynstr-idx :to-be 9)
      (expect symtab-idx :to-be 13)
      (expect strtab-idx :to-be 14)
      (expect debug-line-idx :to-be 15)
      (expect shstrtab-idx :to-be 16)))

  (it "for a shared library (ET_DYN, no PT_INTERP) with .rodata.str present"
    (multiple-value-bind (n-sections dynsym-idx dynstr-idx symtab-idx strtab-idx
                          debug-line-idx shstrtab-idx)
        (cl-cc/binary::%elf64-section-header-indices t nil 1)
      (expect n-sections :to-be 17)
      (expect dynsym-idx :to-be 8)
      (expect dynstr-idx :to-be 9)
      (expect symtab-idx :to-be 14)
      (expect strtab-idx :to-be 15)
      (expect debug-line-idx :to-be 16)
      (expect shstrtab-idx :to-be 17))))
