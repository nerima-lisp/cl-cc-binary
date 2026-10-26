(in-package :cl-cc/binary/elf/test)

(defun %elf-has-phdr-type-p (bytes type)
  "True if any ELF64 program header in BYTES has the given p_type TYPE."
  (let ((phoff (%read-u64le bytes 32))
        (phentsize (%read-u16le bytes 54))
        (phnum (%read-u16le bytes 56)))
    (loop for i below phnum
          thereis (= (%read-u32le bytes (+ phoff (* i phentsize))) type))))

(defun %elf-section-flags-by-name (bytes)
  (let* ((shoff (%read-u64le bytes 40))
         (shentsize (%read-u16le bytes 58))
         (shnum (%read-u16le bytes 60))
         (shstrndx (%read-u16le bytes 62))
         (shstr-header (+ shoff (* shstrndx shentsize)))
         (shstr-offset (%read-u64le bytes (+ shstr-header 24)))
         (result (make-hash-table :test (function equal))))
    (dotimes (i shnum result)
      (let* ((header (+ shoff (* i shentsize)))
             (name-offset (%read-u32le bytes header))
             (name (%read-c-string bytes (+ shstr-offset name-offset)))
             (flags (%read-u64le bytes (+ header 8))))
        (setf (gethash name result) flags)))))
