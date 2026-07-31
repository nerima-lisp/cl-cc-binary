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
(in-package :cl-cc/binary)

;;; ------------------------------------------------------------
;;; ELF64 Serialization
;;; ------------------------------------------------------------

(defun elf64-write-uleb128 (buf value)
  "Write VALUE as unsigned LEB128 to BUF."
  (loop for v = value then (ash v -7)
        for byte = (logand v #x7f)
        do (elf-buf-u8 buf (if (zerop (ash v -7)) byte (logior byte #x80)))
        until (zerop (ash v -7))))

(defun elf64-write-sleb128 (buf value)
  "Write VALUE as signed LEB128 to BUF."
  (loop with more = t
        with v = value
        while more do
          (let* ((byte (logand v #x7f))
                 (sign-set (not (zerop (logand byte #x40)))))
            (setf v (ash v -7))
            (setf more (not (or (and (zerop v) (not sign-set))
                                (and (= v -1) sign-set))))
            (elf-buf-u8 buf (if more (logior byte #x80) byte)))))

(defun elf64-pad-to-align (buf alignment)
  "Pad BUF with DW_CFA_nop bytes to ALIGNMENT."
  (loop while (not (zerop (mod (length buf) alignment)))
        do (elf-buf-u8 buf 0)))

(defun elf64-build-eh-frame (text-size)
  "Build a minimal x86-64 .eh_frame with one CIE and one FDE for .text.

The CIE uses augmentation \"zR\", code alignment 1, data alignment -8,
return-address register RIP (DWARF register 16), and initial CFA rules for a
normal call frame: CFA = RSP+8, RIP saved at CFA-8.  The FDE covers the current
.text range and is intentionally conservative for frameless/RBP-less code."
  (with-byte-buffer (buf)
    ;; CIE
    (let* ((cie-start (length buf))
           (cie-body
             (with-byte-buffer (cie-body)
               (binary-buffer-write-u32le cie-body 0) ; CIE_id
               (elf-buf-u8 cie-body 1)                ; version
               (binary-buffer-write-bytes cie-body (map 'vector #'char-code "zR"))
               (elf-buf-u8 cie-body 0)                ; NUL terminator
               (elf64-write-uleb128 cie-body 1)       ; code alignment factor
               (elf64-write-sleb128 cie-body -8)      ; data alignment factor
               (elf64-write-uleb128 cie-body 16)      ; return address register: RIP
               (elf64-write-uleb128 cie-body 1)       ; augmentation data length
               (elf-buf-u8 cie-body #x1b)             ; DW_EH_PE_pcrel | sdata4
               ;; Initial instructions: DW_CFA_def_cfa rsp,8; DW_CFA_offset rip,1
               (elf-buf-u8 cie-body #x0c)
               (elf64-write-uleb128 cie-body 7)
               (elf64-write-uleb128 cie-body 8)
               (elf-buf-u8 cie-body #x90)
               (elf64-write-uleb128 cie-body 1)
               (elf64-pad-to-align cie-body 8))))
      (binary-buffer-write-u32le buf (length cie-body))
      (binary-buffer-write-bytes buf cie-body)
      ;; FDE. CIE_pointer is the distance from this field back to CIE start.
      (let* ((fde-start (length buf))
             (cie-pointer (- (+ fde-start 4) cie-start))
             (fde-body
               (with-byte-buffer (fde-body)
                 (binary-buffer-write-u32le fde-body cie-pointer)
                 ;; DW_EH_PE_pcrel|sdata4 payload. Relocatable objects leave the encoded
                 ;; location at zero; the linker can resolve final addresses.
                 (binary-buffer-write-u32le fde-body 0)
                 (binary-buffer-write-u32le fde-body text-size)
                 (elf64-write-uleb128 fde-body 0) ; augmentation data length
                 ;; Conservative frameless prologue state: CFA remains RSP+8.
                 (elf-buf-u8 fde-body #x0c)
                 (elf64-write-uleb128 fde-body 7)
                 (elf64-write-uleb128 fde-body 8)
                 (elf64-pad-to-align fde-body 8))))
        (binary-buffer-write-u32le buf (length fde-body))
        (binary-buffer-write-bytes buf fde-body)))))

(defun elf64-build-eh-frame-hdr (eh-frame-offset text-size)
  "Build a compact .eh_frame_hdr with a single binary-search-table FDE row."
  (declare (ignore text-size))
  (with-byte-buffer (buf)
    (elf-buf-u8 buf 1)     ; version
    (elf-buf-u8 buf #x1b)  ; eh_frame_ptr_enc: DW_EH_PE_pcrel | sdata4
    (elf-buf-u8 buf #x03)  ; fde_count_enc: DW_EH_PE_udata4
    (elf-buf-u8 buf #x3b)  ; table_enc: DW_EH_PE_datarel | sdata4
    (binary-buffer-write-u32le buf eh-frame-offset)
    (binary-buffer-write-u32le buf 1)
    ;; initial_location (relative to .eh_frame_hdr base) and FDE pointer.
    (binary-buffer-write-u32le buf 0)
    (binary-buffer-write-u32le buf 0)))

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

(defun %emit-dwarf-line-info (text-size &key (source "<unknown>"))
  "Emit a minimal DWARF3 .debug_line mapping line 1 to address 0."
  (declare (ignore source))
  (with-byte-buffer (buf)
    (binary-buffer-write-u32le buf 29) ; unit_length
    (binary-buffer-write-u16le buf 3)  ; version
    (binary-buffer-write-u32le buf 16) ; header_length
    (binary-buffer-write-bytes buf '(1 1 1 #xfb 14 13))
    (dotimes (_ 12) (declare (ignore _)) (elf-buf-u8 buf 0))
    (elf-buf-u8 buf 0) ; include dirs
    (elf-buf-u8 buf 0) ; file names
    (elf-buf-u8 buf +dwarf-dw-lns-copy+)
    (elf-buf-u8 buf +dwarf-dw-lns-advance-pc+)
    (elf64-write-uleb128 buf text-size)
    (elf-buf-u8 buf 0)
    (elf64-write-uleb128 buf 1)
    (elf-buf-u8 buf +dwarf-dw-lne-end-sequence+)))
