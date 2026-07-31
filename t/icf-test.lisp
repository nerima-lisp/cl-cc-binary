;;;; t/icf-test.lisp — Identical Code Folding (FR-607)
;;;;
;;;; icf.lisp had no test coverage at all before this file.

(in-package :cl-cc-binary/test)

(defun %icf-hex-digest (bytes)
  (string-downcase
   (with-output-to-string (out)
     (loop for byte across bytes
           do (format out "~2,'0x" byte)))))

(describe "icf-sha256"
  (it "matches the NIST test vector for the empty message"
    (expect (%icf-hex-digest (cl-cc/binary::icf-sha256 #()))
            :to-equal "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))

  (it "matches the NIST test vector for \"abc\""
    (expect (%icf-hex-digest (cl-cc/binary::icf-sha256 (map 'vector #'char-code "abc")))
            :to-equal "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))

  (it "returns a 32-byte digest for input spanning multiple 64-byte blocks"
    (let ((bytes (make-array 130 :element-type '(unsigned-byte 8) :initial-element 65)))
      (expect (length (cl-cc/binary::icf-sha256 bytes)) :to-be 32)))

  (it-property "always returns a 32-byte digest regardless of input length"
      ((bytes (gen-vector (gen-integer :min 0 :max 255) :min-length 0 :max-length 200)))
    (expect (length (cl-cc/binary::icf-sha256 bytes)) :to-be 32))

  (it-property "is deterministic: hashing the same bytes twice gives the same digest"
      ((bytes (gen-vector (gen-integer :min 0 :max 255) :min-length 0 :max-length 200)))
    (expect (cl-cc/binary::icf-sha256 bytes) :to-equalp (cl-cc/binary::icf-sha256 bytes))))

(describe "icf-code-hash"
  (it "returns the same digest for the same bytes and references"
    (let ((bytes #(1 2 3 4)))
      (expect (cl-cc/binary::icf-code-hash bytes '((:call . "foo")))
              :to-equalp (cl-cc/binary::icf-code-hash bytes '((:call . "foo"))))))

  (it "returns a different digest when the bytes differ"
    (expect (cl-cc/binary::icf-code-hash #(1 2 3 4))
            :not :to-equalp (cl-cc/binary::icf-code-hash #(1 2 3 5))))

  (it "returns a different digest when the references differ"
    (expect (cl-cc/binary::icf-code-hash #(1 2 3 4) '((:call . "foo")))
            :not :to-equalp (cl-cc/binary::icf-code-hash #(1 2 3 4) '((:call . "bar"))))))

(describe "icf-merge-identical-functions"
  (it "keeps every function unchanged and self-redirected when disabled"
    (let ((fns (list (cl-cc/binary::make-icf-function-section :name "a" :bytes #(1 2))
                     (cl-cc/binary::make-icf-function-section :name "b" :bytes #(1 2)))))
      (multiple-value-bind (kept redirects folded) (cl-cc/binary:icf-merge-identical-functions fns)
        (expect kept :to-equal fns)
        (expect (gethash "a" redirects) :to-equal "a")
        (expect (gethash "b" redirects) :to-equal "b")
        (expect folded :to-be 0))))

  (it "folds two byte-identical functions into one, redirecting the second to the first"
    (let ((fns (list (cl-cc/binary::make-icf-function-section :name "a" :bytes #(#x90 #xc3))
                     (cl-cc/binary::make-icf-function-section :name "b" :bytes #(#x90 #xc3)))))
      (multiple-value-bind (kept redirects folded)
          (cl-cc/binary:icf-merge-identical-functions fns :enabled t)
        (expect (length kept) :to-be 1)
        (expect (cl-cc/binary::icf-function-section-name (first kept)) :to-equal "a")
        (expect (gethash "a" redirects) :to-equal "a")
        (expect (gethash "b" redirects) :to-equal "a")
        (expect folded :to-be 1))))

  (it "does not fold functions with different bytes"
    (let ((fns (list (cl-cc/binary::make-icf-function-section :name "a" :bytes #(#x90))
                     (cl-cc/binary::make-icf-function-section :name "b" :bytes #(#xc3)))))
      (multiple-value-bind (kept redirects folded)
          (cl-cc/binary:icf-merge-identical-functions fns :enabled t)
        (declare (ignore redirects))
        (expect (length kept) :to-be 2)
        (expect folded :to-be 0))))

  (it "does not fold functions with identical bytes but different references"
    (let ((fns (list (cl-cc/binary::make-icf-function-section
                       :name "a" :bytes #(#x90) :references '((:call . "x")))
                     (cl-cc/binary::make-icf-function-section
                       :name "b" :bytes #(#x90) :references '((:call . "y"))))))
      (multiple-value-bind (kept redirects folded)
          (cl-cc/binary:icf-merge-identical-functions fns :enabled t)
        (declare (ignore redirects))
        (expect (length kept) :to-be 2)
        (expect folded :to-be 0))))

  (it "never folds a function marked linkable-distinct-p even when byte-identical"
    (let ((fns (list (cl-cc/binary::make-icf-function-section :name "a" :bytes #(#x90))
                     (cl-cc/binary::make-icf-function-section
                       :name "b" :bytes #(#x90) :linkable-distinct-p t))))
      (multiple-value-bind (kept redirects folded)
          (cl-cc/binary:icf-merge-identical-functions fns :enabled t)
        (expect (length kept) :to-be 2)
        (expect (gethash "b" redirects) :to-equal "b")
        (expect folded :to-be 0))))

  (it "accepts plist entries carrying :name and :bytes"
    (let ((fns (list (list :name "a" :bytes #(#x90))
                     (list :name "b" :bytes #(#x90)))))
      (multiple-value-bind (kept redirects folded)
          (cl-cc/binary:icf-merge-identical-functions fns :enabled t)
        (expect (length kept) :to-be 1)
        (expect (gethash "b" redirects) :to-equal "a")
        (expect folded :to-be 1))))

  (it "accepts alist entries carrying (:name . x) and (:bytes . y)"
    (let ((fns (list (list (cons :name "a") (cons :bytes #(#x90)))
                     (list (cons :name "b") (cons :bytes #(#x90))))))
      (multiple-value-bind (kept redirects folded)
          (cl-cc/binary:icf-merge-identical-functions fns :enabled t)
        (expect (length kept) :to-be 1)
        (expect (gethash "b" redirects) :to-equal "a")
        (expect folded :to-be 1)))))
