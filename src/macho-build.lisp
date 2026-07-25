;;;; packages/binary/src/macho-build.lisp — Mach-O Builder API
;;;
;;; Contains:
;;;   - make-mach-o-builder — factory for :x86-64 / :arm64
;;;   - add-text-segment, %make-pagezero-segment, add-data-segment
;;;   - add-symbol, add-entry-point
;;;   - build-mach-o — assemble all segments → byte array
;;;   - write-mach-o-file — write byte array to file
;;;
;;; Load order: after emit/binary/macho-serialize.lisp.
;;; (mach-o-builder class defined in macho-serialize.lisp;
;;;  constants, structs, buffer helpers, serialization primitives in macho.lisp)
(in-package :cl-cc/binary)


(defparameter *arch-cpu-specs*
  '((:x86-64 #.+cpu-type-x86-64+ #.+cpu-subtype-x86-64-all+)
    (:arm64  #.+cpu-type-arm64+  #.+cpu-subtype-arm64-all+))
  "Alist of (arch cputype cpusubtype) constants for Mach-O header construction.")

(defun make-mach-o-builder (arch)
  "Create a Mach-O builder for the specified architecture.
ARCH should be :X86-64 or :ARM64."
  (declare (type (member :x86-64 :arm64) arch))
  (let* ((cpu-spec (or (assoc arch *arch-cpu-specs*)
                       (error "Unknown Mach-O arch: ~S" arch)))
          (builder (make-instance 'mach-o-builder)))
    (setf (slot-value builder 'header)
          (make-mach-header :cputype    (second cpu-spec)
                            :cpusubtype (third  cpu-spec)))
     (setf (mach-o-builder-entry-point builder)
           (make-entry-point-command))
    (setf (gethash "/usr/lib/libSystem.B.dylib"
                   (mach-o-builder-bind-ordinal-table builder))
          1)
     builder))

(defun add-text-segment (builder code-bytes &key (base-addr +macho-text-base-addr+))
  "Add __TEXT segment with code to BUILDER.
CODE-BYTES should be a simple-array of (unsigned-byte 8).
BASE-ADDR is the virtual memory address for the segment.

The byte order is preserved exactly; native pipeline layout passes such as
PIPELINE-REORDER-FUNCTIONS must run before CODE-BYTES is handed to the Mach-O
builder."
  (declare (type mach-o-builder builder)
           (type (simple-array (unsigned-byte 8) (*)) code-bytes))
  (let* ((code-size (length code-bytes))
         (text-section (make-section
                        :sectname "__text"
                        :segname "__TEXT"
                        :addr base-addr
                        :size code-size
                        :align 4  ; 2^4 = 16-byte alignment
                        :flags (logior +s-attr-pure-instructions+
                                       +s-attr-some-instructions+)))
         (text-segment (make-segment-command
                        :segname "__TEXT"
                        :vmaddr base-addr
                        :vmsize (align-up code-size #x1000)
                        :payload code-bytes
                        :nsects 1
                        :cmdsize (+ +macho-segment-command-size+ (* +macho-section-size+ 1))
                        :sections (list text-section))))
    (push text-segment (mach-o-builder-segments builder))
    builder))

(defun %make-pagezero-segment ()
  "Create the __PAGEZERO segment required for Mach-O executables."
  (make-segment-command
   :segname "__PAGEZERO"
   :vmaddr 0
   :vmsize +macho-text-base-addr+
   :fileoff 0
   :filesize 0
   :maxprot 0
   :initprot 0
   :nsects 0
   :cmdsize +macho-segment-command-size+
   :sections nil))

(defun %make-linkedit-segment (fileoff filesize vmaddr)
  "Create the __LINKEDIT segment required for code signing."
  (make-segment-command
   :segname "__LINKEDIT"
   :vmaddr vmaddr
   :vmsize (max #x1000 (align-up filesize #x1000))
   :fileoff fileoff
   :filesize filesize
   :maxprot 1
   :initprot 1
   :nsects 0
   :cmdsize +macho-segment-command-size+
   :sections nil))

(defun add-data-segment (builder data-bytes &key (base-addr +macho-data-base-addr+))
  "Add __DATA segment to BUILDER.
DATA-BYTES should be a simple-array of (unsigned-byte 8).
BASE-ADDR is the virtual memory address for the segment."
  (declare (type mach-o-builder builder)
           (type (simple-array (unsigned-byte 8) (*)) data-bytes))
  (let* ((data-size (length data-bytes))
         (data-section (make-section
                        :sectname "__data"
                        :segname "__DATA"
                        :addr base-addr
                        :size data-size
                        :align 4))
          (data-segment (make-segment-command
                         :segname "__DATA"
                         :vmaddr base-addr
                         :vmsize (align-up data-size #x1000)
                         :payload data-bytes
                         :nsects 1
                         :maxprot 6    ; rw-
                         :initprot 6   ; rw
                         :cmdsize (+ +macho-segment-command-size+ (* +macho-section-size+ 1))
                         :sections (list data-section))))
    (push data-segment (mach-o-builder-segments builder))
    builder))

(defun %mach-o-find-data-const-segment (builder)
  "Return BUILDER's existing __DATA_CONST segment, if any."
  (find "__DATA_CONST" (mach-o-builder-segments builder)
        :key #'segment-command-segname :test #'string=))

(defun %mach-o-append-data-const-bytes (segment const-bytes)
  "Append CONST-BYTES to SEGMENT's __const payload and update section sizes."
  (let* ((old-payload (segment-command-payload segment))
         (old-size (length old-payload))
         (new-size (+ old-size (length const-bytes)))
         (payload (make-array new-size :element-type '(unsigned-byte 8)
                              :initial-element 0))
         (section (or (find "__const" (segment-command-sections segment)
                            :key #'section-sectname :test #'string=)
                      (make-section :sectname "__const"
                                    :segname "__DATA_CONST"
                                    :addr (segment-command-vmaddr segment)
                                    :align 4))))
    (replace payload old-payload :start1 0)
    (replace payload const-bytes :start1 old-size)
    (setf (section-size section) new-size
          (segment-command-payload segment) payload
          (segment-command-vmsize segment) (align-up new-size #x1000)
          (segment-command-filesize segment) new-size
          (segment-command-nsects segment) 1
          (segment-command-cmdsize segment) (+ +macho-segment-command-size+ +macho-section-size+)
          (segment-command-maxprot segment) 4
          (segment-command-initprot segment) 4
          (segment-command-sections segment) (list section))
    old-size))

(defun add-data-const-segment (builder const-bytes &key (base-addr +macho-data-const-base-addr+))
  "Add a read-only __DATA_CONST segment for immutable constants.

String literals and constant pools should use this segment instead of __DATA.
It is emitted with read-only max/init protections (r--) so writes to mapped
constant data are rejected by the operating system."
  (declare (type mach-o-builder builder)
            (type (simple-array (unsigned-byte 8) (*)) const-bytes))
  (let* ((dedup-key (coerce const-bytes 'list))
         (existing (gethash dedup-key (mach-o-builder-data-const-dedup-table builder))))
    (unless existing
      (let ((segment (or (%mach-o-find-data-const-segment builder)
                         (let ((new-segment
                                 (make-segment-command
                                  :segname "__DATA_CONST"
                                  :vmaddr base-addr
                                  :vmsize #x1000
                                  :payload (make-array 0 :element-type '(unsigned-byte 8))
                                  :nsects 1
                                  :maxprot 4    ; r--
                                  :initprot 4   ; r--
                                  :cmdsize (+ +macho-segment-command-size+ (* +macho-section-size+ 1))
                                  :sections (list (make-section
                                                   :sectname "__const"
                                                   :segname "__DATA_CONST"
                                                   :addr base-addr
                                                   :size 0
                                                   :align 4)))))
                           (push new-segment (mach-o-builder-segments builder))
                           new-segment))))
        (setf (gethash dedup-key (mach-o-builder-data-const-dedup-table builder))
              (%mach-o-append-data-const-bytes segment const-bytes)))))
  builder)

(defun add-symbol (builder name &key (value 0) (type 0) (sect 1))
  "Add a symbol to the builder's symbol table.
NAME is the symbol name string.
VALUE is the symbol's address/value.
TYPE is the symbol type byte.
SECT is the section number."
  (declare (type mach-o-builder builder)
           (type string name))
  (let ((strx (fill-pointer (mach-o-builder-string-table builder))))
    ;; Add name to string table (null-terminated)
    (loop for char across name
          do (vector-push-extend (char-code char)
                                 (mach-o-builder-string-table builder)))
    (vector-push-extend 0 (mach-o-builder-string-table builder))
    ;; Create nlist entry
    (setf (gethash name (mach-o-builder-symbol-index builder))
          (length (mach-o-builder-symbol-table builder)))
    (push (make-nlist :n-strx strx
                      :n-type type
                      :n-sect sect
                      :n-value value)
          (mach-o-builder-symbol-table builder)))
  builder)

(defun %mach-o-symbol-index (builder name)
  "Return the Mach-O symbol table index for NAME, or NIL when absent."
  (gethash name (mach-o-builder-symbol-index builder)))

(defun %ensure-undefined-symbol (builder name)
  "Ensure NAME exists as an undefined external symbol and return its index."
  (or (%mach-o-symbol-index builder name)
      (progn
        (add-symbol builder name :type (logior +n-undef+ +n-ext+) :sect 0)
        (%mach-o-symbol-index builder name))))

(defun add-relocation (builder offset symbol-name
                       &key (pcrel 1) (length 2) (extern 1)
                         (type +x86-64-reloc-branch+) (section "__text"))
  "Add a Mach-O relocation against SYMBOL-NAME at section-relative OFFSET.

This is suitable for unresolved external calls by default.  GOT references can
pass TYPE as +X86-64-RELOC-GOT-LOAD+, +ARM64-RELOC-PAGE21+, or
+ARM64-RELOC-PAGEOFF12+ as appropriate."
  (declare (type mach-o-builder builder)
           (type (unsigned-byte 32) offset)
           (type string symbol-name section))
  (%ensure-undefined-symbol builder symbol-name)
  (push (list :section section
              :offset offset
              :symbol symbol-name
              :pcrel pcrel
              :length length
              :extern extern
              :type type)
        (mach-o-builder-relocations builder))
  builder)

(defun %mach-o-relocation-infos (builder)
  "Resolve pending builder relocation references into relocation-info records."
  (loop for reloc in (nreverse (mach-o-builder-relocations builder))
        for symbol = (getf reloc :symbol)
        collect (make-relocation-info
                 :r-address (getf reloc :offset)
                 :r-symbolnum (%ensure-undefined-symbol builder symbol)
                 :r-pcrel (getf reloc :pcrel)
                 :r-length (getf reloc :length)
                 :r-extern (getf reloc :extern)
                 :r-type (getf reloc :type))))

(defun add-entry-point (builder offset)
  "Add LC_MAIN entry point with file OFFSET."
  (declare (type mach-o-builder builder)
           (type (unsigned-byte 64) offset))
  (setf (entry-point-command-entryoff (mach-o-builder-entry-point builder))
        offset)
  builder)
