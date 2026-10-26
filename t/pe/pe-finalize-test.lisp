;;;; t/pe-finalize-test.lisp — PE32+ image assembly
;;;;
;;;; pe-finalize had no test coverage at all before this file: every
;;;; assertion below also exercises the %pe-with-import-table/
;;;; %pe-with-export-table/%pe-with-base-relocations CPS stages, since a
;;;; default pe32+-builder already carries a kernel32.dll import and this
;;;; file adds an export and a relocation.

(in-package #:cl-cc/binary/pe/test)

(defun %pe-lfanew (bytes)
  (%read-u32le bytes 60))

(defun %pe-signature-offset (bytes)
  (%pe-lfanew bytes))

(defun %pe-coff-offset (bytes)
  (+ (%pe-signature-offset bytes) 4))

(defun %pe-optional-header-offset (bytes)
  (+ (%pe-coff-offset bytes) 20))

(describe "compile-to-pe image structure"
  (it "starts with the MZ DOS signature"
    (let ((bytes (cl-cc/binary/pe::compile-to-pe #(195) nil)))
      (expect (%read-u16le bytes 0) :to-be cl-cc/binary/pe::+pe-dos-signature+)))

  (it "has the PE signature at e_lfanew"
    (let ((bytes (cl-cc/binary/pe::compile-to-pe #(195) nil)))
      (expect (%read-u32le bytes (%pe-signature-offset bytes)) :to-be cl-cc/binary/pe::+pe-signature+)))

  (it "writes the x86-64 machine type in the COFF header by default"
    (let ((bytes (cl-cc/binary/pe::compile-to-pe #(195) nil)))
      (expect (%read-u16le bytes (%pe-coff-offset bytes)) :to-be cl-cc/binary/pe::+pe-machine-amd64+)))

  (it "writes the arm64 machine type when :arch :arm64 is requested"
    (let ((bytes (cl-cc/binary/pe::compile-to-pe #(195) nil :arch :arm64)))
      (expect (%read-u16le bytes (%pe-coff-offset bytes)) :to-be cl-cc/binary/pe::+pe-machine-arm64+)))

  (it "sets IMAGE_FILE_DLL in the COFF characteristics for a DLL"
    (let* ((bytes (cl-cc/binary/pe::compile-to-pe #(195) nil :dll-p t))
           (characteristics (%read-u16le bytes (+ (%pe-coff-offset bytes) 18))))
      (expect (logtest characteristics cl-cc/binary/pe::+pe-file-dll+) :to-be-truthy)))

  (it "does not set IMAGE_FILE_DLL for a plain executable"
    (let* ((bytes (cl-cc/binary/pe::compile-to-pe #(195) nil))
           (characteristics (%read-u16le bytes (+ (%pe-coff-offset bytes) 18))))
      (expect (logtest characteristics cl-cc/binary/pe::+pe-file-dll+) :to-be-falsy)))

  (it "writes the PE32+ magic in the optional header"
    (let ((bytes (cl-cc/binary/pe::compile-to-pe #(195) nil)))
      (expect (%read-u16le bytes (%pe-optional-header-offset bytes))
              :to-be cl-cc/binary/pe::+pe-magic-pe32-plus+)))

  (it "records a nonzero import directory (the default kernel32.dll import)"
    (let* ((bytes (cl-cc/binary/pe::compile-to-pe #(195) nil))
           (directories-offset (+ (%pe-optional-header-offset bytes) 112))
           (import-dir-offset (+ directories-offset (* 8 cl-cc/binary/pe::+pe-directory-import+)))
           (import-size (%read-u32le bytes (+ import-dir-offset 4))))
      (expect (plusp import-size) :to-be-truthy)))

  (it "records a nonzero export directory once an export is added"
    (let* ((builder (cl-cc/binary/pe::make-pe32+-builder))
           (directories-offset nil))
      (cl-cc/binary/pe::pe-add-text-bytes builder #(195))
      (cl-cc/binary/pe::pe-add-export builder "entry" 0)
      (let* ((bytes (cl-cc/binary/pe::pe-finalize builder))
             (export-dir-offset (progn
                                   (setf directories-offset (+ (%pe-optional-header-offset bytes) 112))
                                   (+ directories-offset (* 8 cl-cc/binary/pe::+pe-directory-export+))))
             (export-size (%read-u32le bytes (+ export-dir-offset 4))))
        (expect (plusp export-size) :to-be-truthy))))

  (it "records a base-relocation directory and preserves PE condition symbol identity"
    (let* ((builder (cl-cc/binary/pe::make-pe32+-builder)))
      (cl-cc/binary/pe::pe-add-text-bytes builder #(195))
      (cl-cc/binary/pe::pe-add-base-relocation builder 0)
      (let* ((bytes (cl-cc/binary/pe::pe-finalize builder))
             (directories-offset (+ (%pe-optional-header-offset bytes) 112))
             (reloc-dir-offset (+ directories-offset (* 8 cl-cc/binary/pe::+pe-directory-base-reloc+)))
             (reloc-size (%read-u32le bytes (+ reloc-dir-offset 4))))
        (expect (plusp reloc-size) :to-be-truthy)
        (expect
            (multiple-value-bind (facade-symbol facade-status)
                (find-symbol "PE-SECTION-NOT-FOUND" "CL-CC/BINARY")
              (multiple-value-bind (feature-symbol feature-status)
                  (find-symbol "PE-SECTION-NOT-FOUND" "CL-CC/BINARY/PE")
                (and (eq facade-status :external)
                     (eq feature-status :external)
                     (eq facade-symbol feature-symbol))))
          :to-be-truthy)
        (expect
            (multiple-value-bind (facade-symbol facade-status)
                (find-symbol "PE-SECTION-NOT-FOUND-NAME" "CL-CC/BINARY")
              (multiple-value-bind (feature-symbol feature-status)
                  (find-symbol "PE-SECTION-NOT-FOUND-NAME" "CL-CC/BINARY/PE")
                (and (eq facade-status :external)
                     (eq feature-status :external)
                     (eq facade-symbol feature-symbol))))
          :to-be-truthy)
        (let* ((snapshot-path
                 (asdf:system-relative-pathname
                  "cl-cc-binary"
                  "t/export-surface.txt"))
               (snapshot
                 (with-open-file (stream snapshot-path)
                   (let ((*package* (find-package "CL-USER"))
                         (*read-eval* nil))
                     (read stream))))
               (facade-package (find-package "CL-CC/BINARY"))
               (expected-external-names nil))
          (dolist (record snapshot)
            (destructuring-bind (record-kind disposition facade-name feature-name
                                 expected-home-package symbol-name
                                 &optional changelog-anchor)
                record
              (declare (ignore expected-home-package changelog-anchor))
              (let ((record-facade (find-package (string-upcase facade-name))))
                (expect (eq record-kind :symbol) :to-be-truthy)
                (expect (eq record-facade facade-package) :to-be-truthy)
                (multiple-value-bind (facade-symbol facade-status)
                    (find-symbol symbol-name record-facade)
                  (case disposition
                    ((:keep :add)
                     (let ((feature-package (find-package (string-upcase feature-name))))
                       (multiple-value-bind (feature-symbol feature-status)
                           (find-symbol symbol-name feature-package)
                         (expect
                           (and (eq facade-status :external)
                                (eq feature-status :external)
                                (eq facade-symbol feature-symbol))
                           :to-be-truthy)
                         (push symbol-name expected-external-names))))
                    (:remove
                     (expect (not (eq facade-status :external))
                             :to-be-truthy))
                    (otherwise
                     (expect nil :to-be-truthy)))))))
          (let ((actual-external-names nil))
            (do-external-symbols (symbol facade-package)
              (push (symbol-name symbol) actual-external-names))
            (expect
              (equal (sort expected-external-names #'string<)
                     (sort actual-external-names #'string<))
              :to-be-truthy)))))))
