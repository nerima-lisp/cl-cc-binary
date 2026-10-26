(in-package :cl-cc/binary)

(defparameter *macho-codesign-timeout-seconds* 30
  "Timeout in seconds for the external codesign invocation.
codesign has been observed to hang (e.g. on keychain access); timeout and
nonzero exit are reported as errors so callers cannot publish an unsigned file.")

(defvar *binary-logger* nil
  "Optional CL-LOG-KIT logger for structured Mach-O/ELF/PE emission
diagnostics. NIL (the default) keeps this library silent, mirroring
CL-PROCESS-KIT's *PROCESS-LOGGER* convention: bind this to a
LOG-KIT:MAKE-LOGGER instance to observe successful codesign diagnostics.")

(defun %macho-log-codesign-outcome (outcome filename &key condition)
  "Log OUTCOME (:OK, :TIMEOUT, or :ERROR) for the codesign invocation on
FILENAME through *BINARY-LOGGER*. Does nothing for :OK or when
*BINARY-LOGGER* is NIL, so the default (silent) behavior is unchanged."
  (when *binary-logger*
    (ecase outcome
      (:ok nil)
      (:timeout
       (log-kit:log-warn *binary-logger* "codesign timed out; binary left unsigned"
                         :file (namestring filename)
                         :timeout-seconds *macho-codesign-timeout-seconds*))
      (:error
       (log-kit:log-warn *binary-logger* "codesign failed; binary left unsigned"
                         :file (namestring filename)
                         :reason (princ-to-string condition))))))

(defun %macho-codesign-cps (codesign-program filename on-ok on-timeout on-error)
  "Attempt to codesign FILENAME with CODESIGN-PROGRAM, dispatching to a
continuation instead of returning a tri-state outcome.

ON-OK is called with no arguments when codesign exits successfully within
*MACHO-CODESIGN-TIMEOUT-SECONDS*. ON-TIMEOUT is called with no arguments when
it does not. ON-ERROR is called with one argument — a PROCESS-RESULT for a
nonzero exit, or the signaled condition for a launch failure — in every other
case. Exactly one continuation runs, and its return value becomes this
function's return value."
  (handler-case
      (let ((result (process-kit:run (namestring codesign-program)
                                      (list "-s" "-" "-f" (namestring (pathname filename)))
                                      :timeout *macho-codesign-timeout-seconds*)))
        (if (process-kit:process-success-p result)
            (funcall on-ok)
            (funcall on-error result)))
    (process-kit:process-timeout-error () (funcall on-timeout))
    (process-kit:process-error (condition) (funcall on-error condition))))

(defun %macho-codesign-program ()
  "Return the host codesign program pathname, or NIL when unavailable."
  (probe-file "/usr/bin/codesign"))

(defun %macho-write-bytes (filename mach-o-bytes)
  (with-open-file (out filename
                        :direction :output
                        :element-type '(unsigned-byte 8)
                        :if-exists :supersede
                        :if-does-not-exist :create)
    (write-sequence mach-o-bytes out))
  filename)

(defun write-mach-o-file (filename mach-o-bytes &key (codesign t))
  "Write MACH-O-BYTES to FILENAME, replacing it only after signing succeeds."
  (declare (type (or pathname string) filename)
           (type (simple-array (unsigned-byte 8) (*)) mach-o-bytes))
  (let ((target (pathname filename)))
    (if codesign
        (let ((staged (uiop:tmpize-pathname target)))
          (unwind-protect
               (progn
                 (%macho-write-bytes staged mach-o-bytes)
                 (let ((codesign-program (%macho-codesign-program)))
                   (unless codesign-program
                     (error 'macho-codesign-error
                            :filename target
                            :reason "codesign is unavailable"))
                   (%macho-codesign-cps
                    codesign-program staged
                    (lambda ()
                      (uiop:rename-file-overwriting-target staged target)
                      (%macho-log-codesign-outcome :ok target))
                    (lambda ()
                      (error 'macho-codesign-error
                             :filename target
                             :reason "codesign timed out"))
                    (lambda (condition)
                      (error 'macho-codesign-error
                             :filename target
                             :reason condition))))
                 target)
            (when (probe-file staged)
              (ignore-errors (delete-file staged)))))
        (%macho-write-bytes target mach-o-bytes))))
