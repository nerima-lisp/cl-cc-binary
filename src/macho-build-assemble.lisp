(in-package :cl-cc/binary)

(defun build-mach-o (builder code-bytes &key compress)
  "Build complete Mach-O executable from BUILDER and CODE-BYTES.
Returns a simple-array of (unsigned-byte 8).

Layout: __PAGEZERO (fileoff=0) + __TEXT (fileoff=0, covers header through code)
+ __LINKEDIT (after code) + LC_LOAD_DYLINKER + LC_MAIN.
__TEXT.fileoff=0 is required by macOS strict validation for code signing.
Function order in CODE-BYTES is emitted unchanged so pipeline-level function
reordering directly controls the final text layout."
  (declare (type mach-o-builder builder)
           (type (simple-array (unsigned-byte 8) (*)) code-bytes))
  (let* ((buffer (make-byte-buffer 65536))
         (header-size 32)
         (user-segments (%mach-o-ensure-text-and-unwind
                         (nreverse (mach-o-builder-segments builder))
                         code-bytes :compress compress))
         (relocations (%mach-o-relocation-infos builder))
         (relocation-size (* 8 (length relocations)))
         (symbols (nreverse (mach-o-builder-symbol-table builder)))
         (string-table (subseq (mach-o-builder-string-table builder)
                               0
                               (fill-pointer (mach-o-builder-string-table builder))))
         (has-symbols (plusp (length symbols)))
         (external-symbols (remove-duplicates
                            (loop for reloc in (mach-o-builder-relocations builder)
                                  collect (getf reloc :symbol))
                            :test #'string=))
         (bind-bytes (%macho-build-bind-opcodes external-symbols))
         (has-bind-info (plusp (length bind-bytes)))
         (cmd-sizes (%build-macho-command-sizes user-segments has-symbols))
         (cmds-size (getf cmd-sizes :total))
         (code-offset (align-up (+ header-size cmds-size) 4096))
         (linkedit-fileoff (%build-macho-file-offsets code-offset user-segments code-bytes))
         (nsyms (length symbols))
         (relocoff (if (plusp relocation-size) linkedit-fileoff 0))
         (symoff (if has-symbols (+ linkedit-fileoff relocation-size) 0))
         (stroff (if has-symbols (+ symoff (* nsyms +macho-nlist-size+)) 0))
         (strsize (length string-table))
         (bind-off (if has-bind-info
                       (+ linkedit-fileoff relocation-size
                          (if has-symbols
                              (+ (* nsyms +macho-nlist-size+) strsize)
                              0))
                       0))
         (bind-size (if has-bind-info (length bind-bytes) 0))
         (code-signature-bytes (make-array 0 :element-type '(unsigned-byte 8)))
         (code-signature-size 0)
         (linkedit-filesize (+ relocation-size
                               (if has-symbols
                                   (+ (* nsyms +macho-nlist-size+) strsize)
                                   0)
                               bind-size
                               code-signature-size))
         (linkedit-seg (%make-linkedit-segment linkedit-fileoff linkedit-filesize
                                               (+ +macho-text-base-addr+ linkedit-fileoff))))
    (declare (ignore bind-off))
    ;; Update Mach-O header
    (let ((header (mach-o-builder-header builder)))
      (setf (mach-header-ncmds header)
            ;; PAGEZERO + user segs + LINKEDIT + DYLINKER + DYLIB + MAIN [+ SYMTAB + DYSYMTAB]
            (+ 5 (length user-segments) (if has-symbols 2 0))
            (mach-header-sizeofcmds header) cmds-size
            (mach-header-flags header) (logior +mh-dyldlink+ +mh-pie+)))
    ;; Set entryoff = code-offset (offset within __TEXT, which starts at fileoff=0)
    (setf (entry-point-command-entryoff (mach-o-builder-entry-point builder))
          code-offset)
    ;; Lay out file offsets for all user segments and their sections
    (%update-macho-segment-offsets user-segments code-bytes code-offset relocoff relocations)
    ;; Serialize load commands into buffer
    (%serialize-macho-commands buffer builder user-segments linkedit-seg
                               has-symbols symoff nsyms stroff strsize
                               relocoff relocations)
    ;; Serialize payload bytes into buffer
    (%serialize-macho-payloads buffer user-segments code-bytes code-offset
                               linkedit-fileoff relocations has-symbols symbols
                               string-table has-bind-info bind-bytes
                               code-signature-bytes)
    (buffer-get-bytes buffer)))
