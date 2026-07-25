(in-package :cl-cc/binary)

(defun elf64-finalize-relocatable (builder)
  "Assemble the complete ELF64 object file. Returns a (simple-array (unsigned-byte 8) (*))."
  (let* (;; String tables
         (shstrtab (make-strtab))
         (strtab   (make-strtab))
          ;; Section name offsets in shstrtab
          (sh-text-off     (strtab-add shstrtab ".text"))
          (sh-rodata-off   (strtab-add shstrtab ".rodata"))
          (sh-rodata-str-off (strtab-add shstrtab ".rodata.str"))
          (sh-bss-off      (strtab-add shstrtab ".bss"))
         (sh-eh-frame-off (strtab-add shstrtab ".eh_frame"))
         (sh-eh-frame-hdr-off (strtab-add shstrtab ".eh_frame_hdr"))
         (sh-rela-off     (strtab-add shstrtab ".rela.text"))
         (sh-symtab-off   (strtab-add shstrtab ".symtab"))
          (sh-strtab-off   (strtab-add shstrtab ".strtab"))
          (sh-debug-line-off (strtab-add shstrtab ".debug_line"))
          (sh-shstrtab-off (strtab-add shstrtab ".shstrtab"))
         ;; Build symbol table (populates strtab); capture both bytes and local-count
         (sym-build (multiple-value-list (elf64-build-symtab builder strtab)))
         (sym-buf (first sym-build))
         (sym-local-count (second sym-build))
         ;; Build symbol index map for relocation
         (sym-index-map (let ((m (make-hash-table :test #'equal))
                              (syms (reverse (elf64-symbols builder))))
                          (loop for sym in syms for i from 1
                                do (setf (gethash (first sym) m) i))
                          m))
         ;; Build rela section
         (rela-buf (elf64-build-rela builder sym-index-map))
         ;; Finalize string tables
         (strtab-bytes   (strtab-bytes strtab))
         (shstrtab-bytes (strtab-bytes shstrtab))
          ;; .text/.rodata/.eh_frame bytes
           (text-bytes (binary-buffer-to-array (elf64-text-buf builder)))
           (text-section-values
             (multiple-value-list
              (compress-code-bytes-cps
               text-bytes (elf64-compress-text builder)
               (lambda (compressed original-size compressed-size)
                 (declare (ignore compressed-size))
                 (values (elf64-build-compressed-section compressed original-size :addralign 16) t))
               (lambda () (values text-bytes nil)))))
           (text-section-bytes (first text-section-values))
           (text-section-compressed-p (second text-section-values))
           (rodata-bytes (binary-buffer-to-array (elf64-rodata-buf builder)))
           (rodata-str-bytes (binary-buffer-to-array (elf64-rodata-str-buf builder)))
           (bss-size        (elf64-bss-size builder))
            (eh-frame-bytes (elf64-build-eh-frame (length text-bytes)))
            (debug-line-bytes (%emit-dwarf-line-info (length text-bytes)))
           (rodata-str-size (length rodata-str-bytes))
           (rodata-str-present-p (plusp rodata-str-size))
           ;; Layout: ELF header + sections + section headers.
           ;; Section ordering: NULL, .text, .rodata, optional .rodata.str,
           ;; .bss, .eh_frame, .eh_frame_hdr, .rela.text, .symtab, .strtab,
           ;; .shstrtab
            (n-sections (if rodata-str-present-p 12 11))
            (symtab-idx (if rodata-str-present-p 8 7))
            (strtab-idx (if rodata-str-present-p 9 8))
            (shstrtab-idx (if rodata-str-present-p 11 10))  ; index of .shstrtab
          ;; Data starts after ELF header, honoring section alignment requirements.
            (text-offset     (align-up +elf64-ehdr-size+ 16))
            (text-size       (length text-section-bytes))
            (rodata-offset   (align-up (+ text-offset text-size) 8))
           (rodata-size     (length rodata-bytes))
           (rodata-str-offset (align-up (+ rodata-offset rodata-size) 1))
          (eh-frame-offset (align-up (+ rodata-str-offset rodata-str-size) 8))
          (eh-frame-size   (length eh-frame-bytes))
          (eh-frame-hdr-bytes (elf64-build-eh-frame-hdr eh-frame-offset text-size))
          (eh-frame-hdr-offset (align-up (+ eh-frame-offset eh-frame-size) 4))
          (eh-frame-hdr-size (length eh-frame-hdr-bytes))
          (rela-offset     (align-up (+ eh-frame-hdr-offset eh-frame-hdr-size) 8))
         (rela-size       (length rela-buf))
         (symtab-offset   (align-up (+ rela-offset rela-size) 8))
         (symtab-size     (length sym-buf))
         (strtab-offset   (+ symtab-offset symtab-size))
         (strtab-size     (length strtab-bytes))
          (debug-line-offset (+ strtab-offset strtab-size))
          (debug-line-size (length debug-line-bytes))
          (shstrtab-offset (+ debug-line-offset debug-line-size))
         (shstrtab-size   (length shstrtab-bytes))
         ;; Section headers start after all section data
         (shoff           (align-up (+ shstrtab-offset shstrtab-size) 8))
         ;; Output buffer
         (out (elf-make-buffer)))

    ;; ---- ELF Header (64 bytes) ----
    ;; e_ident[16]
    (elf-buf-u8 out +elf-magic-0+)
    (elf-buf-u8 out +elf-magic-1+)
    (elf-buf-u8 out +elf-magic-2+)
    (elf-buf-u8 out +elf-magic-3+)
    (elf-buf-u8 out +elf-class-64+)     ; EI_CLASS
    (elf-buf-u8 out +elf-data-lsb+)     ; EI_DATA
    (elf-buf-u8 out +elf-version-cur+)  ; EI_VERSION
    (elf-buf-u8 out +elf-osabi-none+)   ; EI_OSABI
    (binary-buffer-write-pad out 8)                  ; EI_ABIVERSION + padding
    ;; e_type(2)
    (binary-buffer-write-u16le out +elf-type-rel+)
     ;; e_machine(2)
     (binary-buffer-write-u16le out (elf64-machine builder))
    ;; e_version(4)
    (binary-buffer-write-u32le out +elf-version-cur+)
    ;; e_entry(8): 0 for .o
    (binary-buffer-write-u64le out 0)
    ;; e_phoff(8): 0 (no program headers)
    (binary-buffer-write-u64le out 0)
    ;; e_shoff(8): section header table offset
    (binary-buffer-write-u64le out shoff)
    ;; e_flags(4): 0
    (binary-buffer-write-u32le out 0)
    ;; e_ehsize(2): 64
    (binary-buffer-write-u16le out +elf64-ehdr-size+)
    ;; e_phentsize(2): 0
    (binary-buffer-write-u16le out 0)
    ;; e_phnum(2): 0
    (binary-buffer-write-u16le out 0)
    ;; e_shentsize(2): 64
    (binary-buffer-write-u16le out +elf64-shdr-size+)
    ;; e_shnum(2)
    (binary-buffer-write-u16le out n-sections)
    ;; e_shstrndx(2)
    (binary-buffer-write-u16le out shstrtab-idx)

     ;; ---- Section Data ----
     (binary-buffer-write-pad out (- text-offset (length out)))
      (binary-buffer-write-bytes out text-section-bytes)
       (binary-buffer-write-pad out (- rodata-offset (length out)))
       (binary-buffer-write-bytes out rodata-bytes)
       (when rodata-str-present-p
         (binary-buffer-write-pad out (- rodata-str-offset (length out)))
         (binary-buffer-write-bytes out rodata-str-bytes))
       (binary-buffer-write-pad out (- eh-frame-offset (length out)))
      (binary-buffer-write-bytes out eh-frame-bytes)
      (binary-buffer-write-pad out (- eh-frame-hdr-offset (length out)))
      (binary-buffer-write-bytes out eh-frame-hdr-bytes)
      (binary-buffer-write-pad out (- rela-offset (length out)))
     (binary-buffer-write-bytes out rela-buf)
     (binary-buffer-write-pad out (- symtab-offset (length out)))
     (binary-buffer-write-bytes out sym-buf)
      (binary-buffer-write-pad out (- strtab-offset (length out)))
      (binary-buffer-write-bytes out strtab-bytes)
      (binary-buffer-write-pad out (- debug-line-offset (length out)))
      (binary-buffer-write-bytes out debug-line-bytes)
      (binary-buffer-write-pad out (- shstrtab-offset (length out)))
     (binary-buffer-write-bytes out shstrtab-bytes)
     (binary-buffer-write-pad out (- shoff (length out)))

    ;; ---- Section Headers ----
    ;; SHN 0: NULL
    (elf64-write-shdr out 0 +sht-null+ 0 0 0 0 0 0 0)
     ;; SHN 1: .text
     (elf64-write-shdr out sh-text-off +sht-progbits+
                       (logior +shf-alloc+ +shf-execinstr+
                               (if text-section-compressed-p +shf-compressed+ 0))
                       text-offset text-size
                       0 0 16 0)
      ;; SHN 2: .rodata (allocated, read-only; no SHF_WRITE)
      (elf64-write-shdr out sh-rodata-off +sht-progbits+
                         +shf-alloc+
                         rodata-offset rodata-size
                         0 0 8 0)
      ;; Optional .rodata.str (mergeable NUL-terminated strings)
      (when rodata-str-present-p
        (elf64-write-shdr out sh-rodata-str-off +sht-progbits+
                          (logior +shf-alloc+ +shf-merge+ +shf-strings+)
                          rodata-str-offset rodata-str-size
                          0 0 1 1))
      ;; .bss (NOBITS; no file payload)
      (elf64-write-shdr out sh-bss-off +sht-nobits+
                        (logior +shf-alloc+ +shf-write+)
                        0 bss-size
                        0 0 8 0)
      ;; SHN 5: .eh_frame (allocated unwind table)
      (elf64-write-shdr out sh-eh-frame-off +sht-progbits+
                        +shf-alloc+
                        eh-frame-offset eh-frame-size
                        0 0 8 0)
      ;; SHN 6: .eh_frame_hdr (allocated compact FDE lookup table)
      (elf64-write-shdr out sh-eh-frame-hdr-off +sht-progbits+
                        +shf-alloc+
                        eh-frame-hdr-offset eh-frame-hdr-size
                        0 0 4 0)
      ;; SHN 7: .rela.text  (link=symtab, info=text-idx=1)
      ;; sh_flags must be 0 for relocation sections in relocatable .o files
      ;; (SHF_ALLOC would incorrectly mark it as occupying memory at runtime)
      (elf64-write-shdr out sh-rela-off +sht-rela+
                        0
                        rela-offset rela-size
                        symtab-idx 1  ; link=.symtab idx, info=.text idx
                        8 +elf64-rela-size+)
      ;; SHN 8: .symtab  (link=.strtab, info=first-global-idx)
      (elf64-write-shdr out sh-symtab-off +sht-symtab+
                        0
                        symtab-offset symtab-size
                        strtab-idx sym-local-count  ; link=.strtab, info=first-global
                        8 +elf64-sym-size+)
      ;; SHN 9: .strtab
      (elf64-write-shdr out sh-strtab-off +sht-strtab+
                         0
                         strtab-offset strtab-size
                         0 0 1 0)
      (elf64-write-shdr out sh-debug-line-off +sht-progbits+ 0
                        debug-line-offset debug-line-size 0 0 1 0)
      ;; SHN 10: .shstrtab
      (elf64-write-shdr out sh-shstrtab-off +sht-strtab+
                       0
                       shstrtab-offset shstrtab-size
                       0 0 1 0)

    (binary-buffer-to-array out)))
