(in-package :cl-cc/binary)

(defun macho-build-unwind-info (code-size &key
                                            (encoding +compact-unwind-x86-64-mode-stack-immd+)
                                            (personality 0))
  "Build a compact __unwind_info payload with one frameless function entry.

The payload starts with a small CL-CC table header followed by a per-function
entry: start address, function length, compact unwind ENCODING, and
PERSONALITY.  The default encoding models frameless/RBP-less x86-64 functions.
This Pure CL backend emits the documented interface without platform mprotect
or linker-private helpers."
  (let ((buf (elf-make-buffer)))
    ;; Signature/version for CL-CC's compact table envelope.
    (binary-buffer-write-bytes buf (map 'vector #'char-code "CLCU"))
    (binary-buffer-write-u32le buf 1)         ; version
    (binary-buffer-write-u32le buf 1)         ; entry count
    (binary-buffer-write-u32le buf 16)        ; first entry offset
    ;; Entry: start address (section-relative), length, encoding, personality.
    (binary-buffer-write-u32le buf 0)
    (binary-buffer-write-u32le buf code-size)
    (binary-buffer-write-u32le buf encoding)
    (binary-buffer-write-u32le buf personality)
    (binary-buffer-to-array buf)))

(defun %build-macho-payload (code-bytes compressed-payload compressed-offset
                             unwind-bytes unwind-offset)
  "Assemble CODE-BYTES, COMPRESSED-PAYLOAD, and UNWIND-BYTES into one flat vector.
COMPRESSED-PAYLOAD may be NIL when no compression was applied."
  (let* ((payload-size (+ unwind-offset (length unwind-bytes)))
         (payload (make-array payload-size :element-type '(unsigned-byte 8)
                              :initial-element 0)))
    (replace payload code-bytes :start1 0)
    (when compressed-payload
      (replace payload compressed-payload :start1 compressed-offset))
    (replace payload unwind-bytes :start1 unwind-offset)
    payload))

