;;;; packages/binary/src/elf-emit.lisp — ELF64 serialization and public API
;;;
;;; Contains:
;;;   - elf64-build-symtab — build symbol table bytes
;;;   - elf64-build-rela — build RELA relocation section bytes
;;;   - elf64-write-shdr — write a section header entry
;;;   - elf64-finalize — lay out all ELF sections and produce final byte array
;;;   - write-elf64-file — write byte array to file
;;;   - compile-to-elf64 — public entry point: code+relocs → ELF64 bytes
;;;
;;; ELF64 constants, byte-buffer helpers, strtab-builder, elf64-builder struct,
;;; and basic builder API (add-text, add-bss, add-reloc, add-symbol)
;;; are in elf.lisp (loads before).
;;;
;;; Load order: after emit/binary/elf.lisp.
(in-package :cl-cc/binary/elf)

;;; ------------------------------------------------------------
;;; ELF64 Serialization
;;; ------------------------------------------------------------

(defun elf64-build-symtab (builder strtab)
  "Build symbol table bytes. Returns (values symtab-bytes local-count).
   Symbol table format: STN_UNDEF first, then locals, then globals.
   local-count is needed in sh_info."
  (let ((symbols (reverse (elf64-symbols builder))))
    ;; local count = 1 (only STN_UNDEF entry is "local")
    (values
     (with-byte-buffer (sym-buf)
       ;; Entry 0: STN_UNDEF (all zeros)
       (binary-buffer-write-pad sym-buf +elf64-sym-size+)
       ;; Add each symbol
       (dolist (sym symbols)
         (destructuring-bind (name binding type section-idx value size) sym
           (let ((name-offset (strtab-add strtab name)))
             ;; st_name(4)
             (binary-buffer-write-u32le sym-buf name-offset)
             ;; st_info(1): (binding << 4) | type
             (elf-buf-u8 sym-buf (logior (ash binding 4) type))
             ;; st_other(1): 0
             (elf-buf-u8 sym-buf 0)
             ;; st_shndx(2): section index (0 = undefined)
             (binary-buffer-write-u16le sym-buf section-idx)
             ;; st_value(8)
             (binary-buffer-write-u64le sym-buf value)
             ;; st_size(8)
             (binary-buffer-write-u64le sym-buf size)))))
     1)))

(defun elf64-build-rela (builder sym-index-map)
  "Build .rela.text section bytes.
   SYM-INDEX-MAP maps sym-name string to its 1-based index in symtab."
  (let ((entries (reverse (elf64-rela-entries builder))))
    (with-byte-buffer (rela-buf)
      (dolist (entry entries)
        (destructuring-bind (offset type sym-name addend) entry
          (let ((sym-idx (or (gethash sym-name sym-index-map) 0)))
            ;; r_offset(8): byte offset in .text
            (binary-buffer-write-u64le rela-buf offset)
            ;; r_info(8): (sym-idx << 32) | type
            (binary-buffer-write-u64le rela-buf (logior (ash sym-idx 32) type))
            ;; r_addend(8): signed addend
            (binary-buffer-write-s64le rela-buf addend)))))))

(defun elf64-write-shdr (buf name-off type flags offset size link info align entsize)
  "Write a 64-byte section header entry to BUF."
  (elf64-write-shdr-with-addr buf name-off type flags 0 offset size link info align entsize))

(define-binary-writer elf64-write-shdr-with-addr
    (buf name-off type flags addr offset size link info align entsize)
    "Write a 64-byte section header entry to BUF with explicit virtual ADDR."
  (:u32 name-off)  ; sh_name
  (:u32 type)      ; sh_type
  (:u64 flags)     ; sh_flags
  (:u64 addr)      ; sh_addr
  (:u64 offset)    ; sh_offset
  (:u64 size)      ; sh_size
  (:u32 link)      ; sh_link
  (:u32 info)      ; sh_info
  (:u64 align)     ; sh_addralign
  (:u64 entsize))  ; sh_entsize

(define-binary-writer elf64-write-phdr
    (buf type flags offset vaddr paddr filesz memsz align)
    "Write an ELF64 program header entry to BUF."
  (:u32 type)
  (:u32 flags)
  (:u64 offset)
  (:u64 vaddr)
  (:u64 paddr)
  (:u64 filesz)
  (:u64 memsz)
  (:u64 align))

