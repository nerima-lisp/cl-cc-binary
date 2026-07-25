;;;; tests/got-plt-tests.lisp — GOT/PLT section generation tests
;;;;
;;;; Tests for: add-plt-stubs, add-got-entries, add-dynamic-relocations,
;;;; bind-now-mode, setup-got-plt (got-plt.lisp).
;;;;
;;;; PLT layout (System V AMD64 ABI):
;;;;   PLT[0]  16 bytes: resolver stub  (ff 35 ... ff 25 ...)
;;;;   PLT[n]  16 bytes each: jmpq *GOT[n+3](%rip); push $n; jmpq PLT[0]
;;;;
;;;; GOT layout (.got.plt):
;;;;   GOT[0..2]  reserved (3 × 8 bytes = 24 bytes)
;;;;   GOT[3+i]   per-symbol slot (8 bytes each), filled lazily by ld.so

(in-package :cl-cc-binary/test)

(describe "GOT/PLT section byte generation"

  (describe "bind-now-mode"
    (it "returns the DF_BIND_NOW flag value (#x8)"
      (expect (cl-cc/binary::bind-now-mode) :to-be cl-cc/binary::+df-bind-now+)))

  (describe "add-plt-stubs"
    (it "returns only the 16-byte PLT[0] resolver when there are no symbols"
      (expect (= (length (cl-cc/binary::add-plt-stubs '())) 16)))

    (it "returns PLT[0] plus one 16-byte entry for a single symbol"
      (expect (= (length (cl-cc/binary::add-plt-stubs '("foo"))) 32)))

    (it-each ((0) (1) (2) (5) (10))
        "returns 16*(1+N) bytes for N=~A symbols"
        (n)
      (let ((syms (loop repeat n collect "sym")))
        (expect (= (length (cl-cc/binary::add-plt-stubs syms)) (* 16 (1+ n))))))

    (it "starts PLT[0] with the pushq (%rip+disp32) opcode bytes ff 35"
      (let ((plt (cl-cc/binary::add-plt-stubs '())))
        (expect (= (aref plt 0) #xff))
        (expect (= (aref plt 1) #x35))))

    (it "starts PLT[1] with the jmpq *GOT(%rip) opcode bytes ff 25"
      (let ((plt (cl-cc/binary::add-plt-stubs '("foo"))))
        (expect (= (aref plt 16) #xff))
        (expect (= (aref plt 17) #x25))))

    (it "encodes push $0 at offset 22 for the first symbol"
      (let* ((plt (cl-cc/binary::add-plt-stubs '("foo")))
             (push-opcode (aref plt 22))
             (index-lo    (aref plt 23)))
        (expect (= push-opcode #x68))
        (expect (= index-lo    0))))

    (it "encodes push $1 for the second symbol"
      (let* ((plt (cl-cc/binary::add-plt-stubs '("foo" "bar")))
             (push-opcode (aref plt 38))   ; 16 + 16 + 6 = 38
             (index-lo    (aref plt 39)))
        (expect (= push-opcode #x68))
        (expect (= index-lo    1)))))

  (describe "add-got-entries"
    (it "reserves 3 slots (24 bytes) for zero symbols"
      (expect (= (length (cl-cc/binary::add-got-entries 0)) 24)))

    (it-each ((0) (1) (2) (5) (10))
        "returns (3+N) × 8 bytes for N=~A symbols"
        (n)
      (expect (= (length (cl-cc/binary::add-got-entries n)) (* 8 (+ 3 n)))))

    (it "initializes all slots to zero, filled lazily by ld.so"
      (let ((got (cl-cc/binary::add-got-entries 2)))
        (expect (every #'zerop got) :to-be-truthy))))

  (describe "add-dynamic-relocations"
    (it "returns an empty vector for no symbols"
      (expect (= (length (cl-cc/binary::add-dynamic-relocations '() 0)) 0)))

    (it "emits one 24-byte Elf64_Rela for one symbol"
      (expect (= (length (cl-cc/binary::add-dynamic-relocations '("foo") 0)) 24)))

    (it-each ((1) (2) (5))
        "emits N × 24-byte Elf64_Rela entries for N=~A symbols"
        (n)
      (let ((syms (loop repeat n collect "sym")))
        (expect (= (length (cl-cc/binary::add-dynamic-relocations syms 0)) (* 24 n)))))

    (it "sets r_info low 32 bits to R_X86_64_JUMP_SLOT (7) for the first symbol"
      (let* ((rela (cl-cc/binary::add-dynamic-relocations '("foo") 0))
             (r-type (logior (aref rela 8)
                             (ash (aref rela 9)  8)
                             (ash (aref rela 10) 16)
                             (ash (aref rela 11) 24))))
        (expect r-type :to-be cl-cc/binary::+r-x86-64-jump-slot+)))

    (it "targets GOT[3] = got-plt-addr + 24 as r_offset for symbol 0"
      (let* ((got-base #x1000)
             (rela (cl-cc/binary::add-dynamic-relocations '("foo") got-base))
             (r-offset (logior (aref rela 0)
                               (ash (aref rela 1) 8)
                               (ash (aref rela 2) 16)
                               (ash (aref rela 3) 24))))
        (expect (= r-offset (+ got-base 24))))))

  (describe "setup-got-plt (integration)"
    (it "returns exactly four values"
      (multiple-value-bind (plt got rela bind-now)
          (cl-cc/binary::setup-got-plt '("foo" "bar"))
        (expect (typep plt  '(simple-array (unsigned-byte 8) (*))) :to-be-truthy)
        (expect (typep got  '(simple-array (unsigned-byte 8) (*))) :to-be-truthy)
        (expect (typep rela '(simple-array (unsigned-byte 8) (*))) :to-be-truthy)
        (expect bind-now :to-be-truthy)))

    (it "produces sizes consistent with per-function invariants for N=3 symbols"
      (let ((syms '("malloc" "free" "puts")))
        (multiple-value-bind (plt got rela _)
            (cl-cc/binary::setup-got-plt syms)
          (declare (ignore _))
          (expect (= (length plt)  (* 16 (1+ (length syms)))))
          (expect (= (length got)  (* 8  (+ 3 (length syms)))))
          (expect (= (length rela) (* 24 (length syms)))))))))
