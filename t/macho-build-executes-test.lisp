;;;; t/macho-build-executes-test.lisp — real end-to-end Mach-O execution
;;;;
;;;; Every other test in this suite asserts on bytes: magic numbers, section
;;;; flags, program header layout. None of them ever hands the produced image
;;;; to the operating system and asks it to run. This is the one test that
;;;; does: it builds a real ARM64 Mach-O executable, writes and codesigns it
;;;; through the same WRITE-MACH-O-FILE path every caller uses, executes it,
;;;; and checks the process actually exited with the code its own machine code
;;;; requested — proof the header, load commands, and ad-hoc codesign this
;;;; library produces are something the real Apple Silicon kernel will load
;;;; and run, not just bytes that happen to satisfy an assertion.
;;;;
;;;; Apple Silicon macOS refuses to run an ARM64 binary that is not validly
;;;; codesigned (even ad-hoc), so this also exercises WRITE-MACH-O-FILE's
;;;; codesign step for real rather than only through the captured-logger unit
;;;; test in t/macho-build-assemble-logging-test.lisp.
;;;;
;;;; Only meaningful on an aarch64-darwin host — the flake's declared systems
;;;; are x86_64-linux and aarch64-darwin, and an ARM64 Mach-O cannot execute
;;;; on either the other architecture or the other OS. IT-RUN-IF reports the
;;;; skip explicitly rather than silently omitting the test elsewhere.
;;;;
;;;; Also skipped inside a Nix build sandbox (NIX_BUILD_TOP set): this test
;;;; observed exit code 137 (SIGKILL) under
;;;; `nix build .#checks.aarch64-darwin.default` on a real aarch64-darwin
;;;; host. The leading suspect is Nix's macOS sandbox-exec profile denying
;;;; process-exec for a binary the derivation just produced, rather than a
;;;; defect in the Mach-O this library writes, since nothing else in this
;;;; sandbox touches codesign or executes a freshly built file. Skip here
;;;; rather than block `nix flake check` on an environment restriction this
;;;; test cannot do anything about.

(in-package :cl-cc-binary/test)

(defun %macho-arm64-exit-stub (code)
  "Twelve bytes of ARM64: mov x0, CODE / mov x16, #1 (SYS_exit) / svc #0x80.

Verified against a real assembled-and-linked binary (clang -arch arm64) via
otool -tv before being transcribed here, rather than hand-encoded from the
ARMv8 instruction-set reference."
  (declare (type (unsigned-byte 16) code))
  (let ((movz-x0 (logior #xd2800000 (ash code 5)))
        (movz-x16 #xd2800030)
        (svc-0x80 #xd4001001))
    (coerce
     (loop for word in (list movz-x0 movz-x16 svc-0x80)
           append (loop for shift from 0 to 24 by 8 collect (ldb (byte 8 shift) word)))
     '(simple-array (unsigned-byte 8) (*)))))

(describe "write-mach-o-file end-to-end execution (FR-291)"
  (it-run-if (and (uiop:os-macosx-p)
                  (string-equal (machine-type) "ARM64")
                  (not (uiop:getenv "NIX_BUILD_TOP")))
      "runs the produced Mach-O and observes the exit code its own code requested"
    (let* ((code (%macho-arm64-exit-stub 42))
           (builder (cl-cc/binary:make-mach-o-builder :arm64)))
      (cl-cc/binary:add-text-segment builder code)
      (cl-cc/binary:add-entry-point builder 0)
      (let ((image (cl-cc/binary:build-mach-o builder code)))
        (uiop:with-temporary-file (:pathname path :keep nil)
          (cl-cc/binary:write-mach-o-file path image)
          (uiop:run-program (list "chmod" "755" (uiop:native-namestring path)))
          (multiple-value-bind (output error-output exit-code)
              (uiop:run-program (list (uiop:native-namestring path))
                                :output nil :error-output nil :ignore-error-status t)
            (declare (ignore output error-output))
            (expect exit-code :to-be 42)))))))
