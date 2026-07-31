;;;; t/wasm-test.lisp — WASM binary format utilities (src/wasm.lisp)
;;;;
;;;; src/wasm.lisp had no test file at all: an SB-COVER report showed 0/138
;;;; expressions exercised, the only entire source file in src/ with zero
;;;; coverage. This tests both LEB128 encoders against known reference values
;;;; and, via a hand-written decoder used only in this test, the general
;;;; round-trip property every value must satisfy; and PORTABLE-DOUBLE-FLOAT-BITS
;;;; against known IEEE754 double bit patterns.

(in-package :cl-cc-binary/test)

(defun %decode-uleb128 (bytes)
  "Decode BYTES (a list) as unsigned LEB128, the inverse of ENCODE-ULEB128."
  (loop with result = 0
        for shift from 0 by 7
        for byte in bytes
        do (setf result (logior result (ash (logand byte #x7f) shift)))
        until (zerop (logand byte #x80))
        finally (return result)))

(defun %decode-sleb128 (bytes)
  "Decode BYTES (a list) as signed LEB128, the inverse of ENCODE-SLEB128."
  (let ((result 0) (shift 0) (byte 0))
    (loop for b in bytes
          do (setf byte b)
             (setf result (logior result (ash (logand byte #x7f) shift)))
             (incf shift 7)
          until (zerop (logand byte #x80)))
    (if (and (< shift 64) (plusp (logand byte #x40)))
        (logior result (ash -1 shift))
        result)))

(describe "encode-uleb128"
  (it "encodes 0 as a single zero byte"
    (expect (cl-cc/binary::encode-uleb128 0) :to-equal '(0)))

  (it "encodes 127 (the largest 7-bit value) as a single byte with no continuation"
    (expect (cl-cc/binary::encode-uleb128 127) :to-equal '(127)))

  (it "encodes 128 across two bytes with the continuation bit set on the first"
    (expect (cl-cc/binary::encode-uleb128 128) :to-equal (list #x80 #x01)))

  (it "matches the canonical DWARF/WASM spec example for 624485"
    (expect (cl-cc/binary::encode-uleb128 624485) :to-equal (list #xe5 #x8e #x26)))

  (it-property "round-trips through %decode-uleb128 for any non-negative integer"
      ((value (gen-integer :min 0 :max 100000000)))
    (expect (%decode-uleb128 (cl-cc/binary::encode-uleb128 value)) :to-be value)))

(describe "encode-sleb128"
  (it "encodes 0 as a single zero byte"
    (expect (cl-cc/binary::encode-sleb128 0) :to-equal '(0)))

  (it "encodes -1 as a single byte with the sign bit set and no continuation"
    (expect (cl-cc/binary::encode-sleb128 -1) :to-equal (list #x7f)))

  (it "encodes 63 (the largest positive value with no continuation) as a single byte"
    (expect (cl-cc/binary::encode-sleb128 63) :to-equal (list #x3f)))

  (it "matches the canonical DWARF/WASM spec example for -123456"
    (expect (cl-cc/binary::encode-sleb128 -123456) :to-equal (list #xc0 #xbb #x78)))

  (it-property "round-trips through %decode-sleb128 for any integer in range"
      ((value (gen-integer :min -100000000 :max 100000000)))
    (expect (%decode-sleb128 (cl-cc/binary::encode-sleb128 value)) :to-be value)))

(describe "portable-double-float-bits"
  (it-each ((1.0d0  #x3ff0000000000000)
            (2.0d0  #x4000000000000000)
            (0.5d0  #x3fe0000000000000)
            (-1.0d0 #xbff0000000000000)
            (0.0d0  #x0000000000000000))
      "encodes ~A as the IEEE754 double bit pattern ~X"
      (value expected)
    (expect (cl-cc/binary::portable-double-float-bits value) :to-be expected))

  (it "encodes -0.0d0 with the sign bit set and all other bits zero"
    (expect (cl-cc/binary::portable-double-float-bits -0.0d0)
            :to-be (ash 1 63)))

  (it "encodes positive infinity as exponent all-ones with a zero mantissa"
    (sb-int:with-float-traps-masked (:overflow :invalid :divide-by-zero)
      (expect (cl-cc/binary::portable-double-float-bits
               sb-ext:double-float-positive-infinity)
              :to-be (ash #x7ff 52))))

  (it "encodes negative infinity as exponent all-ones, sign bit set, zero mantissa"
    (sb-int:with-float-traps-masked (:overflow :invalid :divide-by-zero)
      (expect (cl-cc/binary::portable-double-float-bits
               sb-ext:double-float-negative-infinity)
              :to-be (logior (ash 1 63) (ash #x7ff 52)))))

  (it "encodes a quiet NaN with exponent all-ones and a nonzero mantissa"
    (sb-int:with-float-traps-masked (:invalid)
      (let ((bits (cl-cc/binary::portable-double-float-bits
                   (- sb-ext:double-float-positive-infinity
                      sb-ext:double-float-positive-infinity))))
        (expect (= (ldb (byte 11 52) bits) #x7ff))
        (expect (plusp (ldb (byte 52 0) bits)))))))
