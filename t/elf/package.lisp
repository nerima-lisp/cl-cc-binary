(defpackage #:cl-cc/binary/elf/test
            (:use #:cl #:cl-weave #:cl-cc/binary/elf)
            (:shadowing-import-from #:cl-weave #:describe)
            (:import-from #:cl-cc/binary/buffer/test
                          #:%read-u16le
                          #:%read-u32le
                          #:%read-u64le
                          #:%read-c-string))

(in-package #:cl-cc/binary/elf/test)
