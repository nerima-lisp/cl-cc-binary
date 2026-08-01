;;;; t/elf-compile-executes-test.lisp — real end-to-end ELF64 execution
;;;;
;;;; Every other ELF test in this suite asserts on bytes: magic numbers,
;;;; section flags, program header layout. None ever handed a produced image
;;;; to the operating system and asked it to run. This test builds a real
;;;; ELF64 executable via COMPILE-TO-ELF64-EXEC — the same one-shot entry
;;;; point the README's Quick Start demonstrates — and executes it, checking
;;;; the process exits with the code its own machine code requested.
;;;;
;;;; Only meaningful on a native Linux host: this flake declares
;;;; x86_64-linux as one of its two verified systems (see
;;;; docs/src/project/development.md), so CI's x86_64-linux leg exercises this
;;;; directly with no extra dependency. IT-RUN-IF reports the skip
;;;; explicitly on any other host rather than silently omitting the test.
;;;;
;;;; Both architectures this package supports (:x86-64 and :arm64) were
;;;; manually verified end-to-end during development by cross-building each
;;;; ELF here and running it inside a real Linux container (Docker Desktop
;;;; on an aarch64-darwin host, native aarch64 and QEMU-emulated x86_64),
;;;; both exiting with the code their machine code requested. That path is
;;;; not automated here: it needs a container runtime and a network-fetched
;;;; base image, neither of which belongs in this suite's dependency set —
;;;; see [[nerima_lisp_shared_env_load]] in the developer's own notes for
;;;; why a Docker-based fallback was deliberately left manual.
;;;;
;;;; Also skipped inside a Nix build sandbox (NIX_BUILD_TOP set): matching
;;;; t/macho-build-executes-test.lisp's SIGKILL finding for a self-built
;;;; Mach-O, Nix's sandbox is expected to deny process-exec for a binary
;;;; the derivation just produced on Linux too.

(in-package :cl-cc-binary/test)

(defun %elf-exit-stub-x86-64 (code)
  "mov edi, CODE / mov eax, 60 (SYS_exit) / syscall — the same shape as the
README Quick Start's example machine code."
  (declare (type (unsigned-byte 32) code))
  (coerce
   (append (list #xbf)
           (loop for shift from 0 to 24 by 8 collect (ldb (byte 8 shift) code))
           (list #xb8 #x3c #x00 #x00 #x00)
           (list #x0f #x05))
   '(simple-array (unsigned-byte 8) (*))))

(defun %elf-exit-stub-arm64 (code)
  "mov x0, CODE / mov x8, #93 (Linux __NR_exit) / svc #0.

Verified against a real assembled-and-linked binary (gcc -nostdlib -static)
via objdump -d inside an aarch64 Linux container before being transcribed
here, rather than hand-encoded from the ARMv8 instruction-set reference."
  (declare (type (unsigned-byte 16) code))
  (let ((movz-x0 (logior #xd2800000 (ash code 5)))
        (movz-x8-93 #xd2800ba8)
        (svc-0 #xd4000001))
    (coerce
     (loop for word in (list movz-x0 movz-x8-93 svc-0)
           append (loop for shift from 0 to 24 by 8 collect (ldb (byte 8 shift) word)))
     '(simple-array (unsigned-byte 8) (*)))))

(describe "compile-to-elf64-exec end-to-end execution"
  (it-run-if (and (uiop:os-unix-p)
                  (not (uiop:os-macosx-p))
                  (not (uiop:getenv "NIX_BUILD_TOP")))
      "runs the produced ELF64 executable and observes the exit code its own code requested"
    (let* ((arch (if (string-equal (machine-type) "ARM64") :arm64 :x86-64))
           (code (ecase arch
                   (:arm64 (%elf-exit-stub-arm64 42))
                   (:x86-64 (%elf-exit-stub-x86-64 42))))
           (bytes (cl-cc/binary:compile-to-elf64-exec code nil :arch arch :type :exec)))
      (uiop:with-temporary-file (:pathname path :keep nil)
        (with-open-file (out path :direction :output :if-exists :supersede
                                  :element-type '(unsigned-byte 8))
          (write-sequence bytes out))
        (uiop:run-program (list "chmod" "755" (uiop:native-namestring path)))
        (multiple-value-bind (output error-output exit-code)
            (uiop:run-program (list (uiop:native-namestring path))
                              :output nil :error-output nil :ignore-error-status t)
          (declare (ignore output error-output))
          (expect exit-code :to-be 42))))))
