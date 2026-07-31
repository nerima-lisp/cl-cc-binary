(in-package :cl-cc/binary)

(defun macho-build-unwind-info (code-size &key
                                            (encoding +compact-unwind-x86-64-mode-stack-immd+)
                                            (personality 0))
  "Build a compact __unwind_info payload with one frameless function entry.

The payload starts with a small CL-CC table header followed by a per-function
entry: start address, function length, compact unwind ENCODING, and
PERSONALITY.  The default encoding models frameless/RBP-less x86-64 functions.
This Pure CL backend emits the documented interface without platform mprotect
or linker-private helpers."
  (with-byte-buffer (buf)
    ;; Signature/version for CL-CC's compact table envelope.
    (binary-buffer-write-bytes buf (map 'vector #'char-code "CLCU"))
    (binary-buffer-write-u32le buf 1)         ; version
    (binary-buffer-write-u32le buf 1)         ; entry count
    (binary-buffer-write-u32le buf 16)        ; first entry offset
    ;; Entry: start address (section-relative), length, encoding, personality.
    (binary-buffer-write-u32le buf 0)
    (binary-buffer-write-u32le buf code-size)
    (binary-buffer-write-u32le buf encoding)
    (binary-buffer-write-u32le buf personality)))

(defun %build-macho-payload (code-bytes compressed-payload compressed-offset
                             unwind-bytes unwind-offset)
  "Assemble CODE-BYTES, COMPRESSED-PAYLOAD, and UNWIND-BYTES into one flat vector.
COMPRESSED-PAYLOAD may be NIL when no compression was applied."
  (let* ((payload-size (+ unwind-offset (length unwind-bytes)))
         (payload (make-array payload-size :element-type '(unsigned-byte 8)
                              :initial-element 0)))
    (replace payload code-bytes :start1 0)
    (when compressed-payload
      (replace payload compressed-payload :start1 compressed-offset))
    (replace payload unwind-bytes :start1 unwind-offset)
    payload))

(defun %macho-build-text-sections (text-seg code-size compressed-payload unwind-bytes)
  "Return the list of section objects for a __TEXT segment.
Finds or creates __text, optionally __compressed, and __unwind_info sections."
  (let ((text-section (or (find "__text" (segment-command-sections text-seg)
                                :key #'section-sectname :test #'string=)
                          (make-section :sectname "__text"
                                        :segname "__TEXT"
                                        :size code-size
                                        :align 4
                                        :flags (logior +s-attr-pure-instructions+
                                                       +s-attr-some-instructions+))))
        (compressed-section (when compressed-payload
                              (or (find "__compressed" (segment-command-sections text-seg)
                                        :key #'section-sectname :test #'string=)
                                  (make-section :sectname "__compressed"
                                                :segname "__TEXT"
                                                :size (length compressed-payload)
                                                :align 4))))
        (unwind-section (or (find "__unwind_info" (segment-command-sections text-seg)
                                  :key #'section-sectname :test #'string=)
                            (make-section :sectname "__unwind_info"
                                          :segname "__TEXT"
                                          :size (length unwind-bytes)
                                          :align 2))))
    (setf (section-size text-section) code-size
          (section-size unwind-section) (length unwind-bytes))
    (when compressed-section
      (setf (section-size compressed-section) (length compressed-payload)))
    (if compressed-payload
        (list text-section compressed-section unwind-section)
        (list text-section unwind-section))))

(defun %macho-ensure-data-const-segment (user-segments)
  "Push a default empty __DATA_CONST segment onto USER-SEGMENTS unless one exists.
Returns the (possibly extended) segment list."
  (unless (find "__DATA_CONST" user-segments
                :key #'segment-command-segname :test #'string=)
    ;; Emit an empty read-only constant segment by default. Frontends with
    ;; string literals/constant pools can call ADD-DATA-CONST-SEGMENT to fill
    ;; this section; keeping the segment present documents and preserves the
    ;; protection boundary in every binary.
    (let* ((const-bytes (make-array 0 :element-type '(unsigned-byte 8)))
           (const-section (make-section :sectname "__const"
                                        :segname "__DATA_CONST"
                                        :addr +macho-data-const-base-addr+
                                        :size 0
                                        :align 4))
           (const-segment (make-segment-command
                           :segname "__DATA_CONST"
                           :vmaddr +macho-data-const-base-addr+
                           :vmsize #x1000
                           :payload const-bytes
                           :nsects 1
                           :maxprot 4
                           :initprot 4
                           :cmdsize (+ +macho-segment-command-size+ +macho-section-size+)
                           :sections (list const-section))))
      (push const-segment user-segments)))
  user-segments)

(defun %mach-o-ensure-text-and-unwind (user-segments code-bytes &key compress)
  "Return USER-SEGMENTS with __TEXT unwind info and read-only constants support."
  (let* ((code-size (length code-bytes))
         (compressed-payload
           (compress-code-bytes-cps
            code-bytes compress
            (lambda (compressed original-size compressed-size)
              (build-compressed-code-payload compressed +cl-cc-compression-zlib+
                                             original-size compressed-size))
            (constantly nil))))
    (let* ((unwind-bytes (macho-build-unwind-info code-size))
           (compressed-offset (and compressed-payload (align-up code-size 4)))
           (unwind-offset (align-up (if compressed-payload
                                        (+ compressed-offset (length compressed-payload))
                                        code-size)
                                    4))
           (payload (%build-macho-payload code-bytes compressed-payload compressed-offset
                                          unwind-bytes unwind-offset))
           (payload-size (length payload))
           (text-seg (find "__TEXT" user-segments
                           :key #'segment-command-segname :test #'string=)))
      (unless text-seg
        (setf text-seg (make-segment-command
                        :segname "__TEXT"
                        :vmaddr +macho-text-base-addr+
                        :vmsize (align-up payload-size #x1000)
                        :nsects 0
                        :cmdsize +macho-segment-command-size+
                        :sections nil))
        (push text-seg user-segments))
      (let ((sections (%macho-build-text-sections text-seg code-size
                                                   compressed-payload unwind-bytes)))
        (setf (segment-command-payload text-seg) payload
              (segment-command-nsects text-seg) (length sections)
              (segment-command-cmdsize text-seg)
              (+ +macho-segment-command-size+
                 (* +macho-section-size+ (length sections)))
              (segment-command-maxprot text-seg) 5
              (segment-command-initprot text-seg) 5
              (segment-command-sections text-seg) sections))
      (%macho-ensure-data-const-segment user-segments))))
