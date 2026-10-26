(in-package :cl-cc/binary)

;;; FR-406: distribution compression support.
;;;
;;; SBCL versions that provide SB-EXT:COMPRESS can produce zlib/deflate payloads
;;; directly.  The current development SBCL used by CI may not expose that
;;; symbol, so compression is a capability probe rather than a reader-time
;;; dependency.  When unavailable or unsuccessful, callers fall back to the
;;; original byte vector and omit compressed section flags.

(defconstant +cl-cc-compression-none+ 0
  "No compression was applied.")

(defconstant +cl-cc-compression-zlib+ 1
  "zlib/deflate compression algorithm identifier.")

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

(defun build-compression-metadata (algorithm original-size compressed-size)
  "Build a compact CL-CC compression metadata header.

Header layout, little-endian:
  magic \"CLCZ\" | version u32 | algorithm u32 | original-size u64 |
  compressed-size u64."
  (with-byte-buffer (buf)
    (binary-buffer-write-bytes buf (map 'vector #'char-code "CLCZ"))
    (binary-buffer-write-u32le buf 1)
    (binary-buffer-write-u32le buf algorithm)
    (binary-buffer-write-u64le buf original-size)
    (binary-buffer-write-u64le buf compressed-size)))

(defun build-compressed-code-payload (compressed-bytes algorithm original-size compressed-size)
  "Return metadata followed by COMPRESSED-BYTES for a compressed code section."
  (let* ((metadata (build-compression-metadata algorithm original-size compressed-size))
         (payload (make-array (+ (length metadata) (length compressed-bytes))
                              :element-type '(unsigned-byte 8)
                              :initial-element 0)))
    (replace payload metadata :start1 0)
    (replace payload compressed-bytes :start1 (length metadata))
    payload))
