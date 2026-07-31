(in-package :cl-cc/binary)

(defun %serialize-macho-commands (buffer builder user-segments linkedit-seg
                                   has-symbols symoff nsyms stroff strsize
                                   relocoff relocations)
  "Write all Mach-O load commands to BUFFER in canonical order."
  ;; Mach-O header
  (serialize-mach-header (mach-o-builder-header builder) buffer)
  ;; __PAGEZERO
  (serialize-segment-command (%make-pagezero-segment) buffer)
  ;; User segments with their sections
  (dolist (seg user-segments)
    (serialize-segment-command seg buffer)
    (dolist (sect (segment-command-sections seg))
      (serialize-section sect buffer)))
  ;; __LINKEDIT
  (serialize-segment-command linkedit-seg buffer)
  ;; LC_LOAD_DYLINKER
  (serialize-lc-load-dylinker buffer)
  ;; LC_LOAD_DYLIB for libSystem
  (%write-macho-dylib-command buffer)
  ;; LC_SYMTAB / LC_DYSYMTAB when symbols exist
  (when has-symbols
    (serialize-symtab-command
     (make-symtab-command :symoff symoff :nsyms nsyms :stroff stroff :strsize strsize)
     buffer)
    (serialize-dysymtab-command
     (make-dysymtab-command :iextdefsym 0
                            :nextdefsym 0
                            :iundefsym 0
                            :nundefsym nsyms
                            :extreloff relocoff
                            :nextrel (length relocations))
     buffer))
  ;; LC_MAIN
  (serialize-entry-point-command (mach-o-builder-entry-point builder) buffer))

(defun %serialize-macho-payloads (buffer user-segments code-bytes code-offset
                                   linkedit-fileoff relocations has-symbols symbols
                                   string-table has-bind-info bind-bytes
                                   code-signature-bytes)
  "Write all payload bytes (code, data, LINKEDIT contents) to BUFFER."
  ;; Pad header area to code-offset
  (buffer-pad-to buffer code-offset)
  ;; Write user segment payloads
  (dolist (seg user-segments)
    (let* ((is-text (and (string= (segment-command-segname seg) "__TEXT")
                         (zerop (length (segment-command-payload seg)))))
           (payload (if is-text code-bytes (segment-command-payload seg)))
           (target-off (if (string= (segment-command-segname seg) "__TEXT")
                           code-offset
                           (segment-command-fileoff seg))))
      (buffer-pad-to buffer target-off)
      (serialize-bytes payload buffer)
      (buffer-pad-to buffer (align-up (+ target-off (length payload)) #x1000))))
  ;; Pad to __LINKEDIT start
  (buffer-pad-to buffer linkedit-fileoff)
  ;; Write relocation entries, symbol table, bind info, code signature
  (dolist (reloc relocations)
    (serialize-relocation-info reloc buffer))
  (when has-symbols
    (dolist (sym symbols)
      (serialize-nlist sym buffer))
    (serialize-bytes (coerce string-table '(simple-array (unsigned-byte 8) (*))) buffer))
  (when has-bind-info
    (serialize-bytes bind-bytes buffer))
  (serialize-bytes code-signature-bytes buffer))
