;;;; packages/binary/src/pe.lisp - PE/COFF Binary Format Support
;;;
;;; Implements PE32+ (64-bit) Windows executable and DLL image generation.
;;; Supports x86-64 and ARM64 machine types, DOS stub, PE/COFF headers,
;;; section layout, imports, exports, and base relocations.
;;;
;;; Pure Common Lisp implementation - no external dependencies.

(in-package :cl-cc/binary)

;;; ------------------------------------------------------------
;;; PE/COFF constants
;;; ------------------------------------------------------------

(defconstant +pe-dos-signature+ #x5a4d)      ; MZ
(defconstant +pe-signature+ #x00004550)      ; PE\0\0

(defconstant +pe-machine-amd64+ #x8664)
(defconstant +pe-machine-arm64+ #xaa64)

(defconstant +pe-file-executable-image+ #x0002)
(defconstant +pe-file-large-address-aware+ #x0020)
(defconstant +pe-file-dll+ #x2000)

(defconstant +pe-magic-pe32-plus+ #x020b)
(defconstant +pe-subsystem-windows-gui+ 2)
(defconstant +pe-subsystem-windows-cui+ 3)
(defconstant +pe-number-of-rva-and-sizes+ 16)

(defconstant +pe-section-cnt-code+ #x00000020)
(defconstant +pe-section-cnt-initialized-data+ #x00000040)
(defconstant +pe-section-mem-execute+ #x20000000)
(defconstant +pe-section-mem-read+ #x40000000)
(defconstant +pe-section-mem-write+ #x80000000)

(defconstant +pe-directory-export+ 0)
(defconstant +pe-directory-import+ 1)
(defconstant +pe-directory-base-reloc+ 5)
(defconstant +pe-directory-iat+ 12)

(defconstant +pe-reloc-absolute+ 0)
(defconstant +pe-reloc-dir64+ 10)

(defconstant +pe-file-alignment+ 512)
(defconstant +pe-section-alignment+ 4096)
(defconstant +pe-default-image-base-exe+ #x140000000)
(defconstant +pe-default-image-base-dll+ #x180000000)

;;; ------------------------------------------------------------
;;; Structures and builder API
;;; ------------------------------------------------------------

(defstruct pe-section
  "A PE section payload and its computed layout metadata."
  (name "" :type string)
  (data (make-array 0 :element-type '(unsigned-byte 8))
        :type (simple-array (unsigned-byte 8) (*)))
  (characteristics 0 :type (unsigned-byte 32))
  (virtual-address 0 :type (unsigned-byte 32))
  (virtual-size 0 :type (unsigned-byte 32))
  (raw-pointer 0 :type (unsigned-byte 32))
  (raw-size 0 :type (unsigned-byte 32)))

(defstruct pe-import
  "One imported DLL and its function names."
  (dll-name "" :type string)
  (functions nil :type list))

(defstruct pe-export
  "One exported symbol. RVA is the exported function RVA."
  (name "" :type string)
  (rva 0 :type (unsigned-byte 32))
  (ordinal 1 :type (unsigned-byte 16)))

(defstruct pe-builder
  "Accumulates fields for a PE32+ executable or DLL image."
  (machine +pe-machine-amd64+ :type (unsigned-byte 16))
  (dll-p nil :type boolean)
  (subsystem +pe-subsystem-windows-cui+ :type (unsigned-byte 16))
  (image-base +pe-default-image-base-exe+ :type (unsigned-byte 64))
  (entry-point 0 :type (unsigned-byte 32))
  (text (make-array 0 :element-type '(unsigned-byte 8))
        :type (simple-array (unsigned-byte 8) (*)))
  (rdata (make-array 0 :element-type '(unsigned-byte 8))
         :type (simple-array (unsigned-byte 8) (*)))
  (data (make-array 0 :element-type '(unsigned-byte 8))
        :type (simple-array (unsigned-byte 8) (*)))
  (imports (list (make-pe-import :dll-name "kernel32.dll"
                                 :functions '("ExitProcess" "GetStdHandle" "WriteConsoleA")))
           :type list)
  (exports nil :type list)
  (base-relocations nil :type list))

(defun make-pe32+-builder (&key (arch :x86-64) dll-p
                                (subsystem :console)
                                image-base)
  "Create a PE32+ builder for ARCH (:X86-64, :ARM64, or :AARCH64)."
  (let* ((machine (ecase arch
                    (:x86-64 +pe-machine-amd64+)
                    ((:arm64 :aarch64) +pe-machine-arm64+)))
         (default-base (if dll-p +pe-default-image-base-dll+ +pe-default-image-base-exe+)))
    (make-pe-builder :machine machine
                     :dll-p (and dll-p t)
                     :subsystem (ecase subsystem
                                  (:console +pe-subsystem-windows-cui+)
                                  (:gui +pe-subsystem-windows-gui+))
                     :image-base (or image-base default-base))))

(defun pe-add-text-bytes (builder bytes)
  "Set BUILDER's .text payload to BYTES."
  (setf (pe-builder-text builder) (%pe-ub8-vector bytes))
  builder)

(defun pe-add-rdata-bytes (builder bytes)
  "Set BUILDER's .rdata payload to BYTES."
  (setf (pe-builder-rdata builder) (%pe-ub8-vector bytes))
  builder)

(defun pe-add-data-bytes (builder bytes)
  "Set BUILDER's .data payload to BYTES."
  (setf (pe-builder-data builder) (%pe-ub8-vector bytes))
  builder)

(defun pe-add-import (builder dll-name function-names)
  "Add imported FUNCTION-NAMES from DLL-NAME to BUILDER."
  (push (make-pe-import :dll-name dll-name :functions function-names)
        (pe-builder-imports builder))
  builder)

(defun pe-add-export (builder name rva &key ordinal)
  "Add exported NAME at RVA to BUILDER."
  (push (make-pe-export :name name
                        :rva rva
                        :ordinal (or ordinal (1+ (length (pe-builder-exports builder)))))
        (pe-builder-exports builder))
  builder)

(defun pe-add-base-relocation (builder rva)
  "Add one IMAGE_REL_BASED_DIR64 relocation for RVA."
  (push rva (pe-builder-base-relocations builder))
  builder)

;;; ------------------------------------------------------------
;;; Windows x86-64 ABI helpers
;;; ------------------------------------------------------------

(defparameter *pe-x86-64-argument-registers* '(:rcx :rdx :r8 :r9)
  "Windows x86-64 ABI integer/pointer argument registers.")

(defconstant +pe-x86-64-shadow-space-size+ 32
  "Bytes of caller-allocated shadow space required before each call.")

(defun pe-x86-64-stack-adjustment (stack-argument-count)
  "Return bytes to reserve before a Windows x86-64 call.

The reservation includes 32 bytes of shadow space, stack arguments, and padding
to keep RSP 16-byte aligned at the call boundary.  This helper documents the ABI
contract used by native Windows call lowering."
  (let* ((base (+ +pe-x86-64-shadow-space-size+ (* 8 stack-argument-count)))
         (padding (mod (- 16 (mod base 16)) 16)))
    (+ base padding)))
