(defpackage #:cl-cc/binary/pe/test
            (:use #:cl #:cl-weave #:cl-cc/binary/pe)
            (:shadowing-import-from #:cl-weave #:describe)
            (:import-from #:cl-cc/binary/buffer/test #:%read-u16le #:%read-u32le))

(in-package #:cl-cc/binary/pe/test)
