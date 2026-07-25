;;;; run-tests.lisp — load cl-cc-binary/test and run the cl-weave suite.
;;;;
;;;; Invoked as `sbcl --script run-tests.lisp` by checks.default and apps.test.
;;;;
;;;; Sibling systems (cl-weave, cl-log-kit) are found through CL_SOURCE_REGISTRY,
;;;; which the flake sets and which ASDF reads by itself. There is deliberately
;;;; no cl-cc-binary-specific environment variable: the previous
;;;; CL_CC_BINARY_CL_WEAVE_ROOT / CL_CC_BINARY_CL_LOG_KIT_ROOT pair had to be
;;;; kept in step across the flake, this script and the compile check, and every
;;;; new dependency meant inventing a third one.

(require :asdf)

;; Make this checkout findable regardless of the caller's working directory, so
;; `sbcl --script run-tests.lisp` works from a plain clone too.
;; *central-registry* is consulted independently of CL_SOURCE_REGISTRY, so this
;; adds the tree without discarding what the environment provides.
(push (uiop:pathname-directory-pathname *load-truename*) asdf:*central-registry*)

(handler-case (asdf:load-system "cl-cc-binary/test")
  (error (e)
    (format t "~&FAIL load: ~a~%" e)
    (finish-output)
    (uiop:quit 1)))

(if (uiop:symbol-call :cl-weave :run-all :reporter :spec :pass-with-no-tests nil)
    (progn (format t "~&RESULT: ALL PASS~%")
           (finish-output))
    (progn (format t "~&RESULT: FAIL~%")
           (finish-output)
           (uiop:quit 1)))
