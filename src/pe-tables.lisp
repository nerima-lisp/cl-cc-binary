(in-package :cl-cc/binary)

;;; ------------------------------------------------------------
;;; Byte helpers
;;; ------------------------------------------------------------

(defun %pe-ub8-vector (bytes)
  "Return BYTES as a simple unsigned-byte 8 vector."
  (coerce bytes '(simple-array (unsigned-byte 8) (*))))

(defun %pe-ascii-bytes (string &key (nul t))
  "Return STRING as ASCII bytes, optionally NUL terminated."
  (let* ((extra (if nul 1 0))
         (bytes (make-array (+ (length string) extra)
                            :element-type '(unsigned-byte 8)
                            :initial-element 0)))
    (loop for char across string
          for i from 0
          do (setf (aref bytes i) (char-code char)))
    bytes))

(defun %pe-write-fixed-name (buf name)
  "Write an 8-byte COFF section name field."
  (dotimes (i 8)
    (binary-buffer-write-u8 buf (if (< i (length name))
                                    (char-code (char name i))
                                    0))))

(defun %pe-patch-u16le (bytes offset value)
  (setf (aref bytes offset) (logand value #xff)
        (aref bytes (1+ offset)) (logand (ash value -8) #xff)))

(defun %pe-patch-u32le (bytes offset value)
  (setf (aref bytes offset) (logand value #xff)
        (aref bytes (1+ offset)) (logand (ash value -8) #xff)
        (aref bytes (+ offset 2)) (logand (ash value -16) #xff)
        (aref bytes (+ offset 3)) (logand (ash value -24) #xff)))

(defun %pe-pad-to (buf size)
  (binary-buffer-write-pad buf (max 0 (- size (length buf)))))

(defun %pe-pad-to-align (buf alignment)
  (binary-buffer-write-pad buf (- (align-up (length buf) alignment) (length buf))))

;;; ------------------------------------------------------------
;;; DOS stub and data directories
;;; ------------------------------------------------------------

(defun pe-build-dos-stub ()
  "Build an MZ DOS header plus a tiny DOS message stub.

The first 64 bytes are the DOS header.  E_LFANEW points at #x80 where the PE
signature is written.  The DOS program prints a Windows-required message when
run as a DOS executable."
  (with-byte-buffer (buf)
    (binary-buffer-write-u16le buf +pe-dos-signature+)
    (binary-buffer-write-u16le buf #x0090) ; e_cblp
    (binary-buffer-write-u16le buf #x0003) ; e_cp
    (binary-buffer-write-u16le buf 0)      ; e_crlc
    (binary-buffer-write-u16le buf #x0004) ; e_cparhdr
    (binary-buffer-write-u16le buf 0)      ; e_minalloc
    (binary-buffer-write-u16le buf #xffff) ; e_maxalloc
    (binary-buffer-write-u16le buf 0)      ; e_ss
    (binary-buffer-write-u16le buf #x00b8) ; e_sp
    (binary-buffer-write-u16le buf 0)      ; e_csum
    (binary-buffer-write-u16le buf 0)      ; e_ip
    (binary-buffer-write-u16le buf 0)      ; e_cs
    (binary-buffer-write-u16le buf #x0040) ; e_lfarlc
    (binary-buffer-write-u16le buf 0)      ; e_ovno
    (binary-buffer-write-pad buf 8)        ; e_res
    (binary-buffer-write-u16le buf 0)      ; e_oemid
    (binary-buffer-write-u16le buf 0)      ; e_oeminfo
    (binary-buffer-write-pad buf 20)       ; e_res2
    (binary-buffer-write-u32le buf #x80)   ; e_lfanew
    ;; DOS code: push cs; pop ds; mov dx,msg; mov ah,09h; int 21h; mov ax,4c01h; int 21h
    (binary-buffer-write-bytes buf '(#x0e #x1f #xba #x0e #x00 #xb4 #x09 #xcd #x21
                                     #xb8 #x01 #x4c #xcd #x21))
    (binary-buffer-write-bytes buf (%pe-ascii-bytes "This program requires Windows" :nul nil))
    (binary-buffer-write-bytes buf '(#x0d #x0a #x24))
    (%pe-pad-to buf #x80)))

;;; IMAGE_EXPORT_DIRECTORY field offsets (winnt.h): a fixed 40-byte record,
;;; reserved as zero bytes in PE-BUILD-EXPORT-TABLE and patched once every
;;; field value is known (the function/name/ordinal tables that follow it in
;;; the buffer determine several of its fields, so it cannot be written
;;; sequentially the way DEFINE-BINARY-WRITER records are).
(defconstant +pe-export-dir-characteristics+      0)
(defconstant +pe-export-dir-timestamp+            4)
(defconstant +pe-export-dir-major-version+        8)
(defconstant +pe-export-dir-minor-version+       10)
(defconstant +pe-export-dir-name+                12)
(defconstant +pe-export-dir-base+                16)
(defconstant +pe-export-dir-number-of-functions+ 20)
(defconstant +pe-export-dir-number-of-names+     24)
(defconstant +pe-export-dir-address-of-functions+     28)
(defconstant +pe-export-dir-address-of-names+         32)
(defconstant +pe-export-dir-address-of-name-ordinals+ 36)
(defconstant +pe-export-dir-size+ 40)

(defun %pe-empty-directory-table ()
  (make-array +pe-number-of-rva-and-sizes+
              :initial-element (cons 0 0)))

(defun %pe-set-directory (directories index rva size)
  (setf (aref directories index) (cons rva size)))

;;; ------------------------------------------------------------
;;; Import, export, and relocation payloads
;;; ------------------------------------------------------------

(defun pe-build-import-table (imports section-rva)
  "Build an .idata section and return values: bytes, import-dir, iat-dir.

IMPORT-DIR and IAT-DIR are (RVA . SIZE) conses suitable for the optional-header
data directory table.  Imports use IMAGE_IMPORT_DESCRIPTOR, import lookup table,
hint/name entries, and IAT entries."
  (let* ((imports (reverse imports))
         (descriptor-count (length imports))
         (descriptor-size (* 20 (1+ descriptor-count)))
         (descriptors nil)
         (iat-start 0)
         (iat-end 0)
         (bytes
           (with-byte-buffer (buf)
             (binary-buffer-write-pad buf descriptor-size)
             (dolist (import imports)
               (let* ((functions (pe-import-functions import))
                      (ilt-offset (length buf)))
                 (binary-buffer-write-pad buf (* 8 (1+ (length functions))))
                 (let ((iat-offset (length buf)))
                   (when (zerop iat-start)
                     (setf iat-start iat-offset))
                   (binary-buffer-write-pad buf (* 8 (1+ (length functions))))
                   (let ((name-rvas nil))
                     (dolist (function functions)
                       (%pe-pad-to-align buf 2)
                       (let ((hint-name-offset (length buf)))
                         (binary-buffer-write-u16le buf 0)
                         (binary-buffer-write-bytes buf (%pe-ascii-bytes function))
                         (push (+ section-rva hint-name-offset) name-rvas)))
                     (let ((dll-name-offset (length buf)))
                       (binary-buffer-write-bytes
                        buf (%pe-ascii-bytes (pe-import-dll-name import)))
                       (let ((name-rvas (nreverse name-rvas)))
                         (loop for rva in name-rvas
                               for i from 0
                               do (%pe-patch-u32le buf (+ ilt-offset (* i 8)) rva)
                                  (%pe-patch-u32le buf (+ iat-offset (* i 8)) rva))
                         (push (list :ilt (+ section-rva ilt-offset)
                                     :name (+ section-rva dll-name-offset)
                                     :iat (+ section-rva iat-offset))
                               descriptors)
                         (setf iat-end
                               (+ iat-offset (* 8 (1+ (length functions)))))))))))
             (loop for descriptor in (nreverse descriptors)
                   for offset from 0 by 20
                   do (%pe-patch-u32le buf offset (getf descriptor :ilt))
                      (%pe-patch-u32le buf (+ offset 12) (getf descriptor :name))
                      (%pe-patch-u32le buf (+ offset 16) (getf descriptor :iat))))))
    (values bytes
            (cons section-rva descriptor-size)
            (cons (+ section-rva iat-start) (- iat-end iat-start)))))

(defun pe-build-export-table (exports section-rva dll-name)
  "Build an .edata export table for EXPORTS.

EXPORTS is a list of PE-EXPORT structures with function RVAs.  Returns bytes and
an export directory cons (RVA . SIZE)."
  (let* ((exports (sort (copy-list exports) #'string< :key #'pe-export-name))
         (count (length exports))
         (buf (elf-make-buffer)))
    (when (zerop count)
      (return-from pe-build-export-table
        (values (make-array 0 :element-type '(unsigned-byte 8)) (cons 0 0))))
    ;; IMAGE_EXPORT_DIRECTORY placeholder.
    (binary-buffer-write-pad buf +pe-export-dir-size+)
    (let* ((dll-name-offset (length buf))
           (ordinal-base 1)
           (function-table-offset (progn
                                    (binary-buffer-write-bytes buf (%pe-ascii-bytes dll-name))
                                    (%pe-pad-to-align buf 4)
                                    (length buf))))
      (dolist (export exports)
        (binary-buffer-write-u32le buf (pe-export-rva export)))
      (let ((name-pointer-offset (length buf)))
        (binary-buffer-write-pad buf (* 4 count))
        (let ((ordinal-table-offset (length buf)))
          (dolist (export exports)
            (binary-buffer-write-u16le buf (- (pe-export-ordinal export) ordinal-base)))
          (let ((name-rvas nil))
            (dolist (export exports)
              (let ((name-offset (length buf)))
                (binary-buffer-write-bytes buf (%pe-ascii-bytes (pe-export-name export)))
                (push (+ section-rva name-offset) name-rvas)))
            (loop for name-rva in (nreverse name-rvas)
                  for offset from name-pointer-offset by 4
                  do (%pe-patch-u32le buf offset name-rva))
            (%pe-patch-u32le buf +pe-export-dir-characteristics+ 0)
            (%pe-patch-u32le buf +pe-export-dir-timestamp+ 0)
            (%pe-patch-u16le buf +pe-export-dir-major-version+ 0)
            (%pe-patch-u16le buf +pe-export-dir-minor-version+ 0)
            (%pe-patch-u32le buf +pe-export-dir-name+ (+ section-rva dll-name-offset))
            (%pe-patch-u32le buf +pe-export-dir-base+ ordinal-base)
            (%pe-patch-u32le buf +pe-export-dir-number-of-functions+ count)
            (%pe-patch-u32le buf +pe-export-dir-number-of-names+ count)
            (%pe-patch-u32le buf +pe-export-dir-address-of-functions+
                             (+ section-rva function-table-offset))
            (%pe-patch-u32le buf +pe-export-dir-address-of-names+
                             (+ section-rva name-pointer-offset))
            (%pe-patch-u32le buf +pe-export-dir-address-of-name-ordinals+
                             (+ section-rva ordinal-table-offset))))))
    (let ((bytes (binary-buffer-to-array buf)))
      (values bytes (cons section-rva (length bytes))))))

(defun pe-build-base-relocations (relocation-rvas section-rva)
  "Build a .reloc payload with IMAGE_REL_BASED_DIR64 entries."
  (declare (ignore section-rva))
  (let ((pages (make-hash-table)))
    (dolist (rva relocation-rvas)
      (let ((page (logand rva #xfffff000))
            (offset (logand rva #xfff)))
        (push offset (gethash page pages))))
    (with-byte-buffer (buf)
      (maphash
       (lambda (page offsets)
         (let* ((entries (sort (copy-list offsets) #'<))
                (entry-count (+ (length entries) (if (oddp (length entries)) 1 0)))
                (block-size (+ 8 (* 2 entry-count))))
           (binary-buffer-write-u32le buf page)
           (binary-buffer-write-u32le buf block-size)
           (dolist (offset entries)
             (binary-buffer-write-u16le buf (logior (ash +pe-reloc-dir64+ 12) offset)))
           (when (oddp (length entries))
             (binary-buffer-write-u16le buf (ash +pe-reloc-absolute+ 12)))))
       pages))))
