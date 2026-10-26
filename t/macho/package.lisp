(defpackage #:cl-cc/binary/macho/test
            (:use #:cl #:cl-weave #:cl-cc/binary/macho)
            (:shadowing-import-from #:cl-weave #:describe)
            (:import-from #:cl-cc/binary/buffer/test #:%read-u16le #:%read-u32le #:%read-u64le))

(in-package #:cl-cc/binary/macho/test)
