;;;; packages/binary/src/macho-serialize.lisp — Mach-O Structure Serialization
;;;
;;; Serializes Mach-O structures (mach-header, segment-command, section,
;;; entry-point-command, symtab-command, dysymtab-command, nlist) into
;;; byte-buffer instances using the serialization primitives from macho.lisp.
;;;
;;; Also defines the mach-o-builder CLOS class (fields only; methods are in
;;; macho-build.lisp which loads after this file).
;;;
;;; Load order: after emit/binary/macho.lisp, before emit/binary/macho-build.lisp.

(in-package :cl-cc/binary)

;;; Structures And Their Serializers
;;;
;;; Each DEFINE-BINARY-STRUCT call below generates both the struct (formerly
;;; in macho.lisp) and its serializer from one field-spec list; see
;;; binary-struct.lisp.

(define-binary-struct mach-header
    "64-bit Mach-O header structure."
  ((magic +mh-magic-64+ :u32)
   (cputype +cpu-type-x86-64+ :u32)
   (cpusubtype +cpu-subtype-x86-64-all+ :u32)
   (filetype +mh-execute+ :u32)
   (ncmds 0 :u32)
   (sizeofcmds 0 :u32)
   (flags +mh-noundefs+ :u32)
   (reserved 0 :u32)))

