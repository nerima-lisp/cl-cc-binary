(in-package #:cl-cc/binary/dwarf/test)

(defun dwo-test-uint (bytes offset width)
  (loop for i below width sum (ash (aref bytes (+ offset i)) (* 8 i))))

(it-sequential "dwo-skeleton-header-die-and-abbreviation"
  (multiple-value-bind (info abbrev)
      (cl-cc/binary/dwarf::build-dwarf-skeleton-cu "unit.dwo" :dwo-id #x0123456789abcdef :comp-dir "src")
    (expect (dwo-test-uint info 0 4) :to-equal (- (length info) 4))
    (expect (dwo-test-uint info 4 2) :to-equal 5)
    (expect (aref info 6) :to-equal 4)
    (expect (aref info 7) :to-equal 8)
    (expect (dwo-test-uint info 8 4) :to-equal 0)
    (expect (dwo-test-uint info 12 8) :to-equal #x0123456789abcdef)
    (expect (coerce (subseq info 20) 'list)
            :to-equal '(1 117 110 105 116 46 100 119 111 0 115 114 99 0))
    (expect (coerce abbrev 'list)
            :to-equal '(1 #x4a 0 #x76 8 #x1b 8 #x53 #x19 0 0 0))))

(it-sequential "dwo-crc32-ieee-known-vectors"
  (expect (cl-cc/binary/dwarf::dwarf-crc32 #()) :to-equal 0)
  (expect (cl-cc/binary/dwarf::dwarf-crc32 #(49 50 51 52 53 54 55 56 57)) :to-equal #xcbf43926)
  (expect (cl-cc/binary/dwarf::dwarf-crc32 #(0)) :to-equal #xd202ef8d))

(it-sequential "dwo-debuglink-basename-padding-and-whole-file-crc"
  (let ((link (cl-cc/binary/dwarf::build-gnu-debuglink-section "dir/unit.debug" #(49 50 51 52 53 54 55 56 57))))
    (expect (coerce link 'list)
            :to-equal '(117 110 105 116 46 100 101 98 117 103 0 0 #x26 #x39 #xf4 #xcb))
    (expect (mod (- (length link) 4) 4) :to-equal 0))
  (expect (coerce (cl-cc/binary/dwarf::build-gnu-debuglink-section "a" #()) 'list)
          :to-equal '(97 0 0 0 0 0 0 0)))

