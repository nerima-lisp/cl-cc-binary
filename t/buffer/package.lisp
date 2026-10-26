;;;; t/buffer/package.lisp — Buffer test package.
(defpackage #:cl-cc/binary/buffer/test
            (:use #:cl #:cl-weave #:cl-cc/binary/buffer)
            (:shadowing-import-from #:cl-weave #:describe)
            (:export #:%read-u16le #:%read-u32le #:%read-u64le #:%read-c-string))

(in-package #:cl-cc/binary/buffer/test)
