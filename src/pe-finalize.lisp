(in-package :cl-cc/binary)

;;; ------------------------------------------------------------
;;; Headers and final image assembly
;;; ------------------------------------------------------------

(defun %pe-make-section (name data characteristics)
  (make-pe-section :name name
                   :data (%pe-ub8-vector data)
                   :virtual-size (length data)
                   :characteristics characteristics))

(defun %pe-layout-sections (sections size-of-headers)
  "Assign RVAs and raw file offsets to SECTIONS."
  (let ((next-rva +pe-section-alignment+)
        (next-file size-of-headers))
    (dolist (section sections)
      (let* ((data-size (length (pe-section-data section)))
             (raw-size (if (zerop data-size) 0 (align-up data-size +pe-file-alignment+))))
        (setf (pe-section-virtual-address section) next-rva
              (pe-section-virtual-size section) data-size
              (pe-section-raw-pointer section) (if (zerop raw-size) 0 next-file)
              (pe-section-raw-size section) raw-size)
        (incf next-rva (align-up (max 1 data-size) +pe-section-alignment+))
        (incf next-file raw-size))))
  sections)

(defun %pe-section-by-name (sections name)
  (or (find name sections :key #'pe-section-name :test #'string=)
      (error "Missing PE section ~A" name)))

(define-binary-writer %pe-write-coff-header
    (buf builder section-count size-of-optional-header)
    "Write the COFF file header to BUF."
  (:u16 (pe-builder-machine builder))
  (:u16 section-count)
  (:u32 0) ; timestamp, deterministic
  (:u32 0) ; symbol table pointer
  (:u32 0) ; symbol count
  (:u16 size-of-optional-header)
  (:u16 (logior +pe-file-executable-image+
                +pe-file-large-address-aware+
                (if (pe-builder-dll-p builder) +pe-file-dll+ 0))))

(defun %pe-write-optional-header (buf builder sections directories size-of-headers)
  (let* ((text (%pe-section-by-name sections ".text"))
         (size-of-code (pe-section-raw-size text))
         (initialized-size (loop for section in sections
                                 unless (string= (pe-section-name section) ".text")
                                   sum (pe-section-raw-size section)))
         (size-of-image (align-up
                         (loop for section in sections
                               maximize (+ (pe-section-virtual-address section)
                                           (max 1 (pe-section-virtual-size section))))
                         +pe-section-alignment+)))
    (binary-buffer-write-u16le buf +pe-magic-pe32-plus+)
    (binary-buffer-write-u8 buf 14) ; linker major
    (binary-buffer-write-u8 buf 0)  ; linker minor
    (binary-buffer-write-u32le buf size-of-code)
    (binary-buffer-write-u32le buf initialized-size)
    (binary-buffer-write-u32le buf 0) ; uninitialized size
    (binary-buffer-write-u32le buf (pe-builder-entry-point builder))
    (binary-buffer-write-u32le buf (pe-section-virtual-address text))
    (binary-buffer-write-u64le buf (pe-builder-image-base builder))
    (binary-buffer-write-u32le buf +pe-section-alignment+)
    (binary-buffer-write-u32le buf +pe-file-alignment+)
    (binary-buffer-write-u16le buf 6) ; OS major
    (binary-buffer-write-u16le buf 0)
    (binary-buffer-write-u16le buf 0) ; image version
    (binary-buffer-write-u16le buf 0)
    (binary-buffer-write-u16le buf 6) ; subsystem version
    (binary-buffer-write-u16le buf 0)
    (binary-buffer-write-u32le buf 0) ; win32 version
    (binary-buffer-write-u32le buf size-of-image)
    (binary-buffer-write-u32le buf size-of-headers)
    (binary-buffer-write-u32le buf 0) ; checksum
    (binary-buffer-write-u16le buf (pe-builder-subsystem builder))
    (binary-buffer-write-u16le buf #x8160) ; NX, dynamic base, high entropy VA, terminal aware
    (binary-buffer-write-u64le buf #x100000) ; stack reserve
    (binary-buffer-write-u64le buf #x1000)   ; stack commit
    (binary-buffer-write-u64le buf #x100000) ; heap reserve
    (binary-buffer-write-u64le buf #x1000)   ; heap commit
    (binary-buffer-write-u32le buf 0)        ; loader flags
    (binary-buffer-write-u32le buf +pe-number-of-rva-and-sizes+)
    (dotimes (i +pe-number-of-rva-and-sizes+)
      (let ((directory (aref directories i)))
        (binary-buffer-write-u32le buf (car directory))
        (binary-buffer-write-u32le buf (cdr directory))))))

(define-binary-writer %pe-write-section-header (buf section)
    "Write one 40-byte COFF section header entry to BUF."
  (:raw (%pe-write-fixed-name buf (pe-section-name section)))
  (:u32 (pe-section-virtual-size section))
  (:u32 (pe-section-virtual-address section))
  (:u32 (pe-section-raw-size section))
  (:u32 (pe-section-raw-pointer section))
  (:u32 0) ; relocations pointer
  (:u32 0) ; line numbers pointer
  (:u16 0) ; relocation count
  (:u16 0) ; line number count
  (:u32 (pe-section-characteristics section)))

(defun pe-finalize (builder)
  "Assemble BUILDER into a PE32+ image and return a byte vector."
  (let* ((empty (make-array 0 :element-type '(unsigned-byte 8)))
         (text (%pe-make-section ".text" (pe-builder-text builder)
                                (logior +pe-section-cnt-code+
                                        +pe-section-mem-execute+
                                        +pe-section-mem-read+)))
         (rdata (%pe-make-section ".rdata" (pe-builder-rdata builder)
                                 (logior +pe-section-cnt-initialized-data+
                                         +pe-section-mem-read+)))
         (data (%pe-make-section ".data" (pe-builder-data builder)
                                (logior +pe-section-cnt-initialized-data+
                                        +pe-section-mem-read+
                                        +pe-section-mem-write+)))
         (idata (%pe-make-section ".idata" empty
                                 (logior +pe-section-cnt-initialized-data+
                                         +pe-section-mem-read+
                                         +pe-section-mem-write+)))
         (edata (%pe-make-section ".edata" empty
                                 (logior +pe-section-cnt-initialized-data+
                                         +pe-section-mem-read+)))
         (reloc (%pe-make-section ".reloc" empty
                                 (logior +pe-section-cnt-initialized-data+
                                         +pe-section-mem-read+)))
         (sections (list text rdata data idata edata reloc))
         (dos-stub-size #x80)
         (optional-header-size 240)
         (header-size (+ dos-stub-size 4 20 optional-header-size (* 40 (length sections))))
         (size-of-headers (align-up header-size +pe-file-alignment+)))
    ;; First pass gives stable RVAs for data-directory-bearing sections.
    (%pe-layout-sections sections size-of-headers)
    (multiple-value-bind (idata-bytes import-dir iat-dir)
        (pe-build-import-table (pe-builder-imports builder)
                               (pe-section-virtual-address idata))
      (setf (pe-section-data idata) idata-bytes)
      ;; .edata and .reloc RVAs depend on the final .idata size.
      (%pe-layout-sections sections size-of-headers)
      (multiple-value-bind (edata-bytes export-dir)
          (pe-build-export-table (pe-builder-exports builder)
                                 (pe-section-virtual-address edata)
                                 (if (pe-builder-dll-p builder) "cl-cc.dll" "cl-cc.exe"))
        (setf (pe-section-data edata) edata-bytes)
        (let ((reloc-bytes (pe-build-base-relocations (pe-builder-base-relocations builder)
                                                      (pe-section-virtual-address reloc))))
          (setf (pe-section-data reloc) reloc-bytes)
          ;; Re-layout after generated sections receive their final sizes.
          (%pe-layout-sections sections size-of-headers)
          (let ((directories (%pe-empty-directory-table)))
            (%pe-set-directory directories +pe-directory-import+ (car import-dir) (cdr import-dir))
            (%pe-set-directory directories +pe-directory-iat+ (car iat-dir) (cdr iat-dir))
            (when (plusp (length edata-bytes))
              (%pe-set-directory directories +pe-directory-export+
                                 (car export-dir) (cdr export-dir)))
            (when (plusp (length reloc-bytes))
              (%pe-set-directory directories +pe-directory-base-reloc+
                                 (pe-section-virtual-address reloc)
                                 (length reloc-bytes)))
            (let ((out (elf-make-buffer)))
              (binary-buffer-write-bytes out (pe-build-dos-stub))
              (binary-buffer-write-u32le out +pe-signature+)
              (%pe-write-coff-header out builder (length sections) optional-header-size)
              (%pe-write-optional-header out builder sections directories size-of-headers)
              (dolist (section sections)
                (%pe-write-section-header out section))
              (%pe-pad-to out size-of-headers)
              (dolist (section sections)
                (when (plusp (pe-section-raw-size section))
                  (%pe-pad-to out (pe-section-raw-pointer section))
                  (binary-buffer-write-bytes out (pe-section-data section))
                  (%pe-pad-to out (+ (pe-section-raw-pointer section)
                                     (pe-section-raw-size section)))))
              (binary-buffer-to-array out))))))))

(defun write-pe-file (filename bytes)
  "Write PE image BYTES to FILENAME."
  (with-open-file (out filename
                       :direction :output
                       :element-type '(unsigned-byte 8)
                       :if-exists :supersede
                       :if-does-not-exist :create)
    (write-sequence bytes out))
  filename)

(defun compile-to-pe (code-bytes reloc-entries &key output-file (arch :x86-64)
                                   dll-p (subsystem :console) exports
                                   (rdata-bytes (make-array 0 :element-type '(unsigned-byte 8)))
                                   (data-bytes (make-array 0 :element-type '(unsigned-byte 8))))
  "Create a PE32+ executable or DLL image from CODE-BYTES and RELOC-ENTRIES.

RELOC-ENTRIES may contain .text-relative integer offsets or (OFFSET . SYMBOL)
pairs; PE base relocations use the OFFSET part and are emitted as
IMAGE_REL_BASED_DIR64 entries.  EXPORTS is a list of names exported from .text
at offset zero unless callers add precise RVAs through PE-ADD-EXPORT."
  (let* ((builder (make-pe32+-builder :arch arch :dll-p dll-p :subsystem subsystem))
         (text-rva +pe-section-alignment+))
    (pe-add-text-bytes builder code-bytes)
    (pe-add-rdata-bytes builder rdata-bytes)
    (pe-add-data-bytes builder data-bytes)
    (setf (pe-builder-entry-point builder) text-rva)
    (dolist (reloc reloc-entries)
      (pe-add-base-relocation builder (+ text-rva (if (consp reloc) (car reloc) reloc))))
    (loop for name in exports
          for ordinal from 1
          do (pe-add-export builder name text-rva :ordinal ordinal))
    (let ((bytes (pe-finalize builder)))
      (when output-file
        (write-pe-file output-file bytes))
      bytes)))
