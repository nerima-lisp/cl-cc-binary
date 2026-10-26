(defpackage #:cl-cc/binary/linking
            (:use #:cl)
            (:import-from #:cl-cc/binary/buffer
                          #:cl-cc-binary-error
                          #:with-output-to-vector
                          #:with-byte-buffer
                          #:elf-make-buffer
                          #:binary-buffer-write-bytes
                          #:binary-buffer-write-u32le
                          #:binary-buffer-write-u64le
                          #:binary-buffer-write-s64le
                          #:binary-buffer-to-array)
            (:export #:patchable-entry-overflow
                     #:patchable-entry-overflow-size
                     #:patchable-entry-overflow-reserved
                     #:*icf-enabled*
                     #:icf-merge-identical-functions))
