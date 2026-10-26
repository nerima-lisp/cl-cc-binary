;;;; packages/binary/src/macho-buffer.lisp — Byte Buffer, Utilities, and Serialization
;;;;
;;;; Contains: binary-buffer operations, byte-buffer CLOS class, alignment
;;;; utility, string-to-ascii conversion, and serialization primitives.
;;;;
;;;; Load order: after macho.lisp (constants and struct definitions).

(in-package :cl-cc/binary/buffer)

;;; Byte Buffer - Pure Common Lisp Implementation

(defun make-binary-buffer (&optional (initial-size 4096))
  "Create a fresh shared binary buffer as an adjustable byte vector."
  (make-array initial-size
              :element-type '(unsigned-byte 8)
              :adjustable t
              :fill-pointer 0))

(defun binary-buffer-write-u8 (buffer byte)
  (declare (type (array (unsigned-byte 8) (*)) buffer)
           (type (unsigned-byte 8) byte))
  (vector-push-extend byte buffer))

(defun binary-buffer-write-u16le (buffer value)
  (binary-buffer-write-u8 buffer (logand value #xFF))
  (binary-buffer-write-u8 buffer (logand (ash value -8) #xFF)))

(defun binary-buffer-write-u32le (buffer value)
  (binary-buffer-write-u8 buffer (logand value #xFF))
  (binary-buffer-write-u8 buffer (logand (ash value -8) #xFF))
  (binary-buffer-write-u8 buffer (logand (ash value -16) #xFF))
  (binary-buffer-write-u8 buffer (logand (ash value -24) #xFF)))

(defun binary-buffer-write-u64le (buffer value)
  (binary-buffer-write-u32le buffer (logand value #xFFFFFFFF))
  (binary-buffer-write-u32le buffer (logand (ash value -32) #xFFFFFFFF)))

(defun binary-buffer-write-s64le (buffer value)
  (binary-buffer-write-u64le buffer (logand value #xFFFFFFFFFFFFFFFF)))

(defun binary-buffer-write-bytes (buffer bytes)
  (etypecase bytes
    (list (dolist (b bytes) (binary-buffer-write-u8 buffer b)))
    (vector (loop for b across bytes do (binary-buffer-write-u8 buffer b)))))

(defun binary-buffer-write-pad (buffer n)
  (loop repeat n
        do (binary-buffer-write-u8 buffer 0)))

(defun binary-buffer-pad-and-write (buffer target-offset bytes)
  "Pad BUFFER with zero bytes up to TARGET-OFFSET, then write BYTES.

The layout idiom every finalized output buffer repeats once per section: pad
from the current length to that section's known file offset, then place its
bytes."
  (binary-buffer-write-pad buffer (- target-offset (length buffer)))
  (binary-buffer-write-bytes buffer bytes))

(defun binary-buffer-to-array (buffer)
  (make-array (length buffer)
              :element-type '(unsigned-byte 8)
              :initial-contents buffer))

(defmacro with-byte-buffer ((buffer-var) &body body)
  "Bind BUFFER-VAR to a fresh binary buffer, evaluate BODY for its writes to
that buffer, and return the accumulated bytes as a simple-array.

Every section/payload builder in this system starts with a fresh buffer and
ends by converting it to an array; this macro is that shape, so a builder
reads as only the writes that make it distinct."
  `(let ((,buffer-var (make-binary-buffer 0)))
     ,@body
     (binary-buffer-to-array ,buffer-var)))

(defclass byte-buffer ()
  ((data :initarg :data
         :accessor byte-buffer-data
         :type (array (unsigned-byte 8) (*))
         :documentation "The underlying byte array."))
  (:documentation "A simple growable byte buffer for binary output."))

(defun make-byte-buffer (&optional (initial-size 4096))
  "Create a new byte buffer with INITIAL-SIZE capacity."
  (make-instance 'byte-buffer
                 :data (make-binary-buffer initial-size)))

(defun buffer-write-byte (buffer byte)
  "Write a single BYTE to BUFFER."
  (declare (type byte-buffer buffer)
           (type (unsigned-byte 8) byte))
  (binary-buffer-write-u8 (byte-buffer-data buffer) byte))

(defun buffer-write-bytes (buffer bytes)
  "Write a sequence of BYTES to BUFFER."
  (declare (type byte-buffer buffer))
  (binary-buffer-write-bytes (byte-buffer-data buffer) bytes))

(defun buffer-get-bytes (buffer)
  "Get the contents of BUFFER as a simple-array of (unsigned-byte 8)."
  (declare (type byte-buffer buffer))
  (binary-buffer-to-array (byte-buffer-data buffer)))

(defun buffer-pad-to (buffer target-offset)
  "Pad BUFFER with zero bytes up to TARGET-OFFSET."
  (declare (type byte-buffer buffer))
  (loop repeat (- target-offset (length (byte-buffer-data buffer)))
        do (buffer-write-byte buffer 0)))

;;; Utilities

(defun align-up (value alignment)
  "Align VALUE up to ALIGNMENT boundary."
  (declare (type (unsigned-byte 64) value)
           (type (unsigned-byte 64) alignment)
           (optimize (speed 3) (safety 1)))
  (* (ceiling value alignment) alignment))

(defun string-to-ascii-bytes (string)
  "Convert STRING to a vector of ASCII bytes."
  (declare (type string string))
  (let ((result (make-array (length string) :element-type '(unsigned-byte 8))))
    (loop for char across string
          for i from 0
          do (setf (aref result i) (char-code char)))
    result))

;;; Serialization Primitives

(defun serialize-uint32-le (value buffer)
  "Write 32-bit VALUE to BUFFER in little-endian byte order."
  (declare (type (unsigned-byte 32) value)
           (type byte-buffer buffer)
           (optimize (speed 3) (safety 1)))
  (buffer-write-byte buffer (logand value #xFF))
  (buffer-write-byte buffer (logand (ash value -8) #xFF))
  (buffer-write-byte buffer (logand (ash value -16) #xFF))
  (buffer-write-byte buffer (logand (ash value -24) #xFF)))

(defun serialize-uint64-le (value buffer)
  "Write 64-bit VALUE to BUFFER in little-endian byte order."
  (declare (type (unsigned-byte 64) value)
           (type byte-buffer buffer)
           (optimize (speed 3) (safety 1)))
  (serialize-uint32-le (logand value #xFFFFFFFF) buffer)
  (serialize-uint32-le (ash value -32) buffer))

(defun serialize-string-16 (string buffer)
  "Write STRING as 16-byte null-padded field to BUFFER."
  (declare (type string string)
           (type byte-buffer buffer)
           (optimize (speed 3) (safety 1)))
  (let ((bytes (string-to-ascii-bytes string)))
    (dotimes (i 16)
      (buffer-write-byte buffer (if (< i (length bytes)) (aref bytes i) 0)))))

(defun serialize-bytes (bytes buffer)
  "Write byte sequence BYTES to BUFFER."
  (declare (type (simple-array (unsigned-byte 8) (*)) bytes)
           (type byte-buffer buffer)
           (optimize (speed 3) (safety 1)))
  (buffer-write-bytes buffer bytes))

(defun elf64-pad-to-align (buf alignment)
  "Pad BUF with DW_CFA_nop bytes to ALIGNMENT."
  (loop while (not (zerop (mod (length buf) alignment)))
        do (elf-buf-u8 buf 0)))

(defun elf64-write-sleb128 (buf value)
  "Write VALUE as signed LEB128 to BUF."
  (loop with more = t
        with v = value
        while more do
          (let* ((byte (logand v #x7f))
                 (sign-set (not (zerop (logand byte #x40)))))
            (setf v (ash v -7))
            (setf more (not (or (and (zerop v) (not sign-set))
                                (and (= v -1) sign-set))))
            (elf-buf-u8 buf (if more (logior byte #x80) byte)))))

(defun elf64-write-uleb128 (buf value)
  "Write VALUE as unsigned LEB128 to BUF."
  (loop for v = value then (ash v -7)
        for byte = (logand v #x7f)
        do (elf-buf-u8 buf (if (zerop (ash v -7)) byte (logior byte #x80)))
        until (zerop (ash v -7))))

(defmacro with-output-to-vector ((stream-var) &body body)
  "Execute BODY with STREAM-VAR bound to a byte-accumulator closure.
Returns the collected bytes as a (simple-array (unsigned-byte 8) (*)).
STREAM-VAR is a function accepting a single (unsigned-byte 8) argument."
  (let ((bytes-sym (gensym "BYTES")))
    `(let* ((,bytes-sym '())
            (,stream-var (lambda (byte) (push byte ,bytes-sym))))
       ,@body
       (coerce (nreverse ,bytes-sym) '(simple-array (unsigned-byte 8) (*))))))

(in-package :cl-cc/binary/buffer)

(defun %ub8-vector (bytes)
  "Return BYTES as a simple unsigned-byte 8 vector."
  (coerce bytes '(simple-array (unsigned-byte 8) (*))))

(defun %find-sb-ext-compress ()
  "Return SB-EXT:COMPRESS when the host SBCL provides it, otherwise NIL."
  (let ((package (find-package "SB-EXT")))
    (when package
      (multiple-value-bind (symbol status) (find-symbol "COMPRESS" package)
        (when (and symbol status (fboundp symbol))
          (symbol-function symbol))))))

(defun compress-code-bytes-cps (code-bytes compress on-compressed on-uncompressed)
  "Attempt to compress CODE-BYTES via SB-EXT:COMPRESS, dispatching to a
continuation instead of returning a compress/don't-compress tagged union.

ON-COMPRESSED is called with (COMPRESSED-BYTES ORIGINAL-SIZE COMPRESSED-SIZE)
only when COMPRESS is true, SB-EXT:COMPRESS is available, and the result is
strictly smaller than CODE-BYTES. ON-UNCOMPRESSED is called with no arguments
in every other case: COMPRESS is false, SB-EXT:COMPRESS is unavailable,
compression signaled an error, or the compressed result did not shrink the
input. Exactly one continuation runs, and its return value becomes this
function's return value."
  (declare (type (simple-array (unsigned-byte 8) (*)) code-bytes))
  (flet ((give-up () (funcall on-uncompressed)))
    (if compress
        (let ((compress-fn (%find-sb-ext-compress))
              (original-size (length code-bytes)))
          (if compress-fn
              (handler-case
                  (let ((compressed (%ub8-vector (funcall compress-fn code-bytes))))
                    (if (< (length compressed) original-size)
                        (funcall on-compressed compressed original-size (length compressed))
                        (give-up)))
                (error () (give-up)))
              (give-up)))
        (give-up))))
