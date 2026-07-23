;;;; run-compile-check.lisp
;;;;
;;;; Compile and load :cl-cc-binary from the current source tree, then exit
;;;; non-zero on any compile/load error. This is the build and CI gate for a
;;;; dependency-free leaf system, so no external source registry is required
;;;; beyond the project root registered below.

(require :asdf)

(asdf:initialize-source-registry
 (list :source-registry
       (list :tree (truename "."))
       :inherit-configuration))

(handler-case
    (progn
      (asdf:load-system :cl-cc-binary)
      (format t "~&PASS cl-cc-binary compile check~%")
      (finish-output))
  (error (e)
    (format t "~&FAIL cl-cc-binary: ~a~%" e)
    (finish-output)
    (sb-ext:exit :code 1)))
