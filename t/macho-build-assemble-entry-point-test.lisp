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

(defun %macho-segment-offsets (image)
  (loop with offset = 32
        repeat (%macho-u32le image 16)
        when (= (%macho-u32le image offset) #x19) collect offset
        do (incf offset (%macho-u32le image (+ offset 4)))))

(defun %macho-u64le (image offset)
  (+ (%macho-u32le image offset)
     (ash (%macho-u32le image (+ offset 4)) 32)))

(defun %macho-segment-name (image offset)
  (map 'string #'code-char
       (subseq image (+ offset 8)
               (position 0 image :start (+ offset 8) :end (+ offset 24)))))

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

(describe "Mach-O mapped segment layout"
  (dolist (arch '(:x86-64 :arm64))
    (dolist (size '(12 16385 65537))
      (it (format nil "keeps ~A segments aligned and disjoint for ~D code bytes" arch size)
        (let* ((page (if (eq arch :arm64) #x4000 #x1000))
               (code (make-array size :element-type '(unsigned-byte 8) :initial-element #x42))
               (data (make-array 19 :element-type '(unsigned-byte 8) :initial-element #x73))
               (const (make-array 23 :element-type '(unsigned-byte 8) :initial-element #x91))
               (builder (cl-cc/binary:make-mach-o-builder arch)))
          ;; Deliberately add TEXT last: file order must not depend on API call order.
          (cl-cc/binary:add-data-segment builder data)
          (when (> size 12) (cl-cc/binary:add-data-const-segment builder const))
          (cl-cc/binary:add-text-segment builder code)
          (let* ((image (cl-cc/binary:build-mach-o builder code))
                 (segments (rest (%macho-segment-offsets image)))
                 (text (first segments))
                 (entry (cl-cc/binary:entry-point-command-entryoff
                         (cl-cc/binary::mach-o-builder-entry-point builder))))
            (expect (%macho-segment-name image text) :to-equalp "__TEXT")
            (expect (mod entry page) :to-be 0)
            (expect (subseq image entry (+ entry size)) :to-equalp code)
            (loop for segment in segments
                  for name = (%macho-segment-name image segment)
                  for expected = (cond ((string= name "__TEXT") 5)
                                       ((string= name "__DATA") 3) (t 1))
                  do (dolist (field '(24 32 40))
                       (expect (mod (%macho-u64le image (+ segment field)) page) :to-be 0))
                     (expect (%macho-u32le image (+ segment 56)) :to-be expected)
                     (expect (%macho-u32le image (+ segment 60)) :to-be expected)
                     (expect (<= (%macho-u64le image (+ segment 48))
                                 (%macho-u64le image (+ segment 32))) :to-be t)
                     (when (member name '("__DATA" "__DATA_CONST") :test #'string=)
                       (let* ((section (+ segment 72))
                              (offset (%macho-u32le image (+ section 48)))
                              (payload (if (string= name "__DATA") data
                                           (if (> size 12) const #()))))
                         (expect (%macho-u64le image (+ section 32))
                                 :to-be (%macho-u64le image (+ segment 24)))
                         (expect (subseq image offset (+ offset (length payload)))
                                 :to-equalp payload)))
                     (loop for other in (cdr (member segment segments))
                           do (expect (<= (+ (%macho-u64le image (+ segment 24))
                                             (%macho-u64le image (+ segment 32)))
                                          (%macho-u64le image (+ other 24))) :to-be t)
                              (expect (<= (+ (%macho-u64le image (+ segment 40))
                                             (%macho-u64le image (+ segment 48)))
                                          (%macho-u64le image (+ other 40))) :to-be t)))))))))
