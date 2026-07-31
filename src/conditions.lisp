;;;; packages/binary/src/conditions.lisp — cl-cc-binary condition hierarchy
;;;
;;; Every condition cl-cc-binary signals derives from CL-CC-BINARY-ERROR, so a
;;; caller can catch every failure this package raises with one HANDLER-CASE
;;; clause. Each condition names the situation, not the mechanism, per
;;; CODING_STANDARD.md.

(in-package :cl-cc/binary)

(define-condition cl-cc-binary-error (error) ()
  (:documentation "Base condition for every error cl-cc-binary signals."))

(define-condition value-out-of-range (cl-cc-binary-error)
  ((operation :initarg :operation :reader value-out-of-range-operation)
   (value :initarg :value :reader value-out-of-range-value)
   (low :initarg :low :reader value-out-of-range-low)
   (high :initarg :high :reader value-out-of-range-high))
  (:report (lambda (condition stream)
             (format stream "~A supports values ~D..~D, got ~D"
                     (value-out-of-range-operation condition)
                     (value-out-of-range-low condition)
                     (value-out-of-range-high condition)
                     (value-out-of-range-value condition))))
  (:documentation "A DWARF operand (register number, encoded delta, ...) fell
outside the range its encoding form supports."))

(define-condition elf-wx-violation (cl-cc-binary-error)
  ((segment :initarg :segment :reader elf-wx-violation-segment))
  (:report (lambda (condition stream)
             (format stream "ELF W^X violation: writable executable PT_LOAD segment ~S"
                     (elf-wx-violation-segment condition))))
  (:documentation "An ELF PT_LOAD segment requested both PF_W and PF_X."))

(define-condition patchable-entry-overflow (cl-cc-binary-error)
  ((size :initarg :size :reader patchable-entry-overflow-size)
   (reserved :initarg :reserved :reader patchable-entry-overflow-reserved))
  (:report (lambda (condition stream)
             (format stream "Patch size ~D exceeds reserved ~D bytes"
                     (patchable-entry-overflow-size condition)
                     (patchable-entry-overflow-reserved condition))))
  (:documentation "A patch payload did not fit the bytes reserved for it at a
patchable function entry."))

(define-condition pe-section-not-found (cl-cc-binary-error)
  ((name :initarg :name :reader pe-section-not-found-name))
  (:report (lambda (condition stream)
             (format stream "Missing PE section ~A" (pe-section-not-found-name condition))))
  (:documentation "PE-FINALIZE looked up a section by name that the builder
never added."))

(define-condition macho-unknown-architecture (cl-cc-binary-error)
  ((arch :initarg :arch :reader macho-unknown-architecture-arch))
  (:report (lambda (condition stream)
             (format stream "Unknown Mach-O arch: ~S" (macho-unknown-architecture-arch condition))))
  (:documentation "MAKE-MACH-O-BUILDER received an :ARCH keyword this backend
does not implement."))
