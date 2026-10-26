(in-package #:cl-cc/binary/macho/test)

(describe-each ((:x86-64) (:arm64))
    "make-mach-o-builder for ~A"
    (arch)
  (it "sets the header cputype and cpusubtype for the requested architecture"
    (let* ((builder (cl-cc/binary/macho:make-mach-o-builder arch))
           (header (cl-cc/binary/macho::mach-o-builder-header builder))
           (expected-cputype (ecase arch
                               (:x86-64 cl-cc/binary/macho:+cpu-type-x86-64+)
                               (:arm64 cl-cc/binary/macho:+cpu-type-arm64+)))
           (expected-cpusubtype (ecase arch
                                  (:x86-64 cl-cc/binary/macho:+cpu-subtype-x86-64-all+)
                                  (:arm64 cl-cc/binary/macho:+cpu-subtype-arm64-all+))))
      (expect (cl-cc/binary/macho::mach-header-cputype header) :to-be expected-cputype)
      (expect (cl-cc/binary/macho::mach-header-cpusubtype header) :to-be expected-cpusubtype))))
