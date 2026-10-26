;;;; packages/binary/src/dwarf.lisp — FR-550/552 DWARF v5 debug info

(in-package :cl-cc/binary)

;;; DWARF tags, attributes, forms, opcodes, and constants used by the compact
;;; producer below.  The emitter intentionally stays leaf-local to cl-cc/binary:
;;; callers pass already-lowered source/line and post-regalloc location metadata.

(defconstant +dwarf-dw-ut-compile+ #x01)
(defconstant +dwarf-dw-tag-compile-unit+ #x11)
(defconstant +dwarf-dw-tag-subprogram+ #x2e)
(defconstant +dwarf-dw-tag-formal-parameter+ #x05)
(defconstant +dwarf-dw-tag-variable+ #x34)

(defconstant +dwarf-dw-children-no+ 0)
(defconstant +dwarf-dw-children-yes+ 1)

(defconstant +dwarf-dw-at-name+ #x03)
(defconstant +dwarf-dw-at-stmt-list+ #x10)
(defconstant +dwarf-dw-at-low-pc+ #x11)
(defconstant +dwarf-dw-at-high-pc+ #x12)
(defconstant +dwarf-dw-at-language+ #x13)
(defconstant +dwarf-dw-at-producer+ #x25)
(defconstant +dwarf-dw-at-location+ #x02)

(defconstant +dwarf-dw-form-addr+ #x01)
(defconstant +dwarf-dw-form-data2+ #x05)
(defconstant +dwarf-dw-form-data8+ #x07)
(defconstant +dwarf-dw-form-strp+ #x0e)
(defconstant +dwarf-dw-form-sec-offset+ #x17)
(defconstant +dwarf-dw-form-exprloc+ #x18)

(defconstant +dwarf-dw-lang-common-lisp+ #x001c)

(defconstant +dwarf-dw-op-reg0+ #x50)
(defconstant +dwarf-dw-op-breg0+ #x70)
(defconstant +dwarf-dw-op-fbreg+ #x91)

(defconstant +dwarf-dw-lns-copy+ 1)
(defconstant +dwarf-dw-lns-advance-pc+ 2)
(defconstant +dwarf-dw-lns-advance-line+ 3)
(defconstant +dwarf-dw-lne-end-sequence+ 1)

(defstruct dwarf-variable-location
  "A source variable's physical location over a PC range after register allocation."
  (name "" :type string)
  (kind :register :type symbol)
  (register 0 :type integer)
  (offset 0 :type integer)
  (pc-start 0 :type integer)
  (pc-end 0 :type integer))

(defstruct dwarf-subprogram
  "A DW_TAG_subprogram DIE with parameter and local-variable children."
  (name "<anonymous>" :type string)
  (low-pc 0 :type integer)
  (high-pc 0 :type integer)
  (parameters nil :type list)
  (variables nil :type list))

(defstruct dwarf-compile-unit
  "A DW_TAG_compile_unit DIE and the line/location metadata attached to it."
  (name "<unknown>" :type string)
  (producer "cl-cc 0.1.0" :type string)
  (low-pc 0 :type integer)
  (high-pc 0 :type integer)
  (subprograms nil :type list)
  ;; Entries are (pc line &optional column file-index).
  (lines nil :type list))

(defstruct dwarf-debug-sections
  "DWARF section payloads suitable for ELF/Mach-O debug-section insertion."
  (info #() :type vector)
  (abbrev #() :type vector)
  (line #() :type vector)
  (str #() :type vector)
  (loc #() :type vector))

(defun %dwarf-u8 (buf value) (elf-buf-u8 buf value))

(defun %dwarf-u16 (buf value) (binary-buffer-write-u16le buf value))
(defun %dwarf-u32 (buf value) (binary-buffer-write-u32le buf value))
(defun %dwarf-u64 (buf value) (binary-buffer-write-u64le buf value))
(defun %dwarf-s64 (buf value) (binary-buffer-write-s64le buf value))
(defun %dwarf-bytes (buf bytes) (binary-buffer-write-bytes buf bytes))

(defun %dwarf-write-abbrev-attr (buf attr form)
  (elf64-write-uleb128 buf attr)
  (elf64-write-uleb128 buf form))

(defun %dwarf-string-table (strings)
  "Return a string table builder populated with STRINGS."
  (let ((st (make-strtab)))
    (dolist (string strings st)
      (strtab-add st (or string "")))))

(defun %dwarf-cu-strings (cu)
  (let ((strings (list (dwarf-compile-unit-name cu)
                       (dwarf-compile-unit-producer cu))))
    (dolist (sp (dwarf-compile-unit-subprograms cu))
      (push (dwarf-subprogram-name sp) strings)
      (dolist (param (dwarf-subprogram-parameters sp))
        (push (dwarf-variable-location-name param) strings))
      (dolist (var (dwarf-subprogram-variables sp))
        (push (dwarf-variable-location-name var) strings)))
    (remove-duplicates strings :test #'string=)))

(defparameter *dwarf-abbrev-table*
  `((1 ,+dwarf-dw-tag-compile-unit+ ,+dwarf-dw-children-yes+
     ((,+dwarf-dw-at-name+ ,+dwarf-dw-form-strp+)
      (,+dwarf-dw-at-producer+ ,+dwarf-dw-form-strp+)
      (,+dwarf-dw-at-language+ ,+dwarf-dw-form-data2+)
      (,+dwarf-dw-at-low-pc+ ,+dwarf-dw-form-addr+)
      (,+dwarf-dw-at-high-pc+ ,+dwarf-dw-form-data8+)
      (,+dwarf-dw-at-stmt-list+ ,+dwarf-dw-form-sec-offset+)))
    (2 ,+dwarf-dw-tag-subprogram+ ,+dwarf-dw-children-yes+
     ((,+dwarf-dw-at-name+ ,+dwarf-dw-form-strp+)
      (,+dwarf-dw-at-low-pc+ ,+dwarf-dw-form-addr+)
      (,+dwarf-dw-at-high-pc+ ,+dwarf-dw-form-data8+)))
    (3 ,+dwarf-dw-tag-formal-parameter+ ,+dwarf-dw-children-no+
     ((,+dwarf-dw-at-name+ ,+dwarf-dw-form-strp+)
      (,+dwarf-dw-at-location+ ,+dwarf-dw-form-exprloc+)))
    (4 ,+dwarf-dw-tag-variable+ ,+dwarf-dw-children-no+
     ((,+dwarf-dw-at-name+ ,+dwarf-dw-form-strp+)
      (,+dwarf-dw-at-location+ ,+dwarf-dw-form-exprloc+))))
  "DWARF5 .debug_abbrev table: one (ABBREV-CODE TAG HAS-CHILDREN ATTRS) entry
per DIE kind this producer emits, where ATTRS is a list of (ATTRIBUTE FORM)
pairs. BUILD-DWARF-ABBREV-SECTION is this table's interpreter; adding a DIE
kind to the compact producer is a new row here, not new emission code.")

(defun build-dwarf-abbrev-section ()
  "Build .debug_abbrev for every DIE kind in *DWARF-ABBREV-TABLE*."
  (with-byte-buffer (buf)
    (dolist (entry *dwarf-abbrev-table*)
      (destructuring-bind (code tag has-children attrs) entry
        (elf64-write-uleb128 buf code)
        (elf64-write-uleb128 buf tag)
        (%dwarf-u8 buf has-children)
        (dolist (attr attrs)
          (destructuring-bind (attribute form) attr
            (%dwarf-write-abbrev-attr buf attribute form)))
        (%dwarf-write-abbrev-attr buf 0 0)))
    ;; End abbrev table.
    (elf64-write-uleb128 buf 0)))

(defun dwarf-location-expression (location)
  "Return a DWARF expression for LOCATION using DW_OP_regN/bregN/fbreg."
  (let ((kind (dwarf-variable-location-kind location))
        (reg (dwarf-variable-location-register location))
        (offset (dwarf-variable-location-offset location)))
    (with-byte-buffer (buf)
      (ecase kind
        (:register
         (unless (<= 0 reg 31)
           (error 'value-out-of-range :operation "DW_OP_reg" :value reg :low 0 :high 31))
         (%dwarf-u8 buf (+ +dwarf-dw-op-reg0+ reg)))
        (:base-register
         (unless (<= 0 reg 31)
           (error 'value-out-of-range :operation "DW_OP_breg" :value reg :low 0 :high 31))
         (%dwarf-u8 buf (+ +dwarf-dw-op-breg0+ reg))
         (elf64-write-sleb128 buf offset))
        (:frame-base
         (%dwarf-u8 buf +dwarf-dw-op-fbreg+)
         (elf64-write-sleb128 buf offset))))))

(defun %dwarf-write-exprloc (buf expr)
  (elf64-write-uleb128 buf (length expr))
  (%dwarf-bytes buf expr))

(defun %dwarf-write-variable-die (buf strtab abbrev-code location)
  (elf64-write-uleb128 buf abbrev-code)
  (%dwarf-u32 buf (strtab-add strtab (dwarf-variable-location-name location)))
  (%dwarf-write-exprloc buf (dwarf-location-expression location)))

(defun build-dwarf-info-section (cu strtab)
  "Build .debug_info containing one DWARF5 compile unit and children."
  (let ((body
          ;; CU DIE.
          (with-byte-buffer (body)
            (elf64-write-uleb128 body 1)
            (%dwarf-u32 body (strtab-add strtab (dwarf-compile-unit-name cu)))
            (%dwarf-u32 body (strtab-add strtab (dwarf-compile-unit-producer cu)))
            (%dwarf-u16 body +dwarf-dw-lang-common-lisp+)
            (%dwarf-u64 body (dwarf-compile-unit-low-pc cu))
            (%dwarf-u64 body (max 0 (- (dwarf-compile-unit-high-pc cu)
                                       (dwarf-compile-unit-low-pc cu))))
            (%dwarf-u32 body 0) ; .debug_line offset
            (dolist (sp (dwarf-compile-unit-subprograms cu))
              (elf64-write-uleb128 body 2)
              (%dwarf-u32 body (strtab-add strtab (dwarf-subprogram-name sp)))
              (%dwarf-u64 body (dwarf-subprogram-low-pc sp))
              (%dwarf-u64 body (max 0 (- (dwarf-subprogram-high-pc sp)
                                         (dwarf-subprogram-low-pc sp))))
              (dolist (param (dwarf-subprogram-parameters sp))
                (%dwarf-write-variable-die body strtab 3 param))
              (dolist (var (dwarf-subprogram-variables sp))
                (%dwarf-write-variable-die body strtab 4 var))
              (elf64-write-uleb128 body 0)) ; end subprogram children
            (elf64-write-uleb128 body 0)))) ; end CU children
    ;; DWARF5 unit header: unit_length, version, unit_type, addr_size, abbrev_offset.
    (with-byte-buffer (buf)
      (%dwarf-u32 buf (+ 2 1 1 4 (length body)))
      (%dwarf-u16 buf 5)
      (%dwarf-u8 buf +dwarf-dw-ut-compile+)
      (%dwarf-u8 buf 8)
      (%dwarf-u32 buf 0)
      (%dwarf-bytes buf body))))

(defun build-dwarf-line-section (cu)
  "Build a compact .debug_line program with DW_LNS_copy/advance_pc/advance_line."
  (let ((body
          (with-byte-buffer (body)
            (let ((last-pc 0) (last-line 1))
              (dolist (entry (sort (copy-list (dwarf-compile-unit-lines cu)) #'< :key #'first))
                (destructuring-bind (pc line &optional column file-index) entry
                  (declare (ignore column file-index))
                  (%dwarf-u8 body +dwarf-dw-lns-advance-pc+)
                  (elf64-write-uleb128 body (max 0 (- pc last-pc)))
                  (%dwarf-u8 body +dwarf-dw-lns-advance-line+)
                  (elf64-write-sleb128 body (- line last-line))
                  (%dwarf-u8 body +dwarf-dw-lns-copy+)
                  (setf last-pc pc last-line line))))
            ;; Extended end_sequence.
            (%dwarf-u8 body 0)
            (elf64-write-uleb128 body 1)
            (%dwarf-u8 body +dwarf-dw-lne-end-sequence+)))
        (header
          ;; Minimal DWARF5 line header: address size/segment selector, dirs/files formats empty.
          (with-byte-buffer (header)
            (%dwarf-u8 header 1) ; min instruction length
            (%dwarf-u8 header 1) ; max ops per instruction
            (%dwarf-u8 header 1) ; default_is_stmt
            (%dwarf-u8 header (logand -5 #xff)) ; line_base
            (%dwarf-u8 header 14) ; line_range
            (%dwarf-u8 header 13) ; opcode_base
            (dotimes (_ 12) (declare (ignore _)) (%dwarf-u8 header 0))
            (%dwarf-u8 header 0) ; directory_entry_format_count
            (elf64-write-uleb128 header 0) ; directories_count
            (%dwarf-u8 header 0) ; file_name_entry_format_count
            (elf64-write-uleb128 header 0)))) ; file_names_count
    (with-byte-buffer (buf)
      (%dwarf-u32 buf (+ 2 1 1 4 (length header) (length body)))
      (%dwarf-u16 buf 5)
      (%dwarf-u8 buf 8)
      (%dwarf-u8 buf 0)
      (%dwarf-u32 buf (length header))
      (%dwarf-bytes buf header)
      (%dwarf-bytes buf body))))

(defun build-dwarf-loc-section (cu)
  "Build a .debug_loc payload containing simple PC range + expression records."
  (with-byte-buffer (buf)
    (dolist (sp (dwarf-compile-unit-subprograms cu))
      (dolist (loc (append (dwarf-subprogram-parameters sp)
                           (dwarf-subprogram-variables sp)))
        (let ((expr (dwarf-location-expression loc)))
          (%dwarf-u64 buf (dwarf-variable-location-pc-start loc))
          (%dwarf-u64 buf (dwarf-variable-location-pc-end loc))
          (%dwarf-u16 buf (length expr))
          (%dwarf-bytes buf expr))))
    ;; Terminating base/end pair.
    (%dwarf-u64 buf 0)
    (%dwarf-u64 buf 0)))

(defun build-dwarf-debug-sections (compile-unit)
  "Build .debug_info/.debug_abbrev/.debug_line/.debug_str/.debug_loc payloads."
  (check-type compile-unit dwarf-compile-unit)
  (let* ((strtab (%dwarf-string-table (%dwarf-cu-strings compile-unit)))
         (info (build-dwarf-info-section compile-unit strtab))
         (abbrev (build-dwarf-abbrev-section))
         (line (build-dwarf-line-section compile-unit))
         (loc (build-dwarf-loc-section compile-unit))
         (strings (strtab-bytes strtab)))
    (make-dwarf-debug-sections :info info :abbrev abbrev :line line :str strings :loc loc)))

