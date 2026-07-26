;;;; t/macho-build-assemble-logging-test.lisp — *binary-logger* structured diagnostics
;;;;
;;;; write-mach-o-file's codesign step is the only currently-silent failure
;;;; path in this library, and driving it end-to-end needs a real macOS
;;;; /usr/bin/codesign plus a forced timeout or failure, neither of which is
;;;; deterministic across CI hosts. %macho-log-codesign-outcome factors the
;;;; "what to log for a given outcome" decision out of that untestable
;;;; process invocation, so it is exercised directly here with a captured
;;;; cl-log-kit function-handler instead.

(in-package :cl-cc-binary/test)

(defun %captured-log-records (thunk)
  "Run THUNK with cl-cc/binary:*binary-logger* bound to a logger whose
records are captured into a list, and return that list (oldest first)."
  (let ((captured nil))
    (let ((cl-cc/binary:*binary-logger*
            (log-kit:make-logger
             :handler (log-kit:make-function-handler
                       (lambda (record) (push record captured))))))
      (funcall thunk))
    (nreverse captured)))

(describe "*binary-logger* structured diagnostics"

  (it "defaults to nil, keeping the library silent"
    (expect cl-cc/binary:*binary-logger* :to-be-null))

  (it "logs nothing for :ok"
    (let ((records (%captured-log-records
                    (lambda () (cl-cc/binary::%macho-log-codesign-outcome :ok "/tmp/example.bin")))))
      (expect records :to-equal nil)))

  (it "logs nothing when no logger is bound"
    (let ((cl-cc/binary:*binary-logger* nil))
      (expect (cl-cc/binary::%macho-log-codesign-outcome :timeout "/tmp/example.bin")
              :to-be-null)))

  (it "logs a timeout warning naming the file and configured timeout"
    (let ((records (%captured-log-records
                    (lambda () (cl-cc/binary::%macho-log-codesign-outcome
                                :timeout "/tmp/example.bin")))))
      (expect (length records) :to-be 1)
      (expect (log-kit:log-record-message (first records)) :to-match "codesign timed out")
      (expect (log-kit:log-record-fields (first records))
              :to-have-property :file "/tmp/example.bin")))

  (it "logs an error warning with the condition's printed reason"
    (let ((records (%captured-log-records
                    (lambda () (cl-cc/binary::%macho-log-codesign-outcome
                                :error "/tmp/example.bin"
                                :condition (make-condition 'simple-error
                                                           :format-control "boom"))))))
      (expect (length records) :to-be 1)
      (expect (log-kit:log-record-message (first records)) :to-match "codesign failed")
      (expect (log-kit:log-record-fields (first records))
              :to-have-property :reason "boom"))))
