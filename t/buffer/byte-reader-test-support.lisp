;;;; t/buffer/byte-reader-test-support.lisp — shared little-endian byte-reading helpers
;;;;
;;;; Read raw bytes back out of the format images the test suite builds, so a
;;;; test can assert on the actual serialized layout rather than trusting the
;;;; builder's own bookkeeping. Loaded first so every test file that needs
;;;; them can rely on load order rather than redeclaring them.

(in-package :cl-cc/binary/buffer/test)

(defun %read-u16le (bytes offset)
  (+ (aref bytes offset)
     (ash (aref bytes (1+ offset)) 8)))

(defun %read-u32le (bytes offset)
  (+ (aref bytes offset)
     (ash (aref bytes (1+ offset)) 8)
     (ash (aref bytes (+ offset 2)) 16)
     (ash (aref bytes (+ offset 3)) 24)))

(defun %read-u64le (bytes offset)
  (loop for i below 8
        sum (ash (aref bytes (+ offset i)) (* 8 i))))

(defun %read-c-string (bytes offset)
  (with-output-to-string (out)
    (loop for i from offset below (length bytes)
          for byte = (aref bytes i)
          until (zerop byte)
          do (write-char (code-char byte) out))))

