;;;; t/elf-emit-executable-wxorx-test.lisp — FR-694 ELF W^X tests

(in-package :cl-cc-binary/test)

(describe "FR-694 ELF W^X enforcement"

  (it "includes PT_GNU_STACK with PF_R|PF_W and no PF_X in executables"
    (let* ((bytes (cl-cc/binary::compile-to-elf64-exec #(195) nil))
           (phoff (%elf-u64le bytes 32))
           (phentsize (%elf-u16le bytes 54))
           (phnum (%elf-u16le bytes 56))
           (gnu-stack-flags nil))
      (dotimes (i phnum)
        (let* ((header (+ phoff (* i phentsize)))
               (type (%elf-u32le bytes header))
               (flags (%elf-u32le bytes (+ header 4))))
          (when (= type cl-cc/binary::+pt-gnu-stack+)
            (setf gnu-stack-flags flags))))
      (expect gnu-stack-flags :to-be-truthy)
      (expect gnu-stack-flags :to-be (logior cl-cc/binary::+pf-r+ cl-cc/binary::+pf-w+))
      (expect (zerop (logand gnu-stack-flags cl-cc/binary::+pf-x+)))))

  (it "keeps .text RX while .data/.bss stay RW and never executable"
    (let* ((builder (cl-cc/binary::make-elf64-executable))
           (text-flags nil)
           (data-flags nil)
           (bss-flags nil))
      (cl-cc/binary::elf64-add-text-bytes builder #(195))
      (cl-cc/binary::elf64-add-data-bytes builder #(1 2 3 4))
      (cl-cc/binary::elf64-add-bss builder 16)
      (let ((flags (%elf-section-flags-by-name (cl-cc/binary::elf64-finalize builder))))
        (setf text-flags (gethash ".text" flags)
              data-flags (gethash ".data" flags)
              bss-flags (gethash ".bss" flags)))
      (expect text-flags :to-be (logior cl-cc/binary::+shf-alloc+ cl-cc/binary::+shf-execinstr+))
      (expect data-flags :to-be (logior cl-cc/binary::+shf-alloc+ cl-cc/binary::+shf-write+))
      (expect bss-flags :to-be (logior cl-cc/binary::+shf-alloc+ cl-cc/binary::+shf-write+))
      (expect (zerop (logand text-flags cl-cc/binary::+shf-write+)))
      (expect (zerop (logand data-flags cl-cc/binary::+shf-execinstr+)))
      (expect (zerop (logand bss-flags cl-cc/binary::+shf-execinstr+)))))

  (it "elf64-verify-wx signals elf-wx-violation for a PT_LOAD segment with both PF_W and PF_X"
    (let ((segments (list (list cl-cc/binary::+pt-load+
                                (logior cl-cc/binary::+pf-w+ cl-cc/binary::+pf-x+)
                                0 0 0 0 0 #x1000))))
      (expect (lambda () (cl-cc/binary::elf64-verify-wx segments))
              :to-throw 'cl-cc/binary:elf-wx-violation)))

  (it "elf64-verify-wx returns true for PT_LOAD segments that are not both writable and executable"
    (let ((segments (list (list cl-cc/binary::+pt-load+ cl-cc/binary::+pf-r+ 0 0 0 0 0 #x1000)
                          (list cl-cc/binary::+pt-load+
                                (logior cl-cc/binary::+pf-r+ cl-cc/binary::+pf-w+)
                                0 0 0 0 0 #x1000))))
      (expect (cl-cc/binary::elf64-verify-wx segments) :to-be-truthy))))
