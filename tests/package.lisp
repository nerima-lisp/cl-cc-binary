;;;; tests/package.lisp — cl-cc-binary test package.

(defpackage :cl-cc-binary/test
  (:use :cl :cl-weave :cl-cc/binary)
  (:shadowing-import-from :cl-weave #:describe))

(in-package :cl-cc-binary/test)
