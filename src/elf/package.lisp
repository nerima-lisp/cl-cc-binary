(defpackage #:cl-cc/binary/elf
            (:use #:cl)
            (:import-from #:cl-cc/binary/buffer
                          #:cl-cc-binary-error
                          #:define-binary-writer
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
                          #:align-up
                          #:value-out-of-range
                          #:elf-make-buffer
                          #:compress-code-bytes-cps
                          #:elf-buf-u8
                          #:elf64-write-uleb128
                          #:elf64-write-sleb128
                          #:elf64-pad-to-align
                          #:make-strtab
                          #:strtab-add
                          #:strtab-bytes
                          #:stb-buf
                          #:stb-offset
                          #:stb-map)
            (:import-from #:cl-cc/binary/dwarf
                          #:build-dwarf-debug-sections
                          #:%emit-dwarf-line-info
                          #:elf64-build-eh-frame
                          #:elf64-build-eh-frame-hdr
                          #:%dwo-write-string
                          #:%dwo-unit
                          #:%dwo-line-table)
            (:export #:elf-wx-violation
                     #:elf-wx-violation-segment
                     #:compile-to-elf64
                     #:elf64-add-rodata-bytes
                     #:elf64-add-rodata-string
                     #:elf64-add-got-entry
                     #:elf64-add-plt-stub
                     #:elf64-verify-wx
                     #:build-dwo-file
                     #:compile-to-elf64-exec
                     #:make-elf64-executable
                     #:elf64-add-load-segment
                     #:elf64-add-gnu-stack-segment
                     #:elf64-add-gnu-relro-segment
                     #:write-elf64-file))
