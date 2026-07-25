;;;; tests/macho-build-tests.lisp — Mach-O compression metadata tests
;;;;
;;;; Regression coverage for build-compression-metadata and the deterministic
;;;; (uncompressed) branch of the CPS compress-code-bytes-cps entry point
;;;; (macho-build-compression.lisp). The compressed branch depends on the
;;;; host SBCL exposing SB-EXT:COMPRESS, which is not guaranteed across CI
;;;; environments, so only the always-available give-up path is asserted
;;;; here; the compressed path is exercised indirectly by the byte-exact
;;;; Mach-O/ELF finalization tests elsewhere in this suite.
;;;;
;;;; Previously build-compression-metadata was only reachable via the
;;;; SB-EXT:COMPRESS-gated path, so a malformed docstring that split its body
;;;; into an unbound-variable reference went undetected until this file
;;;; exercised it directly.

(in-package :cl-cc-binary/test)

(describe "Mach-O compression metadata"

  (describe "build-compression-metadata"
    (it "writes the CLCZ magic, version, algorithm, and size fields in order"
      (let ((bytes (cl-cc/binary::build-compression-metadata 1 100 50)))
        (expect (= (length bytes) 28))
        (expect (subseq bytes 0 4) :to-equalp (map 'vector #'char-code "CLCZ"))
        (expect (= (%elf-u32le bytes 4) 1))
        (expect (= (%elf-u32le bytes 8) 1))
        (expect (= (%elf-u64le bytes 12) 100))
        (expect (= (%elf-u64le bytes 20) 50)))))

  (describe "compress-code-bytes-cps"
    (it "calls only on-uncompressed, with the original bytes, when compress is nil"
      (let* ((code (make-array 4 :element-type '(unsigned-byte 8) :initial-contents '(1 2 3 4)))
             (compressed-branch-ran nil))
        (let ((result (cl-cc/binary::compress-code-bytes-cps
                       code nil
                       (lambda (&rest ignored)
                         (declare (ignore ignored))
                         (setf compressed-branch-ran t))
                       (lambda () code))))
          (expect compressed-branch-ran :to-be-falsy)
          (expect result :to-be code))))

    (it-skip-if (cl-cc/binary::%find-sb-ext-compress)
        "calls only on-uncompressed when SB-EXT:COMPRESS is unavailable"
      (let* ((code (make-array 4 :element-type '(unsigned-byte 8) :initial-contents '(9 8 7 6)))
             (compressed-branch-ran nil))
        (let ((result (cl-cc/binary::compress-code-bytes-cps
                       code t
                       (lambda (&rest ignored)
                         (declare (ignore ignored))
                         (setf compressed-branch-ran t))
                       (lambda () code))))
          (expect compressed-branch-ran :to-be-falsy)
          (expect result :to-be code))))))
