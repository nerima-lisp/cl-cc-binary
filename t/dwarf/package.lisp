(defpackage #:cl-cc/binary/dwarf/test
            (:use #:cl #:cl-weave #:cl-cc/binary/dwarf)
            (:shadowing-import-from #:cl-weave #:describe)
            (:import-from #:cl-cc/binary/buffer #:with-byte-buffer)
            (:import-from #:cl-cc/binary/buffer/test #:%read-u32le))

(in-package #:cl-cc/binary/dwarf/test)
