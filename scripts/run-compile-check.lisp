;;;; run-compile-check.lisp
;;;;
;;;; Compile and load :cl-cc-binary from the current source tree, then exit
;;;; non-zero on any compile/load error. This is the build and CI gate.
;;;; :cl-cc-binary's only runtime dependency is cl-log-kit (optional
;;;; structured diagnostics, silent unless a caller binds *BINARY-LOGGER*),
;;;; located via CL_CC_BINARY_CL_LOG_KIT_ROOT.

(require :asdf)

(let ((log-kit (uiop:getenv "CL_CC_BINARY_CL_LOG_KIT_ROOT")))
  (unless log-kit
    (format t "~&FAIL: CL_CC_BINARY_CL_LOG_KIT_ROOT is not set~%") (finish-output)
    (sb-ext:exit :code 1))
  (asdf:initialize-source-registry
   (list :source-registry
         (list :tree (truename "."))
         (list :tree (truename log-kit))
         :inherit-configuration)))

(handler-case
    (progn
      (asdf:load-system :cl-cc-binary)
      (format t "~&PASS cl-cc-binary compile check~%")
      (finish-output))
  (error (e)
    (format t "~&FAIL cl-cc-binary: ~a~%" e)
    (finish-output)
    (sb-ext:exit :code 1)))
