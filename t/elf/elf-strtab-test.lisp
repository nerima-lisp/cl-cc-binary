;;;; t/elf-strtab-test.lisp — ELF string table builder (src/elf-strtab.lisp)
;;;;
;;;; strtab-add had no dedicated test at all before this file, despite being
;;;; the primitive every ELF section-name, symbol-name, and DWARF string
;;;; table in this package is built from.

(in-package :cl-cc-binary/test)

(describe "make-strtab / strtab-add / strtab-bytes"

  (it "pre-inserts the empty string at offset 0"
    (let ((st (cl-cc/binary::make-strtab)))
      (expect (= (cl-cc/binary::strtab-add st "") 0))))

  (it "returns offset 1 for the first non-empty string added"
    (let ((st (cl-cc/binary::make-strtab)))
      (expect (= (cl-cc/binary::strtab-add st ".text") 1))))

  (it "returns the same offset when the same string is added twice"
    (let* ((st (cl-cc/binary::make-strtab))
           (first (cl-cc/binary::strtab-add st ".text"))
           (second (cl-cc/binary::strtab-add st ".text")))
      (expect (= first second))))

  (it "does not grow strtab-bytes on a repeated add"
    (let ((st (cl-cc/binary::make-strtab)))
      (cl-cc/binary::strtab-add st ".text")
      (let ((size-after-first (length (cl-cc/binary::strtab-bytes st))))
        (cl-cc/binary::strtab-add st ".text")
        (expect (= (length (cl-cc/binary::strtab-bytes st)) size-after-first)))))

  (it "gives distinct strings distinct offsets"
    (let* ((st (cl-cc/binary::make-strtab))
           (a (cl-cc/binary::strtab-add st ".text"))
           (b (cl-cc/binary::strtab-add st ".data")))
      (expect (not (= a b)))))

  (it-property "a NUL-terminated read back from the returned offset recovers the added string"
      ((name (gen-string :min-length 1 :max-length 16)))
    (let* ((st (cl-cc/binary::make-strtab))
           (offset (cl-cc/binary::strtab-add st name))
           (bytes (cl-cc/binary::strtab-bytes st)))
      (expect (string= (%elf-c-string bytes offset) name))))

  (it-property "adding the same string twice always returns the same offset"
      ((name (gen-string :min-length 0 :max-length 16)))
    (let ((st (cl-cc/binary::make-strtab)))
      (expect (= (cl-cc/binary::strtab-add st name)
                 (cl-cc/binary::strtab-add st name))))))
