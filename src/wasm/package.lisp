(defpackage #:cl-cc/binary/wasm
  (:use #:cl)
  (:import-from #:cl-cc/binary/buffer
                #:make-binary-buffer
                #:binary-buffer-write-u8
                #:binary-buffer-write-bytes
                #:binary-buffer-to-array
                #:with-byte-buffer)
  (:export #:encode-uleb128
           #:encode-sleb128
           #:portable-double-float-bits
           #:encode-wasm-section
           #:encode-wasm-custom-section
           #:encode-wasm-module
           #:encode-wasm-type-section
           #:encode-wasm-function-section
           #:encode-wasm-export-section
           #:encode-wasm-code-section
           #:encode-wasm-name-section))
