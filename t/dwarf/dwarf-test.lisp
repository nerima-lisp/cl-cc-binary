;;;; t/dwarf-test.lisp — DWARF v5 debug info (FR-550/552)
;;;;
;;;; dwarf.lisp had no test coverage at all before this file.

(in-package #:cl-cc/binary/dwarf/test)

(describe "build-dwarf-debug-sections"
  (it "produces non-empty .debug_info, .debug_abbrev, and .debug_str for a minimal compile unit"
    (let* ((cu (cl-cc/binary/dwarf::make-dwarf-compile-unit :name "a.lisp" :producer "cl-cc 0.1.0"))
           (sections (cl-cc/binary/dwarf:build-dwarf-debug-sections cu)))
      (expect (plusp (length (cl-cc/binary/dwarf::dwarf-debug-sections-info sections))) :to-be-truthy)
      (expect (plusp (length (cl-cc/binary/dwarf::dwarf-debug-sections-abbrev sections))) :to-be-truthy)
      (expect (plusp (length (cl-cc/binary/dwarf::dwarf-debug-sections-str sections))) :to-be-truthy)))

  (it "produces a .debug_line section with entries for the compile unit's line table"
    (let* ((cu (cl-cc/binary/dwarf::make-dwarf-compile-unit
                :name "a.lisp" :lines '((0 1) (4 2) (8 3))))
           (sections (cl-cc/binary/dwarf:build-dwarf-debug-sections cu)))
      (expect (plusp (length (cl-cc/binary/dwarf::dwarf-debug-sections-line sections))) :to-be-truthy)))

  (it "includes a subprogram's name in the .debug_str section"
    (let* ((sp (cl-cc/binary/dwarf::make-dwarf-subprogram :name "my-unusual-function-name"
                                                     :low-pc 0 :high-pc 16))
           (cu (cl-cc/binary/dwarf::make-dwarf-compile-unit :name "a.lisp" :subprograms (list sp)))
           (sections (cl-cc/binary/dwarf:build-dwarf-debug-sections cu))
           (str-bytes (cl-cc/binary/dwarf::dwarf-debug-sections-str sections))
           (str-text (map 'string #'code-char str-bytes)))
      (expect (search "my-unusual-function-name" str-text) :to-be-truthy)))

  (it "produces a non-empty .debug_loc section when a subprogram has a variable"
    (let* ((var (cl-cc/binary/dwarf::make-dwarf-variable-location
                 :name "x" :kind :register :register 0 :pc-start 0 :pc-end 16))
           (sp (cl-cc/binary/dwarf::make-dwarf-subprogram :name "f" :low-pc 0 :high-pc 16
                                                     :variables (list var)))
           (cu (cl-cc/binary/dwarf::make-dwarf-compile-unit :name "a.lisp" :subprograms (list sp)))
           (sections (cl-cc/binary/dwarf:build-dwarf-debug-sections cu)))
      (expect (plusp (length (cl-cc/binary/dwarf::dwarf-debug-sections-loc sections))) :to-be-truthy)))
  (it "fr-550-dwarf5-debug-sections-have-byte-level-headers"
    (let* ((cu (cl-cc/binary/dwarf::make-dwarf-compile-unit
                :name "fr550.lisp"
                :producer "cl-cc-test"
                :low-pc #x1000
                :high-pc #x1020
                :lines '((0 1) (4 2))
                :subprograms
                (list (cl-cc/binary/dwarf::make-dwarf-subprogram
                       :name "main"
                       :low-pc #x1000
                       :high-pc #x1020
                       :parameters
                       (list (cl-cc/binary/dwarf::make-dwarf-variable-location
                              :name "x" :kind :register :register 0))))))
           (sections (cl-cc/binary/dwarf:build-dwarf-debug-sections cu))
           (info (cl-cc/binary/dwarf::dwarf-debug-sections-info sections))
           (line (cl-cc/binary/dwarf::dwarf-debug-sections-line sections))
           (abbrev (cl-cc/binary/dwarf::dwarf-debug-sections-abbrev sections)))
      (expect (plusp (length info)) :to-be-truthy)
      (expect (plusp (length line)) :to-be-truthy)
      (expect (plusp (length abbrev)) :to-be-truthy)
      ;; .debug_info: unit_length:u32, version:u16=5, unit_type=compile, addr_size=8.
      (expect (coerce (subseq info 4 8) 'list) :to-equal '(5 0 1 8))
      ;; .debug_line: unit_length:u32, version:u16=5, addr_size=8, segment_selector=0.
      (expect (coerce (subseq line 4 8) 'list) :to-equal '(5 0 8 0))
      (expect (> (length abbrev) 8) :to-be-truthy))))

(describe "dwarf-location-expression"
  (it "encodes a :register location as DW_OP_regN"
    (let* ((loc (cl-cc/binary/dwarf::make-dwarf-variable-location :kind :register :register 3))
           (expr (cl-cc/binary/dwarf::dwarf-location-expression loc)))
      (expect (aref expr 0) :to-be (+ cl-cc/binary/dwarf::+dwarf-dw-op-reg0+ 3))
      (expect (length expr) :to-be 1)))

  (it "encodes a :base-register location as DW_OP_bregN plus a signed offset"
    (let* ((loc (cl-cc/binary/dwarf::make-dwarf-variable-location :kind :base-register
                                                             :register 6 :offset -8))
           (expr (cl-cc/binary/dwarf::dwarf-location-expression loc)))
      (expect (aref expr 0) :to-be (+ cl-cc/binary/dwarf::+dwarf-dw-op-breg0+ 6))
      (expect (> (length expr) 1) :to-be-truthy)))

  (it "encodes a :frame-base location as DW_OP_fbreg plus a signed offset"
    (let* ((loc (cl-cc/binary/dwarf::make-dwarf-variable-location :kind :frame-base :offset -16))
           (expr (cl-cc/binary/dwarf::dwarf-location-expression loc)))
      (expect (aref expr 0) :to-be cl-cc/binary/dwarf::+dwarf-dw-op-fbreg+)))

  (it "signals value-out-of-range for a :register location with register >= 32"
    (let ((loc (cl-cc/binary/dwarf::make-dwarf-variable-location :kind :register :register 32)))
      (expect (lambda () (cl-cc/binary/dwarf::dwarf-location-expression loc))
              :to-throw 'cl-cc/binary/buffer:value-out-of-range)))

  (it "signals value-out-of-range for a :base-register location with register >= 32"
    (let ((loc (cl-cc/binary/dwarf::make-dwarf-variable-location :kind :base-register :register 40)))
      (expect (lambda () (cl-cc/binary/dwarf::dwarf-location-expression loc))
              :to-throw 'cl-cc/binary/buffer:value-out-of-range))))
