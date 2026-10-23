(in-package :cl-cc-binary/test)

(describe "orphan test control"
  (it "is intentionally not registered in the test system"
    (expect t :to-be-truthy)))
