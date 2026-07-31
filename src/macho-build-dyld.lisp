(in-package :cl-cc/binary)

(defun %macho-build-bind-opcodes (symbol-names)
  "Build a minimal dyld bind opcode stream for external SYMBOL-NAMES."
  (let ((buf (elf-make-buffer)))
    (dolist (name symbol-names)
      ;; BIND_OPCODE_SET_DYLIB_ORDINAL_IMM | 1 (libSystem)
      (binary-buffer-write-u8 buf #x11)
      ;; BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM | 0, followed by C string.
      (binary-buffer-write-u8 buf #x40)
      (loop for c across name
            do (binary-buffer-write-u8 buf (char-code c)))
      (binary-buffer-write-u8 buf 0)
      ;; BIND_OPCODE_SET_TYPE_IMM | BIND_TYPE_POINTER.
      (binary-buffer-write-u8 buf #x51)
      ;; BIND_OPCODE_DO_BIND.  Segment/offset binding is supplied by relocation
      ;; entries; this stream records the external symbol resolution intent.
      (binary-buffer-write-u8 buf #x90))
    (when symbol-names
      ;; BIND_OPCODE_DONE.
      (binary-buffer-write-u8 buf 0))
    (binary-buffer-to-array buf)))

(defun %write-macho-dylib-command (buffer &optional (path "/usr/lib/libSystem.B.dylib"))
  "Emit LC_LOAD_DYLIB for PATH."
  (serialize-dylib-command (make-dylib-command :name path) buffer))
