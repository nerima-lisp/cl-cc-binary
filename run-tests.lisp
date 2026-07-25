;;;; run-tests.lisp — load :cl-cc-binary-test and run the cl-weave suite.
(require :asdf)
(let ((weave (uiop:getenv "CL_CC_BINARY_CL_WEAVE_ROOT"))
      (log-kit (uiop:getenv "CL_CC_BINARY_CL_LOG_KIT_ROOT")))
  (unless weave
    (format t "~&FAIL: CL_CC_BINARY_CL_WEAVE_ROOT is not set~%") (finish-output)
    (sb-ext:exit :code 1))
  (unless log-kit
    (format t "~&FAIL: CL_CC_BINARY_CL_LOG_KIT_ROOT is not set~%") (finish-output)
    (sb-ext:exit :code 1))
  (asdf:initialize-source-registry
   (list :source-registry
         (list :tree (truename "."))
         (list :tree (truename weave))
         (list :tree (truename log-kit))
         :inherit-configuration)))
(handler-case (asdf:load-system :cl-cc-binary-test)
  (error (e) (format t "~&FAIL load: ~a~%" e) (finish-output) (sb-ext:exit :code 1)))
(if (funcall (find-symbol "RUN-ALL" :cl-weave) :reporter :spec :pass-with-no-tests nil)
    (progn (format t "~&RESULT: ALL PASS~%") (finish-output))
    (progn (format t "~&RESULT: FAIL~%") (finish-output) (sb-ext:exit :code 1)))
