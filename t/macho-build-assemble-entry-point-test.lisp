;;;; t/macho-build-assemble-entry-point-test.lisp — end-to-end BUILD-MACH-O coverage
;;;;
;;;; Nothing in this suite used to call BUILD-MACH-O, so the whole executable
;;;; assembly path was untested. When macho-serialize.lisp moved its
;;;; hand-written serializers onto DEFINE-BINARY-STRUCT, the generated function
;;;; for entry-point-command became SERIALIZE-ENTRY-POINT-COMMAND while the
;;;; single call site in macho-build-assemble.lisp still said
;;;; SERIALIZE-ENTRY-POINT. That is a compile-time style warning and a runtime
;;;; UNDEFINED-FUNCTION, and it reached main because no test ever ran the
;;;; function containing the call.
;;;;
;;;; These assertions are deliberately about the header bytes rather than the
;;;; exact image layout: the point is that the path executes and produces a
;;;; recognizable Mach-O, not to pin the byte-for-byte output of the assembler.

(in-package :cl-cc-binary/test)

(defun %macho-u32le (bytes offset)
  (logior (aref bytes offset)
          (ash (aref bytes (1+ offset)) 8)
          (ash (aref bytes (+ offset 2)) 16)
          (ash (aref bytes (+ offset 3)) 24)))

(defun %macho-exit-stub ()
  "Twelve bytes of x86-64: mov edi, 0 / mov eax, 60 / syscall."
  (coerce #(#xbf #x00 #x00 #x00 #x00
            #xb8 #x3c #x00 #x00 #x00
            #x0f #x05)
          '(simple-array (unsigned-byte 8) (*))))

(describe "build-mach-o executable assembly"

  (dolist (arch '(:x86-64 :arm64))
    (describe (format nil "~a" arch)
      (it "assembles an image with an LC_MAIN entry point"
        (let* ((code (%macho-exit-stub))
               (builder (cl-cc/binary:make-mach-o-builder arch)))
          (cl-cc/binary:add-text-segment builder code)
          (cl-cc/binary:add-entry-point builder 0)
          (let ((image (cl-cc/binary:build-mach-o builder code)))
            (expect (plusp (length image)))
            (expect (= (%macho-u32le image 0) cl-cc/binary:+mh-magic-64+))
            (expect (= (%macho-u32le image 12) cl-cc/binary:+mh-execute+)))))))

  (it "records the entry offset on the builder's LC_MAIN command"
    (let* ((code (%macho-exit-stub))
           (builder (cl-cc/binary:make-mach-o-builder :x86-64)))
      (cl-cc/binary:add-text-segment builder code)
      (cl-cc/binary:add-entry-point builder 0)
      (cl-cc/binary:build-mach-o builder code)
      (expect (plusp (cl-cc/binary:entry-point-command-entryoff
                  (cl-cc/binary::mach-o-builder-entry-point builder)))))))
