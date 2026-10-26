(defpackage #:cl-cc/binary/wasm
            (:use #:cl)
            (:import-from #:cl-cc/binary/buffer
                          #:make-binary-buffer
                          #:binary-buffer-write-u8
                          #:binary-buffer-to-array
                          #:with-byte-buffer)
            (:export #:encode-uleb128 #:encode-sleb128 #:portable-double-float-bits))
