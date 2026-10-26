;;;; src/binary-writer.lisp — flat sequential-field writer generation
;;;;
;;;; DEFINE-BINARY-WRITER separates a flat wire record's DATA (the ordered
;;;; list of field widths and value forms) from the LOGIC of writing them
;;;; sequentially to a raw binary buffer, for records that are not backed by a
;;;; DEFSTRUCT (see DEFINE-BINARY-STRUCT for those) — ELF section/program
;;;; headers, PE COFF headers, and similar records assembled directly from
;;;; caller-supplied values rather than struct slots.

(in-package :cl-cc/binary)

(defun %binary-writer-field-form (width buffer-var value)
  (ecase width
    (:u8  `(binary-buffer-write-u8 ,buffer-var ,value))
    (:u16 `(binary-buffer-write-u16le ,buffer-var ,value))
    (:u32 `(binary-buffer-write-u32le ,buffer-var ,value))
    (:u64 `(binary-buffer-write-u64le ,buffer-var ,value))
    (:s64 `(binary-buffer-write-s64le ,buffer-var ,value))
    (:pad `(binary-buffer-write-pad ,buffer-var ,value))
    (:raw value)))

(defmacro define-binary-writer (name lambda-list docstring &body fields)
  "Define function NAME writing FIELDS to its first LAMBDA-LIST parameter.

Each element of FIELDS is (WIDTH VALUE-FORM), written in order. WIDTH is
:U8, :U16, :U32, :U64, or :S64 for a fixed-width little-endian value; :PAD,
where VALUE-FORM is a zero-byte count; or :RAW, where VALUE-FORM is a
complete call spliced in unevaluated by the macro, for fields that already
write more than one byte-width value (such as a fixed-width name)."
  (let ((buffer-var (first lambda-list)))
    `(defun ,name ,lambda-list
       ,docstring
       ,@(loop for (width value) in fields
               collect (%binary-writer-field-form width buffer-var value)))))
