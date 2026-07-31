;;;; t/dwarf-eh-test.lisp — DWARF .eh_frame call-frame information (FR-560)
;;;;
;;;; dwarf-eh.lisp had no test coverage at all before this file.

(in-package :cl-cc-binary/test)

(defun %dwarf-eh-cie-id (bytes)
  "The CIE_id field just after the length prefix; zero identifies a CIE."
  (%elf-u32le bytes 4))

(describe "build-dwarf-eh-frame"
  (it "starts with a CIE (CIE_id = 0) when there are no FDEs"
    (let ((bytes (cl-cc/binary:build-dwarf-eh-frame nil)))
      (expect (%dwarf-eh-cie-id bytes) :to-be 0)))

  (it "grows when an FDE is appended after the CIE"
    (let* ((no-fde (cl-cc/binary:build-dwarf-eh-frame nil))
           (fde (cl-cc/binary:make-dwarf-eh-fde :initial-location 0 :address-range 16))
           (with-fde (cl-cc/binary:build-dwarf-eh-frame (list fde))))
      (expect (> (length with-fde) (length no-fde)) :to-be-truthy)))

  (it "includes the FDE's address-range in its payload"
    (let* ((fde (cl-cc/binary:make-dwarf-eh-fde :initial-location 0 :address-range #x1234))
           (bytes (cl-cc/binary:build-dwarf-eh-frame (list fde)))
           ;; CIE occupies the first (length-prefix + length) bytes; the FDE
           ;; starts there as [length u32][cie_pointer u32][initial_location
           ;; u32][address_range u32], so address-range is 12 bytes in.
           (cie-len (%elf-u32le bytes 0))
           (fde-start (+ 4 cie-len))
           (address-range (%elf-u32le bytes (+ fde-start 12))))
      (expect address-range :to-be #x1234))))

(describe "build-dwarf-eh-lsda"
  (it "returns a nonempty payload for one cleanup-only call site"
    (let ((cs (cl-cc/binary:make-dwarf-eh-call-site :start 0 :length 16 :cleanup-p t)))
      (expect (plusp (length (cl-cc/binary:build-dwarf-eh-lsda (list cs)))) :to-be-truthy)))

  (it "grows when a typed (non-cleanup) call site adds a type-tag table entry"
    (let* ((cleanup-only (list (cl-cc/binary:make-dwarf-eh-call-site :start 0 :length 16
                                                                     :cleanup-p t)))
           (typed (list (cl-cc/binary:make-dwarf-eh-call-site :start 0 :length 16 :action 1
                                                              :type 'error :cleanup-p nil))))
      (expect (> (length (cl-cc/binary:build-dwarf-eh-lsda typed))
                 (length (cl-cc/binary:build-dwarf-eh-lsda cleanup-only)))
              :to-be-truthy))))

(describe "DWARF CFA short-form emitters"
  (it "dwarf-eh-emit-offset writes the trailing factored-offset ULEB128 operand"
    (cl-cc/binary::with-byte-buffer (buf)
      (cl-cc/binary::dwarf-eh-emit-offset buf 3 1)
      (expect (> (length buf) 1) :to-be-truthy)))

  (it "dwarf-eh-emit-advance-loc signals value-out-of-range above the 6-bit short-form limit"
    (expect (lambda ()
              (cl-cc/binary::with-byte-buffer (buf)
                (cl-cc/binary::dwarf-eh-emit-advance-loc buf 64)))
            :to-throw 'cl-cc/binary:value-out-of-range))

  (it "dwarf-eh-emit-restore signals value-out-of-range above the 6-bit short-form limit"
    (expect (lambda ()
              (cl-cc/binary::with-byte-buffer (buf)
                (cl-cc/binary::dwarf-eh-emit-restore buf 64)))
            :to-throw 'cl-cc/binary:value-out-of-range))

  (it "dwarf-eh-emit-offset signals value-out-of-range above the 6-bit short-form limit"
    (expect (lambda ()
              (cl-cc/binary::with-byte-buffer (buf)
                (cl-cc/binary::dwarf-eh-emit-offset buf 64 1)))
            :to-throw 'cl-cc/binary:value-out-of-range)))

(describe "dwarf-eh-encode-instruction-list"
  (it "encodes a :def-cfa-offset instruction"
    (expect (plusp (length (cl-cc/binary::dwarf-eh-encode-instruction-list
                            '((:def-cfa-offset 16)))))
            :to-be-truthy))

  (it "encodes an :advance-loc instruction"
    (expect (plusp (length (cl-cc/binary::dwarf-eh-encode-instruction-list
                            '((:advance-loc 4)))))
            :to-be-truthy))

  (it "passes a raw byte vector instruction through unchanged"
    (expect (coerce (cl-cc/binary::dwarf-eh-encode-instruction-list (list #(1 2 3)))
                    'list)
            :to-equal '(1 2 3))))
