;;;; t/macho-build-assemble-logging-test.lisp — *binary-logger* structured diagnostics
;;;;
;;;; %macho-log-codesign-outcome retains structured success diagnostics while
;;;; write-mach-o-file propagates timeout and nonzero-exit failures.

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

(defun %with-replaced-function (name replacement thunk)
  (let ((old (symbol-function name)))
    (unwind-protect
         (progn
           (setf (symbol-function name) replacement)
           (funcall thunk))
      (setf (symbol-function name) old))))

(defun %assert-codesign-failure-preserves-target (mode)
  (uiop:with-temporary-file (:pathname path)
    (with-open-file (out path :direction :output :if-exists :supersede)
      (write-line "original" out))
    (let ((bytes (make-array 1 :element-type '(unsigned-byte 8)
                             :initial-element 0)))
      (%with-replaced-function
       'cl-cc/binary::%macho-codesign-program
       (lambda () #P"/tmp/codesign")
       (lambda ()
         (%with-replaced-function
          'cl-cc/binary::%macho-codesign-cps
          (lambda (program staged on-ok on-timeout on-error)
            (declare (ignore program staged on-ok))
            (ecase mode
              (:error
               (funcall on-error
                        (make-condition 'simple-error
                                        :format-control "injected failure")))
              (:timeout (funcall on-timeout))))
          (lambda ()
            (signals cl-cc/binary:macho-codesign-error
              (cl-cc/binary:write-mach-o-file path bytes :codesign t))))))
      (with-open-file (in path)
        (expect (read-line in) :to-equal "original")))))

(describe "write-mach-o-file codesign failure propagation"
  (it "keeps the existing target when codesign returns a failure"
    (%assert-codesign-failure-preserves-target :error))

  (it "propagates a codesign timeout without replacing the target"
    (%assert-codesign-failure-preserves-target :timeout)))
