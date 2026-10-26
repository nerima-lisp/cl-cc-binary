;;;; t/macho-buffer-test.lisp — Binary buffer operation tests
;;;;
;;;; Tests for: binary buffer write/read, alignment, string conversion,
;;;; serialization primitives (macho-buffer.lisp).

(in-package :cl-cc-binary/test)

(describe "Binary buffer operations and serialization primitives"

  (describe "make-binary-buffer / write / read operations"
    (it "returns an adjustable buffer with fill-pointer 0"
      (let ((buf (cl-cc/binary::make-binary-buffer 256)))
        (expect (typep buf '(array (unsigned-byte 8) (*))) :to-be-truthy)
        (expect (array-has-fill-pointer-p buf) :to-be-truthy)
        (expect (zerop (length buf)))))

    (it "appends a byte on write-u8"
      (let ((buf (cl-cc/binary::make-binary-buffer 16)))
        (cl-cc/binary::binary-buffer-write-u8 buf #xAB)
        (expect (= (length buf) 1))
        (expect (= (aref buf 0) #xAB))
        (cl-cc/binary::binary-buffer-write-u8 buf #x00)
        (cl-cc/binary::binary-buffer-write-u8 buf #xFF)
        (expect (= (length buf) 3))
        (expect (= (aref buf 1) #x00))
        (expect (= (aref buf 2) #xFF))))

    (it "appends two little-endian bytes on write-u16le"
      (let ((buf (cl-cc/binary::make-binary-buffer 16)))
        (cl-cc/binary::binary-buffer-write-u16le buf #xABCD)
        (expect (= (length buf) 2))
        (expect (= (aref buf 0) #xCD))
        (expect (= (aref buf 1) #xAB))))

    (it "appends four little-endian bytes on write-u32le"
      (let ((buf (cl-cc/binary::make-binary-buffer 16)))
        (cl-cc/binary::binary-buffer-write-u32le buf #xDEADBEEF)
        (expect (= (length buf) 4))
        (expect (= (aref buf 0) #xEF))
        (expect (= (aref buf 1) #xBE))
        (expect (= (aref buf 2) #xAD))
        (expect (= (aref buf 3) #xDE))))

    (it "appends eight little-endian bytes on write-u64le"
      (let ((buf (cl-cc/binary::make-binary-buffer 16)))
        (cl-cc/binary::binary-buffer-write-u64le buf #x0123456789ABCDEF)
        (expect (= (length buf) 8))
        (expect (= (aref buf 0) #xEF))
        (expect (= (aref buf 1) #xCD))
        (expect (= (aref buf 2) #xAB))
        (expect (= (aref buf 3) #x89))
        (expect (= (aref buf 4) #x67))
        (expect (= (aref buf 5) #x45))
        (expect (= (aref buf 6) #x23))
        (expect (= (aref buf 7) #x01))))

    (it "fills N zero bytes on write-pad"
      (let ((buf (cl-cc/binary::make-binary-buffer 16))
            (pad-count 5))
        (cl-cc/binary::binary-buffer-write-pad buf pad-count)
        (expect (= (length buf) pad-count))
        (dotimes (i pad-count)
          (expect (zerop (aref buf i))))))

    (it "copies all elements when writing bytes from a vector"
      (let ((buf (cl-cc/binary::make-binary-buffer 16))
            (data #(1 2 3 4 5)))
        (cl-cc/binary::binary-buffer-write-bytes buf data)
        (expect (= (length buf) 5))
        (dotimes (i 5)
          (expect (= (aref buf i) (aref data i))))))

    (it "copies all elements when writing bytes from a list"
      (let ((buf (cl-cc/binary::make-binary-buffer 16))
            (data '(10 20 30)))
        (cl-cc/binary::binary-buffer-write-bytes buf data)
        (expect (= (length buf) 3))
        (expect (= (aref buf 0) 10))
        (expect (= (aref buf 1) 20))
        (expect (= (aref buf 2) 30))))

    (it "returns a copy with the same contents from binary-buffer-to-array"
      (let ((buf (cl-cc/binary::make-binary-buffer 16)))
        (cl-cc/binary::binary-buffer-write-u8 buf 42)
        (cl-cc/binary::binary-buffer-write-u8 buf 99)
        (let ((copy (cl-cc/binary::binary-buffer-to-array buf)))
          (expect (= (length copy) 2))
          (expect (= (aref copy 0) 42))
          (expect (= (aref copy 1) 99))))))

  (describe "byte-buffer CLOS wrapper"
    (it "creates an empty byte-buffer and appends via buffer-write-byte"
      (let ((bb (cl-cc/binary::make-byte-buffer 64)))
        (cl-cc/binary::buffer-write-byte bb #x7F)
        (let ((data (cl-cc/binary::buffer-get-bytes bb)))
          (expect (= (length data) 1))
          (expect (= (aref data 0) #x7F)))))

    (it "appends sequentially across multiple buffer-write-byte calls"
      (let ((bb (cl-cc/binary::make-byte-buffer 64)))
        (dotimes (i 10)
          (cl-cc/binary::buffer-write-byte bb i))
        (let ((data (cl-cc/binary::buffer-get-bytes bb)))
          (expect (= (length data) 10))
          (dotimes (i 10)
            (expect (= (aref data i) i))))))

    (it "writes correctly via buffer-write-bytes"
      (let ((bb (cl-cc/binary::make-byte-buffer 64)))
        (cl-cc/binary::buffer-write-bytes bb #(100 200 255))
        (let ((data (cl-cc/binary::buffer-get-bytes bb)))
          (expect (= (length data) 3))
          (expect (= (aref data 0) 100))
          (expect (= (aref data 1) 200))
          (expect (= (aref data 2) 255))))))

  (describe "utilities"
    (it-each ((16   8   16)
              (1024 256 1024)
              (9    8   16)
              (15   8   16)
              (129  128 256)
              (0    8   0)
              (42   1   42))
        "aligns ~A up to a multiple of ~A, producing ~A"
        (value alignment expected)
      (expect (= (cl-cc/binary::align-up value alignment) expected)))

    (it-property "align-up returns the smallest multiple of alignment that is >= value"
        ((value (gen-integer :min 0 :max 1000000))
         (alignment (gen-integer :min 1 :max 4096)))
      (let ((result (cl-cc/binary::align-up value alignment)))
        (expect (zerop (mod result alignment)))
        (expect (>= result value))
        (expect (< (- result alignment) value))))

    (it "converts each character to its ASCII code"
      (let ((bytes (cl-cc/binary::string-to-ascii-bytes "ABC")))
        (expect (= (length bytes) 3))
        (expect (= (aref bytes 0) (char-code #\A)))
        (expect (= (aref bytes 1) (char-code #\B)))
        (expect (= (aref bytes 2) (char-code #\C)))))

    (it "returns an empty vector for the empty string"
      (expect (zerop (length (cl-cc/binary::string-to-ascii-bytes ""))))))

  (describe "serialization primitives"
    (it "writes a uint32 in little-endian order"
      (let ((bb (cl-cc/binary::make-byte-buffer 16)))
        (cl-cc/binary::serialize-uint32-le #x12345678 bb)
        (let ((data (cl-cc/binary::buffer-get-bytes bb)))
          (expect (= (length data) 4))
          (expect (= (aref data 0) #x78))
          (expect (= (aref data 1) #x56))
          (expect (= (aref data 2) #x34))
          (expect (= (aref data 3) #x12)))))

    (it "writes a uint64 in little-endian order"
      (let ((bb (cl-cc/binary::make-byte-buffer 16)))
        (cl-cc/binary::serialize-uint64-le #xAABBCCDD00112233 bb)
        (let ((data (cl-cc/binary::buffer-get-bytes bb)))
          (expect (= (length data) 8))
          (expect (= (aref data 0) #x33))
          (expect (= (aref data 1) #x22))
          (expect (= (aref data 2) #x11))
          (expect (= (aref data 3) #x00))
          (expect (= (aref data 4) #xDD))
          (expect (= (aref data 5) #xCC))
          (expect (= (aref data 6) #xBB))
          (expect (= (aref data 7) #xAA)))))

    (it "writes all bytes from a simple-array via serialize-bytes"
      (let ((bb (cl-cc/binary::make-byte-buffer 16))
            (input (make-array 4 :element-type '(unsigned-byte 8) :initial-contents '(1 3 5 7))))
        (cl-cc/binary::serialize-bytes input bb)
        (let ((data (cl-cc/binary::buffer-get-bytes bb)))
          (expect (= (length data) 4))
          (dotimes (i 4)
            (expect (= (aref data i) (aref input i)))))))

    (it "writes exactly 16 bytes, null-padding shorter strings"
      (let ((bb (cl-cc/binary::make-byte-buffer 32)))
        (cl-cc/binary::serialize-string-16 "HI" bb)
        (let ((data (cl-cc/binary::buffer-get-bytes bb)))
          (expect (= (length data) 16))
          (expect (= (aref data 0) (char-code #\H)))
          (expect (= (aref data 1) (char-code #\I)))
          (dotimes (i 14)
            (expect (zerop (aref data (+ i 2))))))))))
