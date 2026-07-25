;;;; t/architecture-tests.lisp — cross-architecture and ET_DYN coverage
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
    (let* ((bytes (cl-cc/binary::compile-to-elf64-exec #(195) nil :type :dyn))
           (e-type (%elf-u16le bytes 16))
           (phoff (%elf-u64le bytes 32))
           (phentsize (%elf-u16le bytes 54))
           (phnum (%elf-u16le bytes 56))
           (has-pt-dynamic nil))
      (expect e-type :to-be cl-cc/binary::+elf-type-dyn+)
      (dotimes (i phnum)
        (when (= (%elf-u32le bytes (+ phoff (* i phentsize))) cl-cc/binary::+pt-dynamic+)
          (setf has-pt-dynamic t)))
      (expect has-pt-dynamic :to-be-truthy)))

  (it "sets e_type to ET_DYN and includes PT_INTERP for a default (non-shared) PIE"
    (let* ((bytes (cl-cc/binary::compile-to-elf64-exec #(195) nil :type :dyn))
           (phoff (%elf-u64le bytes 32))
           (phentsize (%elf-u16le bytes 54))
           (phnum (%elf-u16le bytes 56))
           (has-pt-interp nil))
      (dotimes (i phnum)
        (when (= (%elf-u32le bytes (+ phoff (* i phentsize))) cl-cc/binary::+pt-interp+)
          (setf has-pt-interp t)))
      (expect has-pt-interp :to-be-truthy)))

  (it "omits PT_INTERP for a :shared library (no runtime interpreter needed)"
    (let* ((bytes (cl-cc/binary::compile-to-elf64-exec #(195) nil :type :shared))
           (phoff (%elf-u64le bytes 32))
           (phentsize (%elf-u16le bytes 54))
           (phnum (%elf-u16le bytes 56))
           (has-pt-interp nil))
      (dotimes (i phnum)
        (when (= (%elf-u32le bytes (+ phoff (* i phentsize))) cl-cc/binary::+pt-interp+)
          (setf has-pt-interp t)))
      (expect has-pt-interp :to-be-falsy))))
