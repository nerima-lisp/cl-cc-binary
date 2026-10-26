;;;; packages/binary/src/conditions.lisp — cl-cc-binary condition hierarchy
;;;
;;; Every condition cl-cc-binary signals derives from CL-CC-BINARY-ERROR, so a
;;; caller can catch every failure this package raises with one HANDLER-CASE
;;; clause. Each condition names the situation, not the mechanism, per
;;; CODING_STANDARD.md.

(in-package :cl-cc/binary/buffer)

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