(defun %macho-build-text-sections (text-seg code-size compressed-payload unwind-bytes)
  "Return the list of section objects for a __TEXT segment.
Finds or creates __text, optionally __compressed, and __unwind_info sections."
  (let ((text-section (or (find "__text" (segment-command-sections text-seg)
                                :key #'section-sectname :test #'string=)
                          (make-section :sectname "__text"
                                        :segname "__TEXT"
                                        :size code-size
                                        :align 4
                                        :flags (logior +s-attr-pure-instructions+
                                                       +s-attr-some-instructions+))))
        (compressed-section (when compressed-payload
                              (or (find "__compressed" (segment-command-sections text-seg)
                                        :key #'section-sectname :test #'string=)
                                  (make-section :sectname "__compressed"
                                                :segname "__TEXT"
                                                :size (length compressed-payload)
                                                :align 4))))
        (unwind-section (or (find "__unwind_info" (segment-command-sections text-seg)
                                  :key #'section-sectname :test #'string=)
                            (make-section :sectname "__unwind_info"
                                          :segname "__TEXT"
                                          :size (length unwind-bytes)
                                          :align 2))))
    (setf (section-size text-section) code-size
          (section-size unwind-section) (length unwind-bytes))
    (when compressed-section
      (setf (section-size compressed-section) (length compressed-payload)))
    (if compressed-payload
        (list text-section compressed-section unwind-section)
        (list text-section unwind-section))))

(defun %macho-ensure-data-const-segment (user-segments)
  "Push a default empty __DATA_CONST segment onto USER-SEGMENTS unless one exists.
Returns the (possibly extended) segment list."
  (unless (find "__DATA_CONST" user-segments
                :key #'segment-command-segname :test #'string=)
    ;; Emit an empty read-only constant segment by default. Frontends with
    ;; string literals/constant pools can call ADD-DATA-CONST-SEGMENT to fill
    ;; this section; keeping the segment present documents and preserves the
    ;; protection boundary in every binary.
    (let* ((const-bytes (make-array 0 :element-type '(unsigned-byte 8)))
           (const-section (make-section :sectname "__const"
                                        :segname "__DATA_CONST"
                                        :addr +macho-data-const-base-addr+
                                        :size 0
                                        :align 4))
           (const-segment (make-segment-command
                           :segname "__DATA_CONST"
                           :vmaddr +macho-data-const-base-addr+
                           :vmsize #x1000
                           :payload const-bytes
                           :nsects 1
                           :maxprot 4
                           :initprot 4
                           :cmdsize (+ +macho-segment-command-size+ +macho-section-size+)
                           :sections (list const-section))))
      (push const-segment user-segments)))
  user-segments)

(defun %mach-o-ensure-text-and-unwind (user-segments code-bytes &key compress)
  "Return USER-SEGMENTS with __TEXT unwind info and read-only constants support."
  (let* ((code-size (length code-bytes))
         (compressed-payload
           (compress-code-bytes-cps
            code-bytes compress
            (lambda (compressed original-size compressed-size)
              (build-compressed-code-payload compressed +cl-cc-compression-zlib+
                                             original-size compressed-size))
            (constantly nil))))
    (let* ((unwind-bytes (macho-build-unwind-info code-size))
           (compressed-offset (and compressed-payload (align-up code-size 4)))
           (unwind-offset (align-up (if compressed-payload
                                        (+ compressed-offset (length compressed-payload))
                                        code-size)
                                    4))
           (payload (%build-macho-payload code-bytes compressed-payload compressed-offset
                                          unwind-bytes unwind-offset))
           (payload-size (length payload))
           (text-seg (find "__TEXT" user-segments
                           :key #'segment-command-segname :test #'string=)))
      (unless text-seg
        (setf text-seg (make-segment-command
                        :segname "__TEXT"
                        :vmaddr +macho-text-base-addr+
                        :vmsize (align-up payload-size #x1000)
                        :nsects 0
                        :cmdsize +macho-segment-command-size+
                        :sections nil))
        (push text-seg user-segments))
      (let ((sections (%macho-build-text-sections text-seg code-size
                                                   compressed-payload unwind-bytes)))
        (setf (segment-command-payload text-seg) payload
              (segment-command-nsects text-seg) (length sections)
              (segment-command-cmdsize text-seg)
              (+ +macho-segment-command-size+
                 (* +macho-section-size+ (length sections)))
              (segment-command-maxprot text-seg) 5
              (segment-command-initprot text-seg) 5
              (segment-command-sections text-seg) sections))
      (%macho-ensure-data-const-segment user-segments))))

(defun %macho-build-bind-opcodes (symbol-names)
  "Build a minimal dyld bind opcode stream for external SYMBOL-NAMES."
  (let ((buf (elf-make-buffer)))
    (dolist (name symbol-names)
      ;; BIND_OPCODE_SET_DYLIB_ORDINAL_IMM | 1 (libSystem)
      (binary-buffer-write-u8 buf #x11)
      ;; BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM | 0, followed by C string.
      (binary-buffer-write-u8 buf #x40)
      (loop for c across name
            do (binary-buffer-write-u8 buf (char-code c)))
      (binary-buffer-write-u8 buf 0)
      ;; BIND_OPCODE_SET_TYPE_IMM | BIND_TYPE_POINTER.
      (binary-buffer-write-u8 buf #x51)
      ;; BIND_OPCODE_DO_BIND.  Segment/offset binding is supplied by relocation
      ;; entries; this stream records the external symbol resolution intent.
      (binary-buffer-write-u8 buf #x90))
    (when symbol-names
      ;; BIND_OPCODE_DONE.
      (binary-buffer-write-u8 buf 0))
    (binary-buffer-to-array buf)))

(defun %write-macho-dylib-command (buffer &optional (path "/usr/lib/libSystem.B.dylib"))
  "Emit LC_LOAD_DYLIB for PATH."
  (serialize-dylib-command (make-dylib-command :name path) buffer))

(defun %build-macho-command-sizes (user-segments has-symbols)
  "Return an alist of command-size components for the Mach-O load command area.
USER-SEGMENTS is the ordered list of user-provided segments.
HAS-SYMBOLS indicates whether symbol-table commands should be included."
  (let ((pagezero-cmd-size +macho-segment-command-size+)
        (user-seg-cmd-sizes (loop for seg in user-segments
                                  sum (+ +macho-segment-command-size+
                                         (* +macho-section-size+
                                            (segment-command-nsects seg)))))
        (linkedit-cmd-size +macho-segment-command-size+)
        (dylinker-cmd-size 32)
        (main-cmd-size 24)
        (dyld-info-cmd-size 0)
        (dylib-cmd-size (align-up (+ 24 (1+ (length "/usr/lib/libSystem.B.dylib"))) 8))
        (code-signature-cmd-size 0)
        (symtab-cmd-size (if has-symbols 24 0))
        (dysymtab-cmd-size (if has-symbols 80 0)))
    (list :pagezero pagezero-cmd-size
          :user-segs user-seg-cmd-sizes
          :linkedit linkedit-cmd-size
          :dylinker dylinker-cmd-size
          :main main-cmd-size
          :dyld-info dyld-info-cmd-size
          :dylib dylib-cmd-size
          :code-signature code-signature-cmd-size
          :symtab symtab-cmd-size
          :dysymtab dysymtab-cmd-size
          :total (+ pagezero-cmd-size user-seg-cmd-sizes linkedit-cmd-size
                    dylinker-cmd-size main-cmd-size
                    dyld-info-cmd-size dylib-cmd-size code-signature-cmd-size
                    symtab-cmd-size dysymtab-cmd-size))))

(defun %build-macho-file-offsets (code-offset user-segments code-bytes)
  "Compute LINKEDIT file offset by accumulating page-aligned payload sizes.
Returns the file offset of __LINKEDIT."
  (let ((off code-offset))
    (dolist (seg user-segments off)
      (let ((payload-len
              (if (and (string= (segment-command-segname seg) "__TEXT")
                       (zerop (length (segment-command-payload seg))))
                  (length code-bytes)
                  (length (segment-command-payload seg)))))
        (incf off (align-up payload-len #x1000))))))

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
  (let ((pos (length (byte-buffer-data buffer))))
    (loop repeat (- code-offset pos)
          do (buffer-write-byte buffer 0)))
  ;; Write user segment payloads
  (dolist (seg user-segments)
    (let* ((is-text (and (string= (segment-command-segname seg) "__TEXT")
                         (zerop (length (segment-command-payload seg)))))
           (payload (if is-text code-bytes (segment-command-payload seg)))
           (target-off (if (string= (segment-command-segname seg) "__TEXT")
                           code-offset
                           (segment-command-fileoff seg))))
      (let ((pos (length (byte-buffer-data buffer))))
        (when (> target-off pos)
          (loop repeat (- target-off pos)
                do (buffer-write-byte buffer 0))))
      (serialize-bytes payload buffer)
      (let ((aligned-end (align-up (+ target-off (length payload)) #x1000)))
        (loop repeat (- aligned-end (length (byte-buffer-data buffer)))
              do (buffer-write-byte buffer 0)))))
  ;; Pad to __LINKEDIT start
  (let ((pos (length (byte-buffer-data buffer))))
    (when (< pos linkedit-fileoff)
      (loop repeat (- linkedit-fileoff pos)
            do (buffer-write-byte buffer 0))))
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

(defun %update-macho-segment-offsets (user-segments code-bytes code-offset relocoff relocations)
  "Assign file offsets and section offsets to all user segments in place."
  (let ((next-off code-offset))
    (dolist (seg user-segments)
      (let* ((is-text (and (string= (segment-command-segname seg) "__TEXT")
                           (zerop (length (segment-command-payload seg)))))
             (payload (if is-text code-bytes (segment-command-payload seg)))
             (payload-len (length payload)))
        (cond
          ((string= (segment-command-segname seg) "__TEXT")
           ;; __TEXT: fileoff=0, covers from file start through end of code
           ;; and the compact __unwind_info table.
           (setf (segment-command-fileoff seg) 0
                 (segment-command-filesize seg) (+ code-offset payload-len)
                 (segment-command-vmsize seg) (align-up (+ code-offset payload-len) #x1000))
           (dolist (sect (segment-command-sections seg))
             (let ((section-delta
                     (loop with delta = 0
                           for prior in (segment-command-sections seg)
                           until (eq prior sect)
                           do (setf delta (align-up (+ delta (section-size prior)) 4))
                           finally (return delta))))
               (setf (section-offset sect) (+ code-offset section-delta)
                     (section-addr sect) (+ (segment-command-vmaddr seg)
                                            code-offset
                                            section-delta))
               (when (and (string= (section-sectname sect) "__text")
                          (plusp (length relocations)))
                 (setf (section-reloff sect) relocoff
                       (section-nreloc sect) (length relocations)))))
           (setf next-off (+ code-offset (align-up payload-len #x1000))))
          (t
           ;; Other segments (e.g. __DATA): sequential after code
           (setf (segment-command-fileoff seg) next-off
                 (segment-command-filesize seg) payload-len)
           (dolist (sect (segment-command-sections seg))
             (setf (section-offset sect) next-off))
           (incf next-off (align-up payload-len #x1000))))))))

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

(defparameter *macho-codesign-timeout-seconds* 30
  "Timeout in seconds for the external codesign invocation.
codesign has been observed to hang (e.g. on keychain access); on timeout the
binary is left unsigned, matching the existing best-effort semantics where a
codesign failure is ignored.")

(defvar *binary-logger* nil
  "Optional CL-LOG-KIT logger for structured Mach-O/ELF/PE emission
diagnostics. NIL (the default) keeps this library silent, mirroring
CL-PROCESS-KIT's *PROCESS-LOGGER* convention: bind this to a
LOG-KIT:MAKE-LOGGER instance to observe otherwise-silent failure paths, such
as a timed-out or failed codesign invocation below.")

(defun %macho-log-codesign-outcome (outcome filename &key condition)
  "Log OUTCOME (:OK, :TIMEOUT, or :ERROR) for the codesign invocation on
FILENAME through *BINARY-LOGGER*. Does nothing for :OK or when
*BINARY-LOGGER* is NIL, so the default (silent) behavior is unchanged."
  (when *binary-logger*
    (ecase outcome
      (:ok nil)
      (:timeout
       (log-kit:log-warn *binary-logger* "codesign timed out; binary left unsigned"
                         :file (namestring filename)
                         :timeout-seconds *macho-codesign-timeout-seconds*))
      (:error
       (log-kit:log-warn *binary-logger* "codesign failed; binary left unsigned"
                         :file (namestring filename)
                         :reason (princ-to-string condition))))))

(defun write-mach-o-file (filename mach-o-bytes &key (codesign t))
  "Write MACH-O-BYTES to FILENAME as a binary file."
  (declare (type (or pathname string) filename)
           (type (simple-array (unsigned-byte 8) (*)) mach-o-bytes))
  (with-open-file (out filename
                        :direction :output
                        :element-type '(unsigned-byte 8)
                        :if-exists :supersede
                        :if-does-not-exist :create)
    (write-sequence mach-o-bytes out))
  (when codesign
    (let ((codesign-program (probe-file "/usr/bin/codesign")))
      (when codesign-program
        (handler-case
            (progn
              (sb-ext:with-timeout *macho-codesign-timeout-seconds*
                (sb-ext:run-program (namestring codesign-program)
                                    (list "-s" "-" "-f" (namestring (pathname filename)))
                                    :search nil
                                    :output nil
                                    :error nil))
              (%macho-log-codesign-outcome :ok filename))
          (sb-ext:timeout () (%macho-log-codesign-outcome :timeout filename))
          (error (condition) (%macho-log-codesign-outcome :error filename :condition condition))))))
  filename)
