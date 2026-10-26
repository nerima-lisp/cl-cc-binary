;;;; t/elf-constant-pool-test.lisp — FR-724 constant pool tests

(in-package #:cl-cc/binary/elf/test)

(defun %constpool-ub8 (bytes)
  (make-array (length bytes)
              :element-type '(unsigned-byte 8)
              :initial-contents bytes))

(describe "FR-724 constant pool and literal deduplication"

  (it "deduplicates identical .rodata byte sequences into one shared offset"
    (let* ((builder (cl-cc/binary/elf::make-elf64-object))
           (first (cl-cc/binary/elf:elf64-add-rodata-bytes builder (%constpool-ub8 '(1 2 3 4))))
           (second (cl-cc/binary/elf:elf64-add-rodata-bytes builder (%constpool-ub8 '(9 8))))
           (third (cl-cc/binary/elf:elf64-add-rodata-bytes builder (%constpool-ub8 '(1 2 3 4)))))
      (expect (= first third))
      (expect (zerop first))
      (expect (= second 4))
      (expect (= (length (cl-cc/binary/elf::elf64-rodata-buf builder)) 6))))

  (it "dedupes string literals into SHF_MERGE|SHF_STRINGS .rodata.str"
    (let* ((builder (cl-cc/binary/elf:make-elf64-executable))
           (first (cl-cc/binary/elf:elf64-add-rodata-string builder "hello"))
           (second (cl-cc/binary/elf:elf64-add-rodata-string builder "world"))
           (third (cl-cc/binary/elf:elf64-add-rodata-string builder "hello")))
      (cl-cc/binary/elf::elf64-add-text-bytes builder #(195))
      (expect (= first third))
      (expect (zerop first))
      (expect (= second 6))
      (let* ((flags (%elf-section-flags-by-name (cl-cc/binary/elf::elf64-finalize builder)))
             (string-flags (gethash ".rodata.str" flags)))
        (expect string-flags :to-be (logior cl-cc/binary/elf::+shf-alloc+
                                            cl-cc/binary/elf::+shf-merge+
                                            cl-cc/binary/elf::+shf-strings+))
        (expect (zerop (logand string-flags cl-cc/binary/elf::+shf-write+)))
        (expect (zerop (logand string-flags cl-cc/binary/elf::+shf-execinstr+)))))))
