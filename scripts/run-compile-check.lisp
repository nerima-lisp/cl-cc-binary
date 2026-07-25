;;;; run-compile-check.lisp
;;;;
;;;; Compile and load cl-cc-binary from the current source tree, then exit
;;;; non-zero on any compile/load error. This is the build gate in
;;;; packages.default; it is deliberately narrower than run-tests.lisp, because
;;;; the shipped system has to build without the test framework present.
;;;;
;;;; cl-log-kit, the sole runtime dependency, is located through
;;;; CL_SOURCE_REGISTRY, which ASDF reads by itself.

(require :asdf)

;; The repository root, one level up from scripts/. See run-tests.lisp: this
;; makes the tree findable without depending on the caller's working directory,
;; and leaves CL_SOURCE_REGISTRY untouched.
(push (uiop:pathname-parent-directory-pathname
       (uiop:pathname-directory-pathname *load-truename*))
      asdf:*central-registry*)

(handler-case
    (progn
      (asdf:load-system "cl-cc-binary")
      (format t "~&PASS cl-cc-binary compile check~%")
      (finish-output))
  (error (e)
    (format t "~&FAIL cl-cc-binary: ~a~%" e)
    (finish-output)
    (uiop:quit 1)))
