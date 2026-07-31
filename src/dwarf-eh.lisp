;;;; packages/binary/src/dwarf-eh.lisp — DWARF .eh_frame call-frame information
;;;;
;;;; FR-560: Table-based zero-cost exception handling infrastructure.
;;;; This file emits .eh_frame CIE/FDE records for x86-64.  These records are
;;;; DWARF call-frame instructions consumed by libunwind/_Unwind_RaiseException;
;;;; they are not .debug_frame debug information.

(in-package :cl-cc/binary)

;;; DWARF CFI opcodes used by the compact .eh_frame producer.
(defconstant +dw-cfa-nop+ #x00)
(defconstant +dw-cfa-advance-loc+ #x40)
(defconstant +dw-cfa-offset+ #x80)
(defconstant +dw-cfa-restore+ #xc0)
(defconstant +dw-cfa-def-cfa+ #x0c)
(defconstant +dw-cfa-def-cfa-offset+ #x0e)

;;; DWARF register numbers for the x86-64 System V ABI.
(defconstant +dwarf-reg-x86-64-rsp+ 7)
(defconstant +dwarf-reg-x86-64-rip+ 16)

;;; DW_EH_PE encodings used by the "zPLR" CIE augmentation.
(defconstant +dw-eh-pe-omit+ #xff)
(defconstant +dw-eh-pe-absptr+ #x00)
(defconstant +dw-eh-pe-uleb128+ #x01)
(defconstant +dw-eh-pe-pcrel-sdata4+ #x1b)

(defstruct dwarf-eh-fde
  "A single .eh_frame FDE range with optional call-frame instructions."
  (initial-location 0 :type integer)
  (address-range 0 :type integer)
  (instructions nil :type list)
  (personality nil)
  (lsda nil))

(defstruct dwarf-eh-call-site
  "One LSDA call-site table row.

START and LENGTH are function-relative protected-region offsets. LANDING-PAD is
the function-relative landing-pad offset. ACTION is the one-based action-table
index used by the Itanium ABI; zero means cleanup-only/no typed handler. TYPE is
the CL condition type stored in the cl-cc type table extension."
  (start 0 :type integer)
  (length 0 :type integer)
  (landing-pad 0 :type integer)
  (action 0 :type integer)
  (type t)
  (cleanup-p nil :type boolean))

(defstruct dwarf-eh-frame
  "A complete .eh_frame payload model containing one CIE and zero or more FDEs."
  (code-alignment-factor 1 :type integer)
  (data-alignment-factor -8 :type integer)
  (return-address-register +dwarf-reg-x86-64-rip+ :type integer)
  (fde-list nil :type list))

(defun dwarf-eh-pad-to-align (buf alignment)
  "Pad BUF with DW_CFA_nop up to ALIGNMENT bytes."
  (loop while (not (zerop (mod (length buf) alignment)))
        do (elf-buf-u8 buf +dw-cfa-nop+)))

(defun dwarf-eh-emit-def-cfa (buf register offset)
  "Emit DW_CFA_def_cfa REGISTER OFFSET."
  (elf-buf-u8 buf +dw-cfa-def-cfa+)
  (elf64-write-uleb128 buf register)
  (elf64-write-uleb128 buf offset))

(defun dwarf-eh-emit-def-cfa-offset (buf offset)
  "Emit DW_CFA_def_cfa_offset OFFSET."
  (elf-buf-u8 buf +dw-cfa-def-cfa-offset+)
  (elf64-write-uleb128 buf offset))

(defmacro define-dwarf-cfa-short-form (name lambda-list &key opcode operation-name checked-var
                                                            trailing-body)
  "Define NAME as a DWARF .eh_frame short-form CFA instruction emitter.

Every short form packs one argument into the low 6 bits of an OPCODE byte, so
CHECKED-VAR (one of LAMBDA-LIST's parameters) must be 0..#x3f; OPERATION-NAME
names it in the VALUE-OUT-OF-RANGE condition raised otherwise. TRAILING-BODY,
if given, is spliced in after the opcode byte for short forms (like
DW_CFA_offset) that carry an additional operand."
  (let ((buf-var (first lambda-list)))
    `(defun ,name ,lambda-list
       ,(format nil "Emit ~A using the short form." operation-name)
       (unless (<= 0 ,checked-var #x3f)
         (error 'value-out-of-range :operation ,operation-name
                                     :value ,checked-var :low 0 :high #x3f))
       (elf-buf-u8 ,buf-var (logior ,opcode ,checked-var))
       ,@trailing-body)))

(define-dwarf-cfa-short-form dwarf-eh-emit-offset (buf register factored-offset)
  :opcode +dw-cfa-offset+ :operation-name "DW_CFA_offset" :checked-var register
  :trailing-body ((elf64-write-uleb128 buf factored-offset)))

(define-dwarf-cfa-short-form dwarf-eh-emit-advance-loc (buf delta)
  :opcode +dw-cfa-advance-loc+ :operation-name "DW_CFA_advance_loc" :checked-var delta)

(define-dwarf-cfa-short-form dwarf-eh-emit-restore (buf register)
  :opcode +dw-cfa-restore+ :operation-name "DW_CFA_restore" :checked-var register)

(defun dwarf-eh-condition-type-tag (type)
  "Return a deterministic 31-bit tag for CL condition TYPE names in LSDA.

The native runtime maps these tags back to condition class objects in its type
registry.  The textual symbol name is intentionally not emitted into executable
EH tables, keeping LSDA compact and relocation-free."
  (let* ((name (cond ((symbolp type) (format nil "~A::~A"
                                             (package-name (symbol-package type))
                                             (symbol-name type)))
                     ((typep type 'class) (format nil "CLASS::~A" type))
                     (t (prin1-to-string type))))
         (hash #x811c9dc5))
    (loop for ch across name
          do (setf hash (logand (* (logxor hash (char-code ch)) #x01000193)
                                #x7fffffff)))
    hash))

(defun dwarf-eh-write-lsda-call-site (buf call-site)
  "Append one Itanium ABI LSDA call-site row to BUF."
  (elf64-write-uleb128 buf (dwarf-eh-call-site-start call-site))
  (elf64-write-uleb128 buf (dwarf-eh-call-site-length call-site))
  (elf64-write-uleb128 buf (dwarf-eh-call-site-landing-pad call-site))
  (elf64-write-uleb128 buf (dwarf-eh-call-site-action call-site)))

(defun build-dwarf-eh-lsda (call-sites)
  "Build a compact Itanium ABI LSDA for CALL-SITES.

Layout:
  LPStart encoding      = DW_EH_PE_omit (function base comes from FDE)
  TType encoding        = DW_EH_PE_omit for pointer table; cl-cc appends a
                          relocation-free condition-type tag table instead
  Call-site encoding    = DW_EH_PE_uleb128
  Call-site table       = start, length, landing-pad, action ULEB128 tuples
  Action/type extension = count followed by (action-index, type-tag, flags)

The first four fields are consumed by libunwind personalities following the
Itanium C++ ABI.  The final compact extension is cl-cc-specific and lets the
personality verify Common Lisp condition types without C++ RTTI objects."
  (let* ((call-site-buf
           (with-byte-buffer (call-site-buf)
             (dolist (cs call-sites)
               (dwarf-eh-write-lsda-call-site call-site-buf cs))))
         (typed (remove-if #'dwarf-eh-call-site-cleanup-p call-sites)))
    (with-byte-buffer (buf)
      (elf-buf-u8 buf +dw-eh-pe-omit+)          ; LPStart omitted
      (elf-buf-u8 buf +dw-eh-pe-omit+)          ; TType pointer table omitted
      (elf-buf-u8 buf +dw-eh-pe-uleb128+)       ; call-site encoding
      (elf64-write-uleb128 buf (length call-site-buf))
      (binary-buffer-write-bytes buf call-site-buf)
      ;; cl-cc typed-handler extension.
      (elf64-write-uleb128 buf (length typed))
      (dolist (cs typed)
        (elf64-write-uleb128 buf (dwarf-eh-call-site-action cs))
        (elf64-write-uleb128 buf (dwarf-eh-condition-type-tag
                                  (dwarf-eh-call-site-type cs)))
        (elf-buf-u8 buf (if (dwarf-eh-call-site-cleanup-p cs) 1 0))))))

(defun dwarf-eh-default-cie-instructions ()
  "Return initial x86-64 CFA rules: CFA = RSP+8; RIP saved at CFA-8."
  (with-byte-buffer (buf)
    (dwarf-eh-emit-def-cfa buf +dwarf-reg-x86-64-rsp+ 8)
    ;; data alignment factor is -8, so factored offset 1 means CFA-8.
    (dwarf-eh-emit-offset buf +dwarf-reg-x86-64-rip+ 1)))

(defun dwarf-eh-encode-instruction-list (instructions)
  "Encode symbolic CFI INSTRUCTIONS into bytes.

Supported entries:
  (:def-cfa-offset offset)
  (:offset register factored-offset)
  (:advance-loc delta)
  (:restore register)
Raw byte vectors may also be supplied for pre-encoded instructions."
  (with-byte-buffer (buf)
    (dolist (inst instructions)
      (etypecase inst
        (vector (binary-buffer-write-bytes buf inst))
        (cons
         (ecase (first inst)
           (:def-cfa-offset
            (destructuring-bind (_ offset) inst
              (declare (ignore _))
              (dwarf-eh-emit-def-cfa-offset buf offset)))
           (:offset
            (destructuring-bind (_ register factored-offset) inst
              (declare (ignore _))
              (dwarf-eh-emit-offset buf register factored-offset)))
           (:advance-loc
            (destructuring-bind (_ delta) inst
              (declare (ignore _))
              (dwarf-eh-emit-advance-loc buf delta)))
           (:restore
            (destructuring-bind (_ register) inst
              (declare (ignore _))
              (dwarf-eh-emit-restore buf register)))))))))

(defun dwarf-eh-write-cie (buf frame)
  "Append one CIE to BUF and return its starting offset."
  (let* ((cie-start (length buf))
         (body
           (with-byte-buffer (body)
             (binary-buffer-write-u32le body 0) ; CIE_id for .eh_frame
             (elf-buf-u8 body 1)                ; CIE version
             (binary-buffer-write-bytes body (map 'vector #'char-code "zPLR"))
             (elf-buf-u8 body 0)                ; NUL-terminated augmentation string
             (elf64-write-uleb128 body (dwarf-eh-frame-code-alignment-factor frame))
             (elf64-write-sleb128 body (dwarf-eh-frame-data-alignment-factor frame))
             (elf64-write-uleb128 body (dwarf-eh-frame-return-address-register frame))
             ;; Augmentation data: personality encoding + placeholder personality pointer
             ;; + LSDA encoding + FDE pointer encoding.  The pure emitter has no relocation
             ;; records here, so zero is a linker-resolved placeholder for
             ;; clcc_personality_v0.
             (elf64-write-uleb128 body 7)
             (elf-buf-u8 body +dw-eh-pe-pcrel-sdata4+) ; P: personality pointer encoding
             (binary-buffer-write-u32le body 0)        ; P: clcc_personality_v0 relocation slot
             (elf-buf-u8 body +dw-eh-pe-pcrel-sdata4+) ; L: LSDA pointer encoding
             (elf-buf-u8 body +dw-eh-pe-pcrel-sdata4+) ; R: FDE initial_location/range encoding
             (binary-buffer-write-bytes body (dwarf-eh-default-cie-instructions))
             (dwarf-eh-pad-to-align body 8))))
    (binary-buffer-write-u32le buf (length body))
    (binary-buffer-write-bytes buf body)
    cie-start))

(defun dwarf-eh-write-fde (buf cie-start fde)
  "Append one FDE to BUF referencing CIE-START."
  (let* ((fde-start (length buf))
         ;; .eh_frame CIE_pointer is a backwards distance from the pointer field.
         (cie-pointer (- (+ fde-start 4) cie-start))
         (body
           (with-byte-buffer (body)
             (binary-buffer-write-u32le body cie-pointer)
             ;; With DW_EH_PE_pcrel|sdata4, relocatable objects keep initial_location at
             ;; zero for the linker/loader to resolve.  Executable images can pass an
             ;; already-finalized relative location.
             (binary-buffer-write-u32le body (logand (dwarf-eh-fde-initial-location fde)
                                                      #xffffffff))
             (binary-buffer-write-u32le body (logand (dwarf-eh-fde-address-range fde)
                                                      #xffffffff))
             (let ((lsda (dwarf-eh-fde-lsda fde)))
               (if (and lsda (plusp (length lsda)))
                   (progn
                     ;; FDE augmentation contains the pcrel sdata4 LSDA pointer.  This
                     ;; relocatable writer leaves the slot at zero; executable builders
                     ;; can place LSDA bytes in .gcc_except_table and relocate it.
                     (elf64-write-uleb128 body 4)
                     (binary-buffer-write-u32le body 0))
                   (elf64-write-uleb128 body 0)))
             (binary-buffer-write-bytes body
                                        (dwarf-eh-encode-instruction-list
                                         (dwarf-eh-fde-instructions fde)))
             (dwarf-eh-pad-to-align body 8))))
    (binary-buffer-write-u32le buf (length body))
    (binary-buffer-write-bytes buf body)))

(defun build-dwarf-eh-frame (fde-list &key (code-alignment-factor 1)
                                      (data-alignment-factor -8)
                                      (return-address-register +dwarf-reg-x86-64-rip+))
  "Build a DWARF .eh_frame payload from FDE-LIST.

Each FDE describes a protected PC range and optional frame-state transitions.
  The emitted CIE uses augmentation string zPLR, x86-64 data alignment -8, and
return-address register RIP (DWARF register 16)."
  (let ((frame (make-dwarf-eh-frame
                :code-alignment-factor code-alignment-factor
                :data-alignment-factor data-alignment-factor
                :return-address-register return-address-register
                :fde-list fde-list)))
    (with-byte-buffer (buf)
      (let ((cie-start (dwarf-eh-write-cie buf frame)))
        (dolist (fde (dwarf-eh-frame-fde-list frame))
          (dwarf-eh-write-fde buf cie-start fde))))))

