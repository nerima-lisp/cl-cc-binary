;;;; src/wasm/wasm-module.lisp — WebAssembly wire-format serialization
;;;
;;; Callers supply wire-format value bytes, indices, exports, function bodies,
;;; and names. IR lowering and textual WAT emission remain outside this feature.
;;;
;;; Reference: https://webassembly.github.io/spec/core/binary/index.html

(in-package :cl-cc/binary/wasm)

;;; General wire-format helpers

(defun %wasm-byte-vector (bytes)
  (unless (and (typep bytes 'sequence) (not (stringp bytes)))
    (error "Expected a byte sequence, got ~S" bytes))
  (map '(simple-array (unsigned-byte 8) (*))
       (lambda (byte)
         (check-type byte (unsigned-byte 8))
         byte)
       bytes))

(defun %wasm-write-uleb128 (buffer value)
  (check-type value (integer 0 *))
  (binary-buffer-write-bytes buffer (encode-uleb128 value)))

(defun %wasm-write-name (buffer name)
  (check-type name string)
  (let ((bytes (sb-ext:string-to-octets name :external-format :utf-8)))
    (let ((size (length bytes))) (check-type size (unsigned-byte 32)))
    (%wasm-write-uleb128 buffer (length bytes))
    (binary-buffer-write-bytes buffer bytes)))
;;; Section framing and module header
(defun encode-wasm-section (section-id payload)
  "Frame PAYLOAD as a standard section with SECTION-ID."
  (check-type section-id (unsigned-byte 8))
  (let ((bytes (%wasm-byte-vector payload)))
    (let ((size (length bytes))) (check-type size (unsigned-byte 32)))
    (with-byte-buffer (buffer)
      (binary-buffer-write-u8 buffer section-id)
      (%wasm-write-uleb128 buffer (length bytes))
      (binary-buffer-write-bytes buffer bytes))))
(defun encode-wasm-custom-section (name payload)
  "Encode a custom section NAME containing the byte sequence PAYLOAD."
  (check-type name string)
  (encode-wasm-section
   0
   (with-byte-buffer (buffer)
     (%wasm-write-name buffer name)
     (binary-buffer-write-bytes buffer (%wasm-byte-vector payload)))))
(defun encode-wasm-module (sections)
  "Write the module header followed by already-framed SECTIONS in caller order."
  (check-type sections list)
  (with-byte-buffer (buffer)
    (binary-buffer-write-bytes buffer #(#x00 #x61 #x73 #x6d #x01 #x00 #x00 #x00))
    (dolist (section sections)
      (binary-buffer-write-bytes buffer (%wasm-byte-vector section)))))
;;; Standard section layouts
(defun %wasm-write-valtype-vector (buffer types)
  (check-type types list)
  (let ((size (length types))) (check-type size (unsigned-byte 32)))
  (%wasm-write-uleb128 buffer (length types))
  (dolist (type types)
    (check-type type (unsigned-byte 8))
    (binary-buffer-write-u8 buffer type)))
(defun encode-wasm-type-section (function-types)
  "Encode FUNCTION-TYPES as a standard type section.
Each type is a two-element list of (PARAMETER-TYPE-BYTES RESULT-TYPE-BYTES)."
  (check-type function-types list)
  (let ((size (length function-types))) (check-type size (unsigned-byte 32)))
  (encode-wasm-section
   1
   (with-byte-buffer (buffer)
     (%wasm-write-uleb128 buffer (length function-types))
     (dolist (function-type function-types)
       (unless (and (listp function-type) (= (length function-type) 2))
         (error "Expected a parameter/result pair, got ~S" function-type))
       (binary-buffer-write-u8 buffer #x60)
       (%wasm-write-valtype-vector buffer (first function-type))
       (%wasm-write-valtype-vector buffer (second function-type))))))
(defun encode-wasm-function-section (type-indices)
  "Encode the Function section from TYPE-INDICES, each a type index."
  (check-type type-indices list)
  (let ((size (length type-indices))) (check-type size (unsigned-byte 32)))
  (encode-wasm-section
   3
   (with-byte-buffer (buffer)
     (%wasm-write-uleb128 buffer (length type-indices))
     (dolist (type-index type-indices)
       (check-type type-index (unsigned-byte 32))
       (%wasm-write-uleb128 buffer type-index)))))
(defun encode-wasm-export-section (exports)
  "Encode EXPORTS as (NAME KIND INDEX) wire records in the Export section."
  (check-type exports list)
  (let ((size (length exports))) (check-type size (unsigned-byte 32)))
  (encode-wasm-section
   7
   (with-byte-buffer (buffer)
     (%wasm-write-uleb128 buffer (length exports))
     (dolist (export exports)
       (unless (and (listp export) (= (length export) 3))
         (error "Expected a name/kind/index export record, got ~S" export))
       (destructuring-bind (name kind index) export
         (check-type name string)
         (check-type kind (integer 0 4))
         (check-type index (unsigned-byte 32))
         (%wasm-write-name buffer name)
         (binary-buffer-write-u8 buffer kind)
         (%wasm-write-uleb128 buffer index))))))
(defun encode-wasm-code-section (function-bodies)
  "Encode FUNCTION-BODIES as raw byte sequences in the Code section."
  (check-type function-bodies list)
  (let ((size (length function-bodies))) (check-type size (unsigned-byte 32)))
  (encode-wasm-section
   10
   (with-byte-buffer (buffer)
     (%wasm-write-uleb128 buffer (length function-bodies))
     (dolist (body function-bodies)
       (let ((bytes (%wasm-byte-vector body)))
         (let ((size (length bytes))) (check-type size (unsigned-byte 32)))
         (%wasm-write-uleb128 buffer (length bytes))
         (binary-buffer-write-bytes buffer bytes))))))
;;; Standard name custom section
(defun encode-wasm-name-section (module-name function-names
                                  &key (local-names nil) (label-names nil))
  "Encode the standard module, function, local, and label name subsections.
Name records are (INDEX . STRING); local and label records are
(FUNCTION-INDEX . ((INDEX . STRING) ...)). Returns the full custom section."
  (check-type module-name string)
  (labels ((write-name-assocs (buffer entries)
             (check-type entries list)
             (let ((size (length entries))) (check-type size (unsigned-byte 32)))
             (%wasm-write-uleb128 buffer (length entries))
             (dolist (entry entries)
               (unless (and (consp entry) (stringp (cdr entry)))
                 (error "Expected an index/name record, got ~S" entry))
               (check-type (car entry) (unsigned-byte 32))
               (%wasm-write-uleb128 buffer (car entry))
               (%wasm-write-name buffer (cdr entry))))
           (write-indirect-name-map (buffer entries)
             (check-type entries list)
             (let ((size (length entries))) (check-type size (unsigned-byte 32)))
             (%wasm-write-uleb128 buffer (length entries))
             (dolist (entry entries)
               (unless (and (consp entry) (listp (cdr entry)))
                 (error "Expected a function/name-list record, got ~S" entry))
               (check-type (car entry) (unsigned-byte 32))
               (%wasm-write-uleb128 buffer (car entry))
               (write-name-assocs buffer (cdr entry))))
           (name-subsection (id writer)
             (let ((payload (with-byte-buffer (subsection)
                              (funcall writer subsection))))
               (let ((size (length payload))) (check-type size (unsigned-byte 32)))
               (with-byte-buffer (subsection)
                 (binary-buffer-write-u8 subsection id)
                 (%wasm-write-uleb128 subsection (length payload))
                 (binary-buffer-write-bytes subsection payload)))))
    (encode-wasm-custom-section
     "name"
     (with-byte-buffer (buffer)
       (binary-buffer-write-bytes
        buffer
        (name-subsection 0 (lambda (subsection)
                             (%wasm-write-name subsection module-name))))
       (binary-buffer-write-bytes
        buffer
        (name-subsection 1 (lambda (subsection)
                             (write-name-assocs subsection function-names))))
       (binary-buffer-write-bytes
        buffer
        (name-subsection 2 (lambda (subsection)
                             (write-indirect-name-map subsection local-names))))
       (binary-buffer-write-bytes
        buffer
        (name-subsection 3 (lambda (subsection)
                             (write-indirect-name-map subsection label-names))))))))

