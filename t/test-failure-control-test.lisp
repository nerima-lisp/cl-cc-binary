(in-package :cl-cc-binary/test)

(describe "test failure propagation control"
  (it "fails when an assertion is false"
    (expect nil :to-be t)))
