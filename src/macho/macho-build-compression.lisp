(in-package :cl-cc/binary/macho)

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