(define-binary-struct segment-command
    "64-bit segment load command."
  ((cmd +lc-segment-64+ :u32)
   (cmdsize 72 :u32)
   (segname "" :string16)
   (vmaddr 0 :u64)
   (vmsize 0 :u64)
   (fileoff 0 :u64)
   (filesize 0 :u64)
   (maxprot 7 :u32)   ; rwx
   (initprot 5 :u32)  ; rx
   (nsects 0 :u32)
   (flags 0 :u32))
  :extra-slots ((payload (make-array 0 :element-type '(unsigned-byte 8))
                         :type (simple-array (unsigned-byte 8) (*)))
                (sections nil :type list))
  :serializer-note "Sections are serialized separately by SERIALIZE-SECTION.")

(define-binary-struct section
    "64-bit section structure."
  ((sectname "" :string16)
   (segname "" :string16)
   (addr 0 :u64)
   (size 0 :u64)
   (offset 0 :u32)
   (align 0 :u32)
   (reloff 0 :u32)
   (nreloc 0 :u32)
   (flags 0 :u32)
   (reserved1 0 :u32)
   (reserved2 0 :u32)
   (reserved3 0 :u32)))

(define-binary-struct entry-point-command
    "LC_MAIN entry point command."
  ((cmd +lc-main+ :u32)
   (cmdsize 24 :u32)
   (entryoff 0 :u64)
   (stacksize 0 :u64)))

(define-binary-struct symtab-command
    "Symbol table load command."
  ((cmd +lc-symtab+ :u32)
   (cmdsize 24 :u32)
   (symoff 0 :u32)
   (nsyms 0 :u32)
   (stroff 0 :u32)
   (strsize 0 :u32)))

(define-binary-struct dysymtab-command
    "Dynamic symbol table load command. Minimal zero-filled serialization."
  ((cmd +lc-dysymtab+ :u32)
   (cmdsize 80 :u32)
   (ilocalsym 0 :u32)
   (nlocalsym 0 :u32)
   (iextdefsym 0 :u32)
   (nextdefsym 0 :u32)
   (iundefsym 0 :u32)
   (nundefsym 0 :u32)
   (tocoff 0 :u32)
   (ntoc 0 :u32)
   (modtaboff 0 :u32)
   (nmodtab 0 :u32)
   (extrefsymoff 0 :u32)
   (nextrefsyms 0 :u32)
   (indirectsymoff 0 :u32)
   (nindirectsyms 0 :u32)
   (extreloff 0 :u32)
   (nextrel 0 :u32)
   (locreloff 0 :u32)
   (nlocrel 0 :u32)))

(define-binary-struct dyld-info-command
    "LC_DYLD_INFO_ONLY command containing link-edit rebase/bind/export ranges."
  ((cmd +lc-dyld-info-only+ :u32)
   (cmdsize 48 :u32)
   (rebase-off 0 :u32)
   (rebase-size 0 :u32)
   (bind-off 0 :u32)
   (bind-size 0 :u32)
   (weak-bind-off 0 :u32)
   (weak-bind-size 0 :u32)
   (lazy-bind-off 0 :u32)
   (lazy-bind-size 0 :u32)
   (export-off 0 :u32)
   (export-size 0 :u32)))

(defun serialize-dylib-command (dylib buffer)
  "Serialize DYLIB-COMMAND to BUFFER, including its padded path string."
  (declare (type dylib-command dylib)
           (type byte-buffer buffer))
  (let* ((name (dylib-command-name dylib))
         (name-size (1+ (length name)))
         (cmdsize (align-up (+ 24 name-size) 8)))
    (serialize-uint32-le (dylib-command-cmd dylib) buffer)
    (serialize-uint32-le cmdsize buffer)
    (serialize-uint32-le (dylib-command-name-offset dylib) buffer)
    (serialize-uint32-le (dylib-command-timestamp dylib) buffer)
    (serialize-uint32-le (dylib-command-current-version dylib) buffer)
    (serialize-uint32-le (dylib-command-compatibility-version dylib) buffer)
    (loop for c across name
          do (buffer-write-byte buffer (char-code c)))
    (loop repeat (- cmdsize (+ 24 (length name)))
          do (buffer-write-byte buffer 0))))

(define-binary-struct linkedit-data-command
    "LC_CODE_SIGNATURE and other link-edit data command payload ranges."
  ((cmd +lc-code-signature+ :u32)
   (cmdsize 16 :u32)
   (dataoff 0 :u32)
   (datasize 0 :u32)))

(defun serialize-relocation-info (reloc buffer)
  "Serialize Mach-O RELOCATION-INFO to BUFFER."
  (declare (type relocation-info reloc)
           (type byte-buffer buffer))
  (serialize-uint32-le (relocation-info-r-address reloc) buffer)
  (serialize-uint32-le
   (logior (logand (relocation-info-r-symbolnum reloc) #x00FFFFFF)
           (ash (logand (relocation-info-r-pcrel reloc) #x1) 24)
           (ash (logand (relocation-info-r-length reloc) #x3) 25)
           (ash (logand (relocation-info-r-extern reloc) #x1) 27)
           (ash (logand (relocation-info-r-type reloc) #xF) 28))
   buffer))

(defun serialize-nlist (nlist buffer)
  "Serialize NLIST to BUFFER."
  (declare (type nlist nlist)
           (type byte-buffer buffer))
  (serialize-uint32-le (nlist-n-strx nlist) buffer)
  (buffer-write-byte buffer (nlist-n-type nlist))
  (buffer-write-byte buffer (nlist-n-sect nlist))
  (serialize-uint32-le (nlist-n-desc nlist) buffer)
  (serialize-uint64-le (nlist-n-value nlist) buffer))

(defun serialize-lc-load-dylinker (buffer)
  "Serialize LC_LOAD_DYLINKER /usr/lib/dyld command (32 bytes) to BUFFER.
cmdsize must be 8-byte aligned for 64-bit Mach-O: 12 header + 13 string + 7 pad = 32."
  (serialize-uint32-le +lc-load-dylinker+ buffer)
  (serialize-uint32-le 32 buffer)
  (serialize-uint32-le 12 buffer)
  (loop for c across "/usr/lib/dyld"
        do (buffer-write-byte buffer (char-code c)))
  (loop repeat 7
        do (buffer-write-byte buffer 0)))

;;; Builder Class

(defclass mach-o-builder ()
  ((header :reader mach-o-builder-header
           :documentation "Mach-O header structure.")
   (segments :initform nil
             :accessor mach-o-builder-segments
             :documentation "List of segment commands.")
   (entry-point :accessor mach-o-builder-entry-point
                :documentation "Entry point command.")
   (string-table :initform (make-array 1024 :element-type '(unsigned-byte 8)
                                              :fill-pointer 1)
                 :reader mach-o-builder-string-table
                 :documentation "String table for symbols.")
    (symbol-table :initform nil
                  :accessor mach-o-builder-symbol-table
                  :documentation "List of nlist entries.")
    (symbol-index :initform (make-hash-table :test #'equal)
                  :reader mach-o-builder-symbol-index
                  :documentation "Map from symbol name to nlist index.")
     (relocations :initform nil
                  :accessor mach-o-builder-relocations
                  :documentation "Pending Mach-O relocation references.")
     (data-const-dedup-table :initform (make-hash-table :test #'equalp)
                             :reader mach-o-builder-data-const-dedup-table
                             :documentation "Deduplicates __DATA_CONST payloads by byte content.")
     (bind-ordinal-table :initform (make-hash-table :test #'equal)
                        :reader mach-o-builder-bind-ordinal-table
                        :documentation "Map from dylib path/name to dyld library ordinal."))
  (:documentation "Builder class for constructing Mach-O executables."))

;;; (make-mach-o-builder, add-text-segment, add-data-segment,
;;;  add-symbol, add-entry-point, build-mach-o, write-mach-o-file
;;;  are in macho-build.lisp which loads after this file.)
