(in-package :cl-cc/binary)

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
