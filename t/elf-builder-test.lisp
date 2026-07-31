;;;; t/elf-builder-test.lisp — ELF64 builder accumulation API (src/elf.lisp)
;;;;
;;;; The elf64-builder's own accumulation methods (make-elf64-dynamic,
;;;; elf64-add-got-entry, elf64-add-plt-stub, elf64-add-needed-library,
;;;; elf64-add-reloc, elf64-add-global-symbol, elf64-add-load-segment,
;;;; elf64-add-gnu-stack-segment, elf64-add-gnu-relro-segment) were only ever
;;;; exercised indirectly through the full compile-to-elf64-exec pipeline. An
;;;; SB-COVER report showed elf.lisp at 49.8% expression coverage — the
;;;; lowest of any src/ file with real logic — with every one of these
;;;; builder methods flagged as never directly executed.

(in-package :cl-cc-binary/test)

(describe "make-elf64-object / make-elf64-executable / make-elf64-dynamic"
  (it "make-elf64-object defaults to ET_REL"
    (expect (cl-cc/binary::elf64-elf-type (cl-cc/binary::make-elf64-object))
            :to-be cl-cc/binary::+elf-type-rel+))

  (it "make-elf64-executable sets ET_EXEC and the given entry point"
    (let ((builder (cl-cc/binary:make-elf64-executable :entry-point #x401000)))
      (expect (cl-cc/binary::elf64-elf-type builder) :to-be cl-cc/binary::+elf-type-exec+)
      (expect (cl-cc/binary::elf64-entry-point builder) :to-be #x401000)))

  (it "make-elf64-dynamic sets ET_DYN, the given interpreter, and shared-object flag"
    (let ((builder (cl-cc/binary::make-elf64-dynamic :interpreter "/lib64/ld-linux-x86-64.so.2"
                                                     :shared-object t)))
      (expect (cl-cc/binary::elf64-elf-type builder) :to-be cl-cc/binary::+elf-type-dyn+)
      (expect (cl-cc/binary::elf64-interpreter builder) :to-equal "/lib64/ld-linux-x86-64.so.2")
      (expect (cl-cc/binary::elf64-shared-object builder) :to-be-truthy)))

  (it "make-elf64-dynamic defaults shared-object to nil (a PIE executable, not a .so)"
    (expect (cl-cc/binary::elf64-shared-object (cl-cc/binary::make-elf64-dynamic))
            :to-be-null)))

(describe "elf64-text-size"
  (it "grows by exactly the number of bytes appended"
    (let ((builder (cl-cc/binary::make-elf64-object)))
      (expect (cl-cc/binary::elf64-text-size builder) :to-be 0)
      (cl-cc/binary::elf64-add-text-bytes builder #(1 2 3 4))
      (expect (cl-cc/binary::elf64-text-size builder) :to-be 4))))

(describe "elf64-add-got-entry / elf64-add-plt-stub"
  (it "elf64-add-got-entry reserves 8 bytes in .data and registers a global symbol"
    (let* ((builder (cl-cc/binary::make-elf64-object))
           (offset (cl-cc/binary:elf64-add-got-entry builder "puts")))
      (expect offset :to-be 0)
      (expect (length (cl-cc/binary::elf64-data-buf builder)) :to-be 8)
      (expect (= (cl-cc/binary::elf64-symbol-count builder) 1))))

  (it "elf64-add-plt-stub appends a 10-byte jump stub and records a relocation"
    (let* ((builder (cl-cc/binary::make-elf64-object))
           (offset (cl-cc/binary:elf64-add-plt-stub builder "puts")))
      (expect offset :to-be 0)
      (expect (cl-cc/binary::elf64-text-size builder) :to-be 10)
      (expect (= (length (cl-cc/binary::elf64-rela-entries builder)) 1)))))

(describe "elf64-add-needed-library"
  (it "records a DT_NEEDED soname"
    (let ((builder (cl-cc/binary::make-elf64-object)))
      (cl-cc/binary::elf64-add-needed-library builder "libc.so.6")
      (expect (member "libc.so.6" (cl-cc/binary::elf64-needed-libraries builder) :test #'string=)
              :to-be-truthy)))

  (it "does not add the same soname twice"
    (let ((builder (cl-cc/binary::make-elf64-object)))
      (cl-cc/binary::elf64-add-needed-library builder "libc.so.6")
      (cl-cc/binary::elf64-add-needed-library builder "libc.so.6")
      (expect (length (cl-cc/binary::elf64-needed-libraries builder)) :to-be 1))))

(describe "elf64-add-reloc / elf64-add-global-symbol"
  (it "elf64-add-global-symbol returns sequential indices starting at 0"
    (let ((builder (cl-cc/binary::make-elf64-object)))
      (expect (cl-cc/binary::elf64-add-global-symbol builder "a") :to-be 0)
      (expect (cl-cc/binary::elf64-add-global-symbol builder "b") :to-be 1)))

  (it "elf64-add-reloc pushes an (offset type sym-name addend) entry"
    (let ((builder (cl-cc/binary::make-elf64-object)))
      (cl-cc/binary::elf64-add-reloc builder 16 "callee" :type cl-cc/binary::+r-x86-64-plt32+
                                                          :addend -4)
      (expect (first (cl-cc/binary::elf64-rela-entries builder))
              :to-equal (list 16 cl-cc/binary::+r-x86-64-plt32+ "callee" -4)))))

(describe "elf64-add-load-segment / elf64-add-gnu-stack-segment / elf64-add-gnu-relro-segment"
  (it "elf64-add-load-segment pushes a PT_LOAD phdr with FILESZ defaulting to MEMSZ"
    (let ((builder (cl-cc/binary::make-elf64-object)))
      (cl-cc/binary::elf64-add-load-segment builder #x400000 #x1000)
      ;; ELF64-ADD-LOAD-SEGMENT pushes (type flags (OR filesz memsz) vaddr
      ;; paddr filesz memsz align) — the third element is the *effective*
      ;; file size, already defaulted; the sixth is the raw FILESZ argument,
      ;; which stays NIL here since the call above did not supply one.
      (destructuring-bind (type flags effective-filesz vaddr paddr raw-filesz memsz align)
          (first (cl-cc/binary::elf64-phdrs builder))
        (expect type :to-be cl-cc/binary::+pt-load+)
        (expect flags :to-be (logior cl-cc/binary::+pf-r+ cl-cc/binary::+pf-x+))
        (expect vaddr :to-be #x400000)
        (expect paddr :to-be #x400000)
        (expect effective-filesz :to-be #x1000)
        (expect raw-filesz :to-be-null)
        (expect memsz :to-be #x1000)
        (expect align :to-be #x1000))))

  (it "elf64-add-gnu-stack-segment defaults to PF_R|PF_W with no PF_X"
    (let ((builder (cl-cc/binary::make-elf64-object)))
      (cl-cc/binary::elf64-add-gnu-stack-segment builder)
      (destructuring-bind (type flags &rest ignored) (first (cl-cc/binary::elf64-phdrs builder))
        (declare (ignore ignored))
        (expect type :to-be cl-cc/binary::+pt-gnu-stack+)
        (expect flags :to-be (logior cl-cc/binary::+pf-r+ cl-cc/binary::+pf-w+))
        (expect (zerop (logand flags cl-cc/binary::+pf-x+))))))

  (it "elf64-add-gnu-relro-segment pushes a read-only PT_GNU_RELRO phdr"
    (let ((builder (cl-cc/binary::make-elf64-object)))
      (cl-cc/binary::elf64-add-gnu-relro-segment builder #x2000 #x600000 #x100)
      (destructuring-bind (type flags offset vaddr paddr filesz memsz align)
          (first (cl-cc/binary::elf64-phdrs builder))
        (expect type :to-be cl-cc/binary::+pt-gnu-relro+)
        (expect flags :to-be cl-cc/binary::+pf-r+)
        (expect offset :to-be #x2000)
        (expect vaddr :to-be #x600000)
        (expect paddr :to-be #x600000)
        (expect filesz :to-be #x100)
        (expect memsz :to-be #x100)
        (expect align :to-be 1)))))
