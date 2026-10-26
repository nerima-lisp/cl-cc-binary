;;;; packages/binary/src/package.lisp - Binary Format Package Definition
;;;
;;; Package for Mach-O binary format support in cl-cc.
(defpackage #:cl-cc/binary/buffer
            (:use #:cl)
            (:export #:cl-cc-binary-error
                     #:value-out-of-range
                     #:value-out-of-range-operation
                     #:value-out-of-range-value
                     #:value-out-of-range-low
                     #:value-out-of-range-high
                     #:make-binary-buffer
                     #:binary-buffer-write-u8
                     #:binary-buffer-write-u16le
                     #:binary-buffer-write-u32le
                     #:binary-buffer-write-u64le
                     #:binary-buffer-write-s64le
                     #:binary-buffer-write-bytes
                     #:binary-buffer-write-pad
                     #:binary-buffer-pad-and-write
                     #:binary-buffer-to-array
                     #:with-byte-buffer
                     #:make-byte-buffer
                     #:byte-buffer
                     #:buffer-write-byte
                     #:buffer-write-bytes
                     #:buffer-get-bytes
                     #:buffer-pad-to
                     #:align-up
                     #:string-to-ascii-bytes
                     #:serialize-uint32-le
                     #:serialize-uint64-le
                     #:serialize-string-16
                     #:serialize-bytes
                     #:with-output-to-vector
                     #:define-binary-struct
                     #:define-binary-writer
                     #:elf-make-buffer
                     #:elf-buf-u8
                     #:elf64-write-uleb128
                     #:elf64-write-sleb128
                     #:elf64-pad-to-align
                     #:strtab-builder
                     #:stb-buf
                     #:stb-offset
                     #:stb-map
                     #:make-strtab
                     #:strtab-add
                     #:strtab-bytes
                     #:compress-code-bytes-cps))
