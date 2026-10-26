(in-package :cl-cc/binary)

;;; ------------------------------------------------------------
;;; Byte Buffer Helpers
;;; ------------------------------------------------------------

(defun elf-make-buffer ()
  "Create a fresh byte buffer."
  (make-binary-buffer 0))

(defun elf-buf-u8 (buf val)
  "Write 1 byte to buffer."
  (binary-buffer-write-u8 buf (logand val #xff)))

;;; ------------------------------------------------------------
;;; String Table Builder
;;; ------------------------------------------------------------

(defstruct (strtab-builder (:conc-name stb-))
  "Builds an ELF string table section."
  (buf (elf-make-buffer))
  (offset 0)
  (map (make-hash-table :test #'equal)))

(defun make-strtab ()
  "Create a new string table, pre-inserting the empty string at offset 0."
  (let ((st (make-strtab-builder)))
    ;; ELF strtab always starts with a NUL byte (empty string at offset 0)
    (elf-buf-u8 (stb-buf st) 0)
    (setf (stb-offset st) 1)
    (setf (gethash "" (stb-map st)) 0)
    st))

(defun strtab-add (st name)
  "Add NAME to string table, return its byte offset. Deduplicates."
  (or (gethash name (stb-map st))
      (let ((offset (stb-offset st)))
        (setf (gethash name (stb-map st)) offset)
        (loop for c across name do (elf-buf-u8 (stb-buf st) (char-code c)))
        (elf-buf-u8 (stb-buf st) 0)   ; NUL terminator
        (setf (stb-offset st) (+ offset (length name) 1))
        offset)))

(defun strtab-bytes (st)
  "Return the strtab as a byte array."
  (binary-buffer-to-array (stb-buf st)))
