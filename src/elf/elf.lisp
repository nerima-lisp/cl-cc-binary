;;;; packages/binary/src/elf.lisp - ELF64 Relocatable Object File Builder
;;;
;;; Builds ELF64 .o files for x86-64 Linux (ET_REL).
;;; FR-247: Unwind Tables / .eh_frame Generation — DWARF CFI-based unwind
;;; information for native debuggers and profilers; LSB/System V ABI compliant.
;;; Sections: NULL, .text, .rodata, .bss, .eh_frame, .eh_frame_hdr,
;;;           .rela.text, .symtab, .strtab, .shstrtab
;;;
;;; ELF64 reference: System V AMD64 ABI, ELF-64 Object File Format v1.5

(in-package :cl-cc/binary)

;;; ------------------------------------------------------------
;;; ELF64 Builder
;;; ------------------------------------------------------------

(defstruct (elf64-builder (:conc-name elf64-))
  "Accumulates sections for an ELF64 relocatable object file.
FR-291: Extended with program header and entry point support for executables."
  (machine +elf-machine-x86-64+ :type (unsigned-byte 16))
  (elf-type +elf-type-rel+ :type (unsigned-byte 16))  ; ET_REL, ET_EXEC, ET_DYN
  (entry-point 0 :type (unsigned-byte 64))             ; e_entry for executables
  ;; .text section data
  (text-buf    (elf-make-buffer))
  ;; .rodata section data. Immutable constants are emitted here with SHF_ALLOC
  ;; and without SHF_WRITE so final linked images may be mapped read-only by
  ;; the operating system; attempted writes should fault at the OS level.
  (rodata-buf  (elf-make-buffer))
  (rodata-str-buf (elf-make-buffer))
  (const-pool (make-hash-table :test #'equal))
  (rodata-string-pool (make-hash-table :test #'equal))
  ;; .data section data for ET_EXEC/ET_DYN outputs.
  (data-buf    (elf-make-buffer))
  ;; .bss section size in bytes (NOBITS, occupies memory only)
  (bss-size 0 :type integer)
  ;; Relocation entries: list of (offset type sym-name addend)
  (rela-entries nil)
  ;; Symbol entries: list of (name binding type section-idx value size)
  (symbols nil)
  ;; Shared object names to place in .dynstr and DT_NEEDED entries.
  (needed-libraries nil)
  ;; Program interpreter path for dynamically linked executables.
  (interpreter +elf64-default-interpreter+ :type string)
  (shared-object nil :type boolean)
  ;; File symbol (index 0 in symtab is always STN_UNDEF)
  (symbol-count 0)
  ;; FR-291: Program headers for executable generation
  ;; List of (type flags offset vaddr paddr filesz memsz align)
  (phdrs nil)
  ;; FR-406: whether .text should be serialized as an ELF compressed section.
  (compress-text nil :type boolean))

(defun %elf64-bytes-key (bytes)
  "Return an EQUAL hash-table key for BYTES."
  (coerce bytes 'list))

(defun make-elf64-object (&key (machine +elf-machine-x86-64+))
  "Create a fresh ELF64 builder for ET_REL (.o file)."
  (make-elf64-builder :machine machine))

(defun make-elf64-executable (&key (machine +elf-machine-x86-64+) (entry-point 0))
  "Create an ELF64 builder for ET_EXEC (static executable). FR-291."
  (make-elf64-builder :machine machine :elf-type +elf-type-exec+ :entry-point entry-point))

(defun make-elf64-dynamic (&key (machine +elf-machine-x86-64+) (entry-point 0)
                                (interpreter +elf64-default-interpreter+) shared-object)
  "Create an ELF64 builder for ET_DYN (PIE/shared object). FR-291."
  (make-elf64-builder :machine machine
                       :elf-type +elf-type-dyn+
                       :entry-point entry-point
                       :interpreter interpreter
                       :shared-object shared-object))

(defun elf64-add-text-bytes (builder bytes)
  "Append BYTES (vector or list of (unsigned-byte 8)) to .text section."
  (binary-buffer-write-bytes (elf64-text-buf builder) bytes))

(defun elf64-text-size (builder)
  "Return current .text section size in bytes."
  (length (elf64-text-buf builder)))

(defun elf64-add-rodata-bytes (builder bytes)
  "Append immutable constant BYTES to .rodata and return their section offset.

String literals and constant pools should use this API rather than .data.  The
serialized ELF section is allocated but not writable (SHF_ALLOC without
SHF_WRITE), allowing the final OS mapping to protect constants from writes."
  (let* ((key (%elf64-bytes-key bytes))
         (cached (gethash key (elf64-const-pool builder))))
    (or cached
        (let ((offset (length (elf64-rodata-buf builder))))
          (binary-buffer-write-bytes (elf64-rodata-buf builder) bytes)
          (setf (gethash key (elf64-const-pool builder)) offset)
          offset))))

(defun elf64-add-rodata-string (builder string)
  "Add STRING to mergeable .rodata.str and return its section offset."
  (or (gethash string (elf64-rodata-string-pool builder))
      (let ((offset (length (elf64-rodata-str-buf builder))))
        (loop for ch across string do (elf-buf-u8 (elf64-rodata-str-buf builder) (char-code ch)))
        (elf-buf-u8 (elf64-rodata-str-buf builder) 0)
        (setf (gethash string (elf64-rodata-string-pool builder)) offset)
        offset)))

(defun elf64-add-got-entry (builder symbol-name)
  "Reserve an 8-byte GOT slot for SYMBOL-NAME in .data and return its offset."
  (let ((offset (elf64-add-data-bytes builder #(0 0 0 0 0 0 0 0))))
    (elf64-add-global-symbol builder symbol-name :section-idx 0 :value 0 :size 0)
    offset))

(defun elf64-add-plt-stub (builder symbol-name)
  "Append a conservative x86-64 PLT-style jump stub for SYMBOL-NAME."
  (let ((offset (elf64-text-size builder)))
    (elf64-add-text-bytes builder #(#xff #x25 #x00 #x00 #x00 #x00 #x0f #x1f #x40 #x00))
    (elf64-add-global-symbol builder symbol-name :section-idx 0 :value 0 :size 0)
    (elf64-add-reloc builder (+ offset 2) symbol-name :type +r-x86-64-pc32+ :addend -4)
    offset))

(defun elf64-verify-wx (segments)
  "Signal an error if any PT_LOAD segment is both writable and executable."
  (dolist (segment segments t)
    (destructuring-bind (type flags &rest _) segment
      (declare (ignore _))
      (when (and (= type +pt-load+)
                 (not (zerop (logand flags +pf-w+)))
                 (not (zerop (logand flags +pf-x+))))
        (error 'elf-wx-violation :segment segment)))))

(defun elf64-add-data-bytes (builder bytes)
  "Append initialized writable BYTES to .data and return their section offset."
  (let ((offset (length (elf64-data-buf builder))))
    (binary-buffer-write-bytes (elf64-data-buf builder) bytes)
    offset))

(defun elf64-add-needed-library (builder soname)
  "Record SONAME as a DT_NEEDED dependency for ET_DYN output."
  (pushnew soname (elf64-needed-libraries builder) :test #'string=)
  soname)

(defun elf64-add-bss (builder size)
  "Reserve SIZE bytes in the .bss section."
  (incf (elf64-bss-size builder) size)
  (elf64-bss-size builder))

(defun elf64-add-reloc (builder offset sym-name &key (type +r-x86-64-plt32+) (addend -4))
  "Add a relocation entry for a CALL instruction at OFFSET in .text.
   SYM-NAME is the external symbol to reference.
   TYPE defaults to R_X86_64_PLT32 (appropriate for CALL rel32).
   ADDEND defaults to -4 (PC-relative from end of 4-byte immediate)."
  (push (list offset type sym-name addend) (elf64-rela-entries builder)))

(defun elf64-add-global-symbol (builder name &key (section-idx 0) (value 0) (size 0))
  "Add a global (external) symbol reference to the symbol table.
   section-idx=0 means undefined (external), 1 means defined in .text."
  (let ((idx (elf64-symbol-count builder)))
    (push (list name +stb-global+ +stt-func+ section-idx value size) (elf64-symbols builder))
    (setf (elf64-symbol-count builder) (1+ idx))
    idx))

;;; FR-291: Program header (segment) support for executables

(defun elf64-add-load-segment (builder vaddr memsz
                               &key (flags (+ +pf-r+ +pf-x+)) (filesz nil)
                                    (align #x1000))
  "Add a PT_LOAD program header covering [VADDR, VADDR+MEMSZ).
FILESZ defaults to MEMSZ (no .bss tail).  ALIGN defaults to 4KB page.
FLAGS default to PF_R | PF_X (readable+executable)."
  (push (list +pt-load+ flags (or filesz memsz) vaddr vaddr filesz memsz align)
        (elf64-phdrs builder)))

(defun elf64-add-gnu-stack-segment (builder &optional (flags (+ +pf-r+ +pf-w+)))
  "Add PT_GNU_STACK segment with FLAGS (defaults to RW, no exec).
Required by Linux kernel for NX (non-executable stack) support."
  (push (list +pt-gnu-stack+ flags 0 0 0 0 0 0)
        (elf64-phdrs builder)))

(defun elf64-add-gnu-relro-segment (builder offset vaddr size &key (align 1))
  "Add PT_GNU_RELRO segment for read-only-after-relocation data."
  (push (list +pt-gnu-relro+ +pf-r+ offset vaddr vaddr size size align)
        (elf64-phdrs builder)))


;;; (elf64-build-symtab, elf64-build-rela, elf64-write-shdr, elf64-finalize,
;;;  write-elf64-file, and compile-to-elf64 are in elf-emit.lisp
;;;  which loads after this file.)
