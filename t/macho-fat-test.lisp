;;;; t/macho-fat-test.lisp

(in-package :cl-cc-binary/test)

(defun %read-file-bytes (path)
  "Return the contents of PATH as a fresh (unsigned-byte 8) vector."
  (with-open-file (in path :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence bytes in)
      bytes)))

(describe "FR-691 Mach-O universal/fat binary"

  (it "emits FAT_MAGIC and a slice table"
    (let* ((x86 (cl-cc/binary:make-mach-o-fat-slice
                 :cputype cl-cc/binary:+fat-cputype-x86-64+
                 :cpusubtype cl-cc/binary:+cpu-subtype-x86-64-all+
                 :align 2
                 :bytes (make-array 4 :element-type '(unsigned-byte 8)
                                       :initial-contents '(1 2 3 4))))
           (arm (cl-cc/binary:make-mach-o-fat-slice
                 :cputype cl-cc/binary:+fat-cputype-arm64+
                 :cpusubtype cl-cc/binary:+cpu-subtype-arm64-all+
                 :align 2
                 :bytes (make-array 4 :element-type '(unsigned-byte 8)
                                       :initial-contents '(5 6 7 8))))
           (bytes (cl-cc/binary:build-mach-o-fat-binary (list x86 arm))))
      (expect (subseq (coerce bytes 'list) 0 4) :to-equal '(#xCA #xFE #xBA #xBE))
      (expect (= (elt bytes 7) 2))
      (expect (> (length bytes) 48))))

  (it "write-mach-o-fat-file writes the same bytes build-mach-o-fat-binary returns"
    (let* ((slice (cl-cc/binary:make-mach-o-fat-slice
                   :cputype cl-cc/binary:+fat-cputype-x86-64+
                   :cpusubtype cl-cc/binary:+cpu-subtype-x86-64-all+
                   :align 2
                   :bytes (make-array 4 :element-type '(unsigned-byte 8)
                                        :initial-contents '(1 2 3 4))))
           (expected (cl-cc/binary:build-mach-o-fat-binary (list slice))))
      (uiop:with-temporary-file (:pathname path :type "bin")
        (cl-cc/binary:write-mach-o-fat-file path (list slice))
        (expect (%read-file-bytes path) :to-equalp expected)))))
