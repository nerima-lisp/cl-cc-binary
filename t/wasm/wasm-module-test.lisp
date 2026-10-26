(in-package #:cl-cc/binary/wasm/test)
(describe "WASM binary sections and debug metadata"
  (it "encodes the largest unsigned 32-bit index as five ULEB128 bytes"
    (expect (cl-cc/binary/wasm:encode-uleb128 #xffffffff)
            :to-equal '(#xff #xff #xff #xff #x0f)))

  (it "rejects negative unsigned LEB128 values"
    (expect (lambda () (cl-cc/binary/wasm:encode-uleb128 -1))
            :to-throw 'type-error))

  (it "rejects non-integer signed LEB128 values"
    (expect (lambda () (cl-cc/binary/wasm:encode-sleb128 "1"))
            :to-throw 'type-error))

  (it "frames a standard section around its payload"
    (expect (coerce (encode-wasm-section 1 '(#x01 #x02)) 'list)
            :to-equal '(1 2 1 2)))

  (it "rejects section identifiers outside one byte"
    (expect (lambda () (encode-wasm-section 256 #()))
            :to-throw 'type-error))

  (it "rejects non-byte section payload elements"
    (expect (lambda () (encode-wasm-section 1 #(256)))
            :to-throw 'type-error))

  (it "encodes type records from parameter and result valtype bytes"
    (expect (coerce (encode-wasm-type-section '(((#x7f #x7e) (#x7f)))) 'list)
            :to-equal '(1 7 1 #x60 2 #x7f #x7e 1 #x7f)))

  (it "rejects malformed function type records"
    (expect (lambda () (encode-wasm-type-section '((#x7f))))
            :to-throw 'error))

  (it "encodes function-section type indices"
    (expect (coerce (encode-wasm-function-section '(0 3)) 'list)
            :to-equal '(3 3 2 0 3)))

  (it "rejects negative type indices"
    (expect (lambda () (encode-wasm-function-section '(-1)))
            :to-throw 'type-error))

  (it "encodes export name, kind, and index records"
    (expect (coerce (encode-wasm-export-section '(("run" 0 2))) 'list)
            :to-equal '(7 7 1 3 114 117 110 0 2)))

  (it "rejects export kinds outside the standard kind range"
    (expect (lambda () (encode-wasm-export-section '(("run" 5 2))))
            :to-throw 'type-error))

  (it "encodes raw function bodies with their byte lengths"
    (expect (coerce (encode-wasm-code-section '(#(#x00 #x0b))) 'list)
            :to-equal '(10 4 1 2 0 11)))

  (it "rejects non-byte function body elements"
    (expect (lambda () (encode-wasm-code-section '(#(256))))
            :to-throw 'type-error))

  (it "encodes custom section names as UTF-8"
    (expect (coerce (encode-wasm-custom-section "λ" #()) 'list)
            :to-equal '(0 3 2 #xce #xbb)))

  (it "serializes module, function, local, and label name records"
    (expect
     (coerce (encode-wasm-name-section
              "M" '((0 . "f"))
              :local-names '((0 (0 . "x")))
              :label-names '((0 (1 . "L"))))
             'list)
     :to-equal '(0 31 4 110 97 109 101
                 0 2 1 77
                 1 4 1 0 1 102
                 2 6 1 0 1 0 1 120
                 3 6 1 0 1 1 1 76)))

  (it "rejects negative name indices"
    (expect (lambda () (encode-wasm-name-section "M" '((-1 . "f"))))
            :to-throw 'type-error))

  (it "writes a module header followed by framed sections"
    (expect
     (coerce (encode-wasm-module (list (encode-wasm-custom-section "x" #()))) 'list)
     :to-equal '(0 97 115 109 1 0 0 0 0 2 1 120)))
  (it "matches codegen-native's standard and name section bytes"
    (let* ((standard-sections
             (list (encode-wasm-type-section '((nil nil)))
                   (encode-wasm-function-section '(0))
                   (encode-wasm-export-section '(("run" 0 0)))
                   (encode-wasm-code-section '(#(#x00 #x0b)))))
           (name-section
             (encode-wasm-name-section
              "cl-cc-wasm-module"
              '((0 . "main"))
              :local-names '((0 . ((0 . "pc") (1 . "tmp"))))
              :label-names '((0))))
           (standard-module (encode-wasm-module standard-sections))
           (module-bytes
             (encode-wasm-module
              (append standard-sections (list name-section)))))
      (expect (plusp (length module-bytes)) :to-equal t)
      (expect (length module-bytes) :to-equal 88)
      (expect (coerce standard-module 'list)
              :to-equal
              '(0 97 115 109 1 0 0 0 1 4 1 96 0 0 3 2 1 0
                7 7 1 3 114 117 110 0 0 10 4 1 2 0 11))
      (expect (coerce name-section 'list)
              :to-equal
              '(0 53 4 110 97 109 101 0 18 17 99 108 45 99 99 45 119
                97 115 109 45 109 111 100 117 108 101 1 7 1 0 4 109
                97 105 110 2 12 1 0 2 0 2 112 99 1 3 116 109 112
                3 3 1 0 0))
      (expect (coerce module-bytes 'list)
              :to-equal
              '(0 97 115 109 1 0 0 0 1 4 1 96 0 0 3 2 1 0 7 7 1 3
                114 117 110 0 0 10 4 1 2 0 11 0 53 4 110 97 109 101
                0 18 17 99 108 45 99 99 45 119 97 115 109 45 109 111
                100 117 108 101 1 7 1 0 4 109 97 105 110 2 12 1 0 2 0
                2 112 99 1 3 116 109 112 3 3 1 0 0)))))
