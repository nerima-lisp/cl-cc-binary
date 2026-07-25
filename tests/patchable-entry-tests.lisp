;;;; tests/patchable-entry-tests.lisp — Patchable entry tests
;;;;
;;;; Tests for: emit-nop-sequence, emit-patchable-function-entry,
;;;; and with-patchable-entries (patchable-entry.lisp / FR-584).

(in-package :cl-cc-binary/test)

(defun %nop-bytes (count)
  "Return emitted NOP bytes for COUNT as a list."
  (coerce (cl-cc/binary::with-output-to-vector (stream)
            (cl-cc/binary::emit-nop-sequence stream count))
          'list))

(describe "Patchable function entry NOP emission (FR-584)"

  (describe "emit-nop-sequence"
    (it-each ((1) (2) (3) (4) (5) (6) (7) (8) (9) (10) (18))
        "emits exactly ~A bytes total"
        (count)
      (expect (= (length (%nop-bytes count)) count)))

    (it-each ((1 (#x90))
              (2 (#x66 #x90))
              (3 (#x0F #x1F #x00))
              (4 (#x0F #x1F #x40 #x00))
              (5 (#x0F #x1F #x44 #x00 #x00))
              (6 (#x66 #x0F #x1F #x44 #x00 #x00))
              (7 (#x0F #x1F #x80 #x00 #x00 #x00 #x00))
              (8 (#x0F #x1F #x84 #x00 #x00 #x00 #x00 #x00))
              (9 (#x66 #x0F #x1F #x84 #x00 #x00 #x00 #x00 #x00)))
        "emits the canonical encoding for a single ~A-byte NOP"
        (count expected)
      (expect (%nop-bytes count) :to-equal expected))

    (it "decomposes count=10 into a 9-byte NOP then a 1-byte NOP"
      (let ((bytes (%nop-bytes 10)))
        (expect (= (length bytes) 10))
        (expect (subseq bytes 0 9) :to-equal '(#x66 #x0F #x1F #x84 #x00 #x00 #x00 #x00 #x00))
        (expect (subseq bytes 9 10) :to-equal '(#x90))))

    (it "emits nothing for count=0"
      (expect (%nop-bytes 0) :to-equal '())))

  (describe "emit-patchable-function-entry"
    (it "emits 3 NOP bytes when before=3, after=0"
      (let ((bytes (coerce
                    (cl-cc/binary::with-output-to-vector (stream)
                      (let ((cl-cc/binary::*patchable-entry-before* 3)
                            (cl-cc/binary::*patchable-entry-after* 0))
                        (cl-cc/binary::emit-patchable-function-entry stream)))
                    'list)))
        (expect (= (length bytes) 3))
        (expect bytes :to-equal '(#x0F #x1F #x00))))

    (it "emits 2 NOP bytes when before=0, after=2"
      (let ((bytes (coerce
                    (cl-cc/binary::with-output-to-vector (stream)
                      (let ((cl-cc/binary::*patchable-entry-before* 0)
                            (cl-cc/binary::*patchable-entry-after* 2))
                        (cl-cc/binary::emit-patchable-function-entry stream)))
                    'list)))
        (expect (= (length bytes) 2))
        (expect bytes :to-equal '(#x66 #x90))))

    (it "emits 8 NOP bytes total when before=5, after=3"
      (let ((bytes (coerce
                    (cl-cc/binary::with-output-to-vector (stream)
                      (let ((cl-cc/binary::*patchable-entry-before* 5)
                            (cl-cc/binary::*patchable-entry-after* 3))
                        (cl-cc/binary::emit-patchable-function-entry stream)))
                    'list)))
        (expect (= (length bytes) 8))
        (expect (subseq bytes 0 5) :to-equal '(#x0F #x1F #x44 #x00 #x00))
        (expect (subseq bytes 5 8) :to-equal '(#x0F #x1F #x00))))

    (it "emits nothing when before=0 and after=0"
      (let ((bytes (coerce
                    (cl-cc/binary::with-output-to-vector (stream)
                      (let ((cl-cc/binary::*patchable-entry-before* 0)
                            (cl-cc/binary::*patchable-entry-after* 0))
                        (cl-cc/binary::emit-patchable-function-entry stream)))
                    'list)))
        (expect bytes :to-equal '()))))

  (describe "with-patchable-entries"
    (it "binds *patchable-entry-before* and *patchable-entry-after*"
      (cl-cc/binary::with-patchable-entries (:before 4 :after 2)
        (expect (= cl-cc/binary::*patchable-entry-before* 4))
        (expect (= cl-cc/binary::*patchable-entry-after* 2))))

    (it "restores the original variable values after the body runs"
      (let ((before-saved cl-cc/binary::*patchable-entry-before*)
            (after-saved  cl-cc/binary::*patchable-entry-after*))
        (cl-cc/binary::with-patchable-entries (:before 7 :after 5)
          (expect (= cl-cc/binary::*patchable-entry-before* 7)))
        (expect (= cl-cc/binary::*patchable-entry-before* before-saved))
        (expect (= cl-cc/binary::*patchable-entry-after* after-saved)))))

  (describe "patch-function-entry"
    (it "signals an error when the patch is larger than the reserved bytes"
      (let ((cl-cc/binary::*patchable-entry-before* 2))
        (expect (lambda () (cl-cc/binary::patch-function-entry 0 #(#x90 #x90 #x90)))
                :to-throw 'error)))))
