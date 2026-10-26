;;;; src/binary-struct.lisp — struct + little-endian serializer generation
;;;;
;;;; DEFINE-BINARY-STRUCT separates a wire record's DATA (field name, default
;;;; value, and byte width) from the LOGIC that turns it into both a defstruct
;;;; and a field-by-field little-endian serializer, eliminating the
;;;; one-serialize-function-per-defstruct duplication that used to make up
;;;; most of macho-serialize.lisp. It only fits records whose fields serialize
;;;; in exactly their struct definition order with no bitpacking or
;;;; variable-length payloads; dylib-command (variable-length string),
;;;; relocation-info (bitpacked), and nlist (a narrower on-wire n-desc than
;;;; its declared slot width) stay hand-written.

(in-package :cl-cc/binary)

(defun %binary-struct-slot-type (width)
  (ecase width
    (:u8       '(unsigned-byte 8))
    (:u32      '(unsigned-byte 32))
    (:u64      '(unsigned-byte 64))
    (:string16 'string)))

(defun %binary-struct-accessor (struct-name slot-name)
  (intern (format nil "~A-~A" struct-name slot-name)))

(defun %binary-struct-serialize-form (width accessor-call buffer-var)
  (ecase width
    (:u8       `(buffer-write-byte ,buffer-var ,accessor-call))
    (:u32      `(serialize-uint32-le ,accessor-call ,buffer-var))
    (:u64      `(serialize-uint64-le ,accessor-call ,buffer-var))
    (:string16 `(serialize-string-16 ,accessor-call ,buffer-var))))

(defmacro define-binary-struct (name docstring fields &key extra-slots serializer-note)
  "Define struct NAME and function SERIALIZE-NAME from FIELDS.

Each element of FIELDS is (SLOT-NAME DEFAULT-VALUE WIRE-WIDTH), where
WIRE-WIDTH is :U8, :U32, :U64, or :STRING16. Fields are written to the
serializer's BUFFER argument in the order given, matching the generated
defstruct's slot order exactly. EXTRA-SLOTS are appended as ordinary defstruct
slot specs and take no part in serialization. SERIALIZER-NOTE, when given, is
appended to the generated serializer's docstring."
  (let* ((instance (intern "INSTANCE"))
         (buffer (intern "BUFFER"))
         (slot-forms (loop for (slot default width) in fields
                            collect `(,slot ,default :type ,(%binary-struct-slot-type width))))
         (serializer-name (intern (format nil "SERIALIZE-~A" name))))
    `(progn
       (defstruct ,name
         ,docstring
         ,@slot-forms
         ,@extra-slots)
       (defun ,serializer-name (,instance ,buffer)
         ,(format nil "Serialize ~A to BUFFER.~@[ ~A~]" name serializer-note)
         (declare (type ,name ,instance) (type byte-buffer ,buffer))
         ,@(loop for (slot nil width) in fields
                 collect (%binary-struct-serialize-form
                          width
                          `(,(%binary-struct-accessor name slot) ,instance)
                          buffer))))))
