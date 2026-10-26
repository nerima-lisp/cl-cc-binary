(defpackage #:cl-cc/binary/dwarf
            (:use #:cl)
            (:import-from #:cl-cc/binary/buffer
                          #:make-binary-buffer
                          #:binary-buffer-write-u8
                          #:binary-buffer-write-u16le
                          #:binary-buffer-write-u32le
                          #:binary-buffer-write-u64le
                          #:binary-buffer-write-s64le
                          #:binary-buffer-write-bytes
                          #:binary-buffer-write-pad
                          #:binary-buffer-to-array
                          #:with-byte-buffer
                          #:value-out-of-range
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
            (:export #:build-dwarf-debug-sections
                     #:build-dwarf-skeleton-cu
                     #:build-gnu-debuglink-section
                     #:dwarf-crc32
                     #:build-dwarf-eh-frame
                     #:make-dwarf-eh-fde
                     #:dwarf-eh-fde-lsda
                     #:dwarf-eh-fde-personality
                     #:make-dwarf-eh-call-site
                     #:dwarf-eh-call-site-start
                     #:dwarf-eh-call-site-length
                     #:dwarf-eh-call-site-landing-pad
                     #:dwarf-eh-call-site-action
                     #:dwarf-eh-call-site-type
                     #:build-dwarf-eh-lsda
                     #:%emit-dwarf-line-info
                     #:elf64-build-eh-frame
                     #:elf64-build-eh-frame-hdr
                     #:%dwo-write-string
                     #:%dwo-unit
                     #:%dwo-line-table
                     #:+dwarf-dw-lns-copy+
                     #:+dwarf-dw-lns-advance-pc+
                     #:+dwarf-dw-lne-end-sequence+))
