;;;; t/dwarf-test.lisp — DWARF v5 debug info (FR-550/552)
;;;;
;;;; dwarf.lisp had no test coverage at all before this file.

(in-package :cl-cc-binary/test)

(describe "build-dwarf-debug-sections"
  (it "produces non-empty .debug_info, .debug_abbrev, and .debug_str for a minimal compile unit"
    (let* ((cu (cl-cc/binary::make-dwarf-compile-unit :name "a.lisp" :producer "cl-cc 0.1.0"))
           (sections (cl-cc/binary:build-dwarf-debug-sections cu)))
      (expect (plusp (length (cl-cc/binary::dwarf-debug-sections-info sections))) :to-be-truthy)
      (expect (plusp (length (cl-cc/binary::dwarf-debug-sections-abbrev sections))) :to-be-truthy)
      (expect (plusp (length (cl-cc/binary::dwarf-debug-sections-str sections))) :to-be-truthy)))

  (it "produces a .debug_line section with entries for the compile unit's line table"
    (let* ((cu (cl-cc/binary::make-dwarf-compile-unit
                :name "a.lisp" :lines '((0 1) (4 2) (8 3))))
           (sections (cl-cc/binary:build-dwarf-debug-sections cu)))
      (expect (plusp (length (cl-cc/binary::dwarf-debug-sections-line sections))) :to-be-truthy)))

  (it "includes a subprogram's name in the .debug_str section"
    (let* ((sp (cl-cc/binary::make-dwarf-subprogram :name "my-unusual-function-name"
                                                     :low-pc 0 :high-pc 16))
           (cu (cl-cc/binary::make-dwarf-compile-unit :name "a.lisp" :subprograms (list sp)))
           (sections (cl-cc/binary:build-dwarf-debug-sections cu))
           (str-bytes (cl-cc/binary::dwarf-debug-sections-str sections))
           (str-text (map 'string #'code-char str-bytes)))
      (expect (search "my-unusual-function-name" str-text) :to-be-truthy)))

  (it "produces a non-empty .debug_loc section when a subprogram has a variable"
    (let* ((var (cl-cc/binary::make-dwarf-variable-location
                 :name "x" :kind :register :register 0 :pc-start 0 :pc-end 16))
           (sp (cl-cc/binary::make-dwarf-subprogram :name "f" :low-pc 0 :high-pc 16
                                                     :variables (list var)))
           (cu (cl-cc/binary::make-dwarf-compile-unit :name "a.lisp" :subprograms (list sp)))
           (sections (cl-cc/binary:build-dwarf-debug-sections cu)))
      (expect (plusp (length (cl-cc/binary::dwarf-debug-sections-loc sections))) :to-be-truthy))))

(describe "dwarf-location-expression"
  (it "encodes a :register location as DW_OP_regN"
    (let* ((loc (cl-cc/binary::make-dwarf-variable-location :kind :register :register 3))
           (expr (cl-cc/binary::dwarf-location-expression loc)))
      (expect (aref expr 0) :to-be (+ cl-cc/binary::+dwarf-dw-op-reg0+ 3))
      (expect (length expr) :to-be 1)))

  (it "encodes a :base-register location as DW_OP_bregN plus a signed offset"
    (let* ((loc (cl-cc/binary::make-dwarf-variable-location :kind :base-register
                                                             :register 6 :offset -8))
           (expr (cl-cc/binary::dwarf-location-expression loc)))
      (expect (aref expr 0) :to-be (+ cl-cc/binary::+dwarf-dw-op-breg0+ 6))
      (expect (> (length expr) 1) :to-be-truthy)))

  (it "encodes a :frame-base location as DW_OP_fbreg plus a signed offset"
    (let* ((loc (cl-cc/binary::make-dwarf-variable-location :kind :frame-base :offset -16))
           (expr (cl-cc/binary::dwarf-location-expression loc)))
      (expect (aref expr 0) :to-be cl-cc/binary::+dwarf-dw-op-fbreg+)))

  (it "signals value-out-of-range for a :register location with register >= 32"
    (let ((loc (cl-cc/binary::make-dwarf-variable-location :kind :register :register 32)))
      (expect (lambda () (cl-cc/binary::dwarf-location-expression loc))
              :to-throw 'cl-cc/binary:value-out-of-range)))

  (it "signals value-out-of-range for a :base-register location with register >= 32"
    (let ((loc (cl-cc/binary::make-dwarf-variable-location :kind :base-register :register 40)))
      (expect (lambda () (cl-cc/binary::dwarf-location-expression loc))
              :to-throw 'cl-cc/binary:value-out-of-range))))
