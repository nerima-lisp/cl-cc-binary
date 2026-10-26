;;;; t/helpers-byte-reader.lisp — shared little-endian byte-reading helpers
;;;;
;;;; Read raw bytes back out of the ELF images the test suite builds, so a
;;;; test can assert on the actual serialized layout rather than trusting the
;;;; builder's own bookkeeping. Loaded first so every test file that needs
;;;; them can rely on load order rather than redeclaring them.

(in-package :cl-cc-binary/test)

(defun %elf-u16le (bytes offset)
  (+ (aref bytes offset)
     (ash (aref bytes (1+ offset)) 8)))

(defun %elf-u32le (bytes offset)
  (+ (aref bytes offset)
     (ash (aref bytes (1+ offset)) 8)
     (ash (aref bytes (+ offset 2)) 16)
     (ash (aref bytes (+ offset 3)) 24)))

(defun %elf-u64le (bytes offset)
  (loop for i below 8
        sum (ash (aref bytes (+ offset i)) (* 8 i))))

(defun %elf-c-string (bytes offset)
  (with-output-to-string (out)
    (loop for i from offset below (length bytes)
          for byte = (aref bytes i)
          until (zerop byte)
          do (write-char (code-char byte) out))))

(defun %elf-has-phdr-type-p (bytes type)
  "True if any ELF64 program header in BYTES has the given p_type TYPE."
  (let ((phoff (%elf-u64le bytes 32))
        (phentsize (%elf-u16le bytes 54))
        (phnum (%elf-u16le bytes 56)))
    (loop for i below phnum
          thereis (= (%elf-u32le bytes (+ phoff (* i phentsize))) type))))

(defun %elf-section-flags-by-name (bytes)
  (let* ((shoff (%elf-u64le bytes 40))
         (shentsize (%elf-u16le bytes 58))
         (shnum (%elf-u16le bytes 60))
         (shstrndx (%elf-u16le bytes 62))
         (shstr-header (+ shoff (* shstrndx shentsize)))
         (shstr-offset (%elf-u64le bytes (+ shstr-header 24)))
         (result (make-hash-table :test #'equal)))
    (dotimes (i shnum result)
      (let* ((header (+ shoff (* i shentsize)))
             (name-offset (%elf-u32le bytes header))
             (name (%elf-c-string bytes (+ shstr-offset name-offset)))
             (flags (%elf-u64le bytes (+ header 8))))
        (setf (gethash name result) flags)))))
