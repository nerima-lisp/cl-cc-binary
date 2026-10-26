(defpackage #:cl-cc/binary/pe
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
                          #:binary-buffer-to-array
                          #:with-byte-buffer
                          #:align-up
                          #:value-out-of-range
                          #:elf-make-buffer)
            (:export #:pe-section-not-found
                     #:pe-section-not-found-name
                     #:+pe-machine-amd64+
                     #:+pe-machine-arm64+
                     #:+pe-magic-pe32-plus+
                     #:+pe-section-alignment+
                     #:+pe-file-alignment+
                     #:pe-builder
                     #:pe-section
                     #:pe-import
                     #:pe-export
                     #:make-pe32+-builder
                     #:pe-add-text-bytes
                     #:pe-add-rdata-bytes
                     #:pe-add-data-bytes
                     #:pe-add-import
                     #:pe-add-export
                     #:pe-add-base-relocation
                     #:pe-finalize
                     #:compile-to-pe
                     #:write-pe-file
                     #:*pe-x86-64-argument-registers*
                     #:+pe-x86-64-shadow-space-size+
                     #:pe-x86-64-stack-adjustment))
