(asdf:defsystem "cl-cc-binary-test"
  :description "Tests for cl-cc-binary (cl-weave)."
  :version "0.1.0"
  :author "takeokunn"
  :license "MIT"
  :homepage "https://github.com/nerima-lisp/cl-cc-binary"
  :depends-on ("cl-cc-binary" "cl-weave" "cl-log-kit")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "binary-buffer-tests")
               (:file "binary-constpool-tests")
               (:file "binary-wxorx-tests")
               (:file "architecture-tests")
               (:file "got-plt-tests")
               (:file "macho-fat-tests")
               (:file "macho-build-tests")
               (:file "binary-logger-tests")
               (:file "patchable-entry-tests"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-weave :run-all :reporter :spec :pass-with-no-tests nil)
               (error "cl-cc-binary tests failed"))))
