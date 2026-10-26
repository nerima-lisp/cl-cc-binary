;;;; t/pe-finalize-test.lisp — PE32+ image assembly
;;;;
;;;; pe-finalize had no test coverage at all before this file: every
;;;; assertion below also exercises the %pe-with-import-table/
;;;; %pe-with-export-table/%pe-with-base-relocations CPS stages, since a
;;;; default pe32+-builder already carries a kernel32.dll import and this
;;;; file adds an export and a relocation.

(in-package :cl-cc-binary/test)

(defun %pe-lfanew (bytes)
  (%elf-u32le bytes 60))

(defun %pe-signature-offset (bytes)
  (%pe-lfanew bytes))

(defun %pe-coff-offset (bytes)
  (+ (%pe-signature-offset bytes) 4))

(defun %pe-optional-header-offset (bytes)
  (+ (%pe-coff-offset bytes) 20))

(describe "compile-to-pe image structure"
  (it "starts with the MZ DOS signature"
    (let ((bytes (cl-cc/binary::compile-to-pe #(195) nil)))
      (expect (%elf-u16le bytes 0) :to-be cl-cc/binary::+pe-dos-signature+)))

  (it "has the PE signature at e_lfanew"
    (let ((bytes (cl-cc/binary::compile-to-pe #(195) nil)))
      (expect (%elf-u32le bytes (%pe-signature-offset bytes)) :to-be cl-cc/binary::+pe-signature+)))

  (it "writes the x86-64 machine type in the COFF header by default"
    (let ((bytes (cl-cc/binary::compile-to-pe #(195) nil)))
      (expect (%elf-u16le bytes (%pe-coff-offset bytes)) :to-be cl-cc/binary::+pe-machine-amd64+)))

  (it "writes the arm64 machine type when :arch :arm64 is requested"
    (let ((bytes (cl-cc/binary::compile-to-pe #(195) nil :arch :arm64)))
      (expect (%elf-u16le bytes (%pe-coff-offset bytes)) :to-be cl-cc/binary::+pe-machine-arm64+)))

  (it "sets IMAGE_FILE_DLL in the COFF characteristics for a DLL"
    (let* ((bytes (cl-cc/binary::compile-to-pe #(195) nil :dll-p t))
           (characteristics (%elf-u16le bytes (+ (%pe-coff-offset bytes) 18))))
      (expect (logtest characteristics cl-cc/binary::+pe-file-dll+) :to-be-truthy)))

  (it "does not set IMAGE_FILE_DLL for a plain executable"
    (let* ((bytes (cl-cc/binary::compile-to-pe #(195) nil))
           (characteristics (%elf-u16le bytes (+ (%pe-coff-offset bytes) 18))))
      (expect (logtest characteristics cl-cc/binary::+pe-file-dll+) :to-be-falsy)))

  (it "writes the PE32+ magic in the optional header"
    (let ((bytes (cl-cc/binary::compile-to-pe #(195) nil)))
      (expect (%elf-u16le bytes (%pe-optional-header-offset bytes))
              :to-be cl-cc/binary::+pe-magic-pe32-plus+)))

  (it "records a nonzero import directory (the default kernel32.dll import)"
    (let* ((bytes (cl-cc/binary::compile-to-pe #(195) nil))
           (directories-offset (+ (%pe-optional-header-offset bytes) 112))
           (import-dir-offset (+ directories-offset (* 8 cl-cc/binary::+pe-directory-import+)))
           (import-size (%elf-u32le bytes (+ import-dir-offset 4))))
      (expect (plusp import-size) :to-be-truthy)))

  (it "records a nonzero export directory once an export is added"
    (let* ((builder (cl-cc/binary::make-pe32+-builder))
           (directories-offset nil))
      (cl-cc/binary::pe-add-text-bytes builder #(195))
      (cl-cc/binary::pe-add-export builder "entry" 0)
      (let* ((bytes (cl-cc/binary::pe-finalize builder))
             (export-dir-offset (progn
                                   (setf directories-offset (+ (%pe-optional-header-offset bytes) 112))
                                   (+ directories-offset (* 8 cl-cc/binary::+pe-directory-export+))))
             (export-size (%elf-u32le bytes (+ export-dir-offset 4))))
        (expect (plusp export-size) :to-be-truthy))))

  (it "records a nonzero base-relocation directory once a relocation is added"
    (let* ((builder (cl-cc/binary::make-pe32+-builder)))
      (cl-cc/binary::pe-add-text-bytes builder #(195))
      (cl-cc/binary::pe-add-base-relocation builder 0)
      (let* ((bytes (cl-cc/binary::pe-finalize builder))
             (directories-offset (+ (%pe-optional-header-offset bytes) 112))
             (reloc-dir-offset (+ directories-offset (* 8 cl-cc/binary::+pe-directory-base-reloc+)))
             (reloc-size (%elf-u32le bytes (+ reloc-dir-offset 4))))
        (expect (plusp reloc-size) :to-be-truthy)))))
