;;;; run-coverage.lisp — load cl-cc-binary/test under SB-COVER, run the
;;;; cl-weave suite, and write an HTML coverage report.
;;;;
;;;; Invoked as `sbcl --script run-coverage.lisp <report-dir>` by
;;;; packages.coverage. Mirrors run-tests.lisp's loading, with
;;;; SB-COVER:STORE-COVERAGE-DATA declaimed before the forced recompile so
;;;; every form in cl-cc-binary and cl-cc-binary/test is instrumented.
;;;;
;;;; DECLAIM's effect is always global (it calls PROCLAIM), so it is written
;;;; at top level rather than nested inside the REPORT-DIR check below, where
;;;; its placement would misleadingly suggest it were scoped to that form.

(require :asdf)
(require :sb-cover)

(push (uiop:pathname-directory-pathname *load-truename*) asdf:*central-registry*)

(declaim (optimize sb-cover:store-coverage-data))

(defparameter *report-dir*
  ;; SB-COVER:REPORT parses its argument as a pathname and requires it to
  ;; designate a directory, which in Lisp pathname syntax means a trailing
  ;; slash; without one a string like ".../cl-cc-binary-coverage-0.1.0"
  ;; parses as a file named that, not a directory.
  (let ((dir (or (second sb-ext:*posix-argv*)
                 (error "usage: sbcl --script run-coverage.lisp <report-dir>"))))
    (if (char= (char dir (1- (length dir))) #\/)
        dir
        (concatenate 'string dir "/"))))

(handler-case (asdf:load-system "cl-cc-binary/test" :force t)
  (error (e)
    (format t "~&FAIL load: ~a~%" e)
    (finish-output)
    (uiop:quit 1)))

(uiop:symbol-call :cl-weave :run-all :reporter :spec :pass-with-no-tests nil)

(sb-cover:report *report-dir*)
(format t "~&Coverage report written to ~a~%" *report-dir*)
(finish-output)
