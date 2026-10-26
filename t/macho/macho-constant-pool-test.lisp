(in-package #:cl-cc/binary/macho/test)

(defun %constpool-ub8 (bytes) (make-array (length bytes) :element-type '(unsigned-byte 8) :initial-contents bytes))

(describe "Mach-O __DATA_CONST constant pool" (it "keeps one copy of repeated immutable __DATA_CONST payloads"
    (let ((builder (cl-cc/binary/macho:make-mach-o-builder :x86-64)))
      (cl-cc/binary/macho:add-data-const-segment builder (%constpool-ub8 '(10 20 30)))
      (cl-cc/binary/macho:add-data-const-segment builder (%constpool-ub8 '(1 2)))
      (cl-cc/binary/macho:add-data-const-segment builder (%constpool-ub8 '(10 20 30)))
      (let* ((segment (find "__DATA_CONST" (cl-cc/binary/macho::mach-o-builder-segments builder)
                            :key #'cl-cc/binary/macho:segment-command-segname
                            :test #'string=))
             (payload (cl-cc/binary/macho::segment-command-payload segment)))
        (expect segment :to-be-truthy)
        (expect (= (length payload) 5))
        (expect (= (aref payload 0) 10))
        (expect (= (aref payload 1) 20))
        (expect (= (aref payload 2) 30))
        (expect (= (aref payload 3) 1))
        (expect (= (aref payload 4) 2))))))