(define-binary-writer elf64-write-dynamic-entry (buf tag value)
    "Write one Elf64_Dyn entry to BUF."
  (:s64 tag)
  (:u64 value))

(defun elf64-build-compressed-section (compressed-bytes original-size &key (addralign 16))
  "Build an ELF64 SHF_COMPRESSED section payload.

The returned bytes start with Elf64_Chdr:
  ch_type=ELFCOMPRESS_ZLIB, ch_reserved=0, ch_size=ORIGINAL-SIZE,
  ch_addralign=ADDRALIGN; followed by zlib-compressed bytes."
  (with-byte-buffer (buf)
    (binary-buffer-write-u32le buf +elfcompress-zlib+)
    (binary-buffer-write-u32le buf 0)
    (binary-buffer-write-u64le buf original-size)
    (binary-buffer-write-u64le buf addralign)
    (binary-buffer-write-bytes buf compressed-bytes)))

(defun build-dwo-file (source-name &key dwo-id (producer "cl-cc") (comp-dir "."))
  "Return a little-endian x86-64 ELF64 ET_REL metadata-only DWO file.
DWO-ID must match the skeleton's ID. The split CU has no child DIEs or code
mapping; its v5 line section contains a file table, not line instructions."
  (let ((info (%dwo-unit 5 dwo-id
                         (with-byte-buffer (die)
                           (binary-buffer-write-u8 die 1)
                           (%dwo-write-string die source-name)
                           (%dwo-write-string die producer))))
        (abbrev (make-array 12 :element-type '(unsigned-byte 8)
                            :initial-contents '(1 #x11 0 3 8 #x25 8 #x53 #x19 0 0 0))))
    (%dwo-elf64 (list (cons ".debug_info.dwo" info)
                      (cons ".debug_abbrev.dwo" abbrev)
                      (cons ".debug_line.dwo" (%dwo-line-table source-name comp-dir))))))

(defun %dwo-elf64 (sections)
  ;; The ordinary ELF builder owns code/symbol sections. This container only
  ;; lays out the named, non-allocated metadata sections supplied here.
  (let* ((strings (make-strtab))
         (name-offsets (mapcar (lambda (section) (strtab-add strings (car section))) sections))
         (strings-name (strtab-add strings ".shstrtab"))
         (payloads (append (mapcar #'cdr sections) (list (strtab-bytes strings))))
         (offset 64)
         (offsets (mapcar (lambda (bytes) (prog1 offset (incf offset (length bytes)))) payloads))
         (shoff (align-up offset 8))
         (count (+ 2 (length sections))))
    (with-byte-buffer (buffer)
      (binary-buffer-write-bytes buffer '(#x7f #x45 #x4c #x46 2 1 1 0 0))
      (binary-buffer-write-pad buffer 7)
      (binary-buffer-write-u16le buffer +elf-type-rel+)
      (binary-buffer-write-u16le buffer +elf-machine-x86-64+)
      (binary-buffer-write-u32le buffer +elf-version-cur+)
      (binary-buffer-write-u64le buffer 0)
      (binary-buffer-write-u64le buffer 0)
      (binary-buffer-write-u64le buffer shoff)
      (binary-buffer-write-u32le buffer 0)
      (binary-buffer-write-u16le buffer 64)
      (binary-buffer-write-u16le buffer 0)
      (binary-buffer-write-u16le buffer 0)
      (binary-buffer-write-u16le buffer 64)
      (binary-buffer-write-u16le buffer count)
      (binary-buffer-write-u16le buffer (1- count))
      (dolist (bytes payloads) (binary-buffer-write-bytes buffer bytes))
      (binary-buffer-write-pad buffer (- shoff (length buffer)))
      (binary-buffer-write-pad buffer 64)
      (loop for bytes in payloads for position in offsets
            for name in (append name-offsets (list strings-name))
            for index from 1 do
        (elf64-write-shdr buffer name
                          (if (= index (1- count)) +sht-strtab+ +sht-progbits+)
                          0 position (length bytes) 0 0 1 0)))))
