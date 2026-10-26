(in-package :cl-cc/binary)

;;; ------------------------------------------------------------
;;; ELF64 Constants
;;; ------------------------------------------------------------

(defconstant +elf-magic-0+ #x7f)

(defconstant +elf-magic-1+ #x45)

(defconstant +elf-magic-2+ #x4c)

(defconstant +elf-magic-3+ #x46)

(defconstant +elf-class-64+    2)

(defconstant +elf-data-lsb+    1)

(defconstant +elf-version-cur+ 1)

(defconstant +elf-osabi-none+  0)

(defconstant +elf-type-rel+    1)

(defconstant +elf-type-exec+   2)

(defconstant +elf-type-dyn+    3)

(defconstant +elf-machine-x86-64+ #x3e)

(defconstant +elf-machine-aarch64+ #xB7)

;;; Section header types
(defconstant +sht-null+     0)

(defconstant +sht-progbits+ 1)

(defconstant +sht-symtab+   2)

(defconstant +sht-strtab+   3)

(defconstant +sht-rela+     4)

(defconstant +sht-dynamic+  6)

(defconstant +sht-nobits+   8)

(defconstant +sht-dynsym+   11)

;;; Section header flags
(defconstant +shf-write+      1)

(defconstant +shf-alloc+      2)

(defconstant +shf-execinstr+  4)

(defconstant +shf-merge+      #x10)

(defconstant +shf-strings+    #x20)

(defconstant +shf-compressed+ #x800)

;;; Compression algorithms for Elf64_Chdr.
(defconstant +elfcompress-zlib+ 1)

;;; Symbol binding
(defconstant +stb-local+  0)

(defconstant +stb-global+ 1)

(defconstant +stb-weak+   2)

;;; Symbol type
(defconstant +stt-notype+  0)

(defconstant +stt-object+  1)

(defconstant +stt-func+    2)

(defconstant +stt-section+ 3)

(defconstant +stt-file+    4)

;;; Relocation types (System V AMD64 ABI §4.4)
(defconstant +r-x86-64-none+      0)

(defconstant +r-x86-64-64+        1)

(defconstant +r-x86-64-pc32+      2)

(defconstant +r-x86-64-got32+     3)

(defconstant +r-x86-64-plt32+     4)

(defconstant +r-x86-64-copy+      5)

(defconstant +r-x86-64-glob-dat+  6)

(defconstant +r-x86-64-jump-slot+ 7)

(defconstant +r-x86-64-relative+  8)

(defconstant +r-x86-64-gotpcrel+  9)

(defconstant +r-x86-64-32+       10)

(defconstant +r-x86-64-32s+      11)

;;; Program header types (FR-291: ELF executable generation)
(defconstant +pt-null+    0)

(defconstant +pt-load+    1)

(defconstant +pt-dynamic+ 2)

(defconstant +pt-interp+  3)

(defconstant +pt-note+    4)

(defconstant +pt-phdr+    6)

(defconstant +pt-gnu-stack+ #x6474e551)

(defconstant +pt-gnu-relro+ #x6474e552)

;;; Dynamic section tags
(defconstant +dt-null+    0)

(defconstant +dt-needed+  1)

(defconstant +dt-strtab+  5)

(defconstant +dt-symtab+  6)

(defconstant +dt-rela+    7)

(defconstant +dt-relasz+  8)

(defconstant +dt-relaent+ 9)

(defconstant +dt-strsz+   10)

(defconstant +dt-syment+  11)

(defconstant +dt-jmprel+  23)

(defconstant +dt-pltrelsz+ 2)

(defconstant +dt-pltrel+  20)

(defconstant +dt-flags+   30)

(defconstant +df-bind-now+ #x8)

;;; Program header flags
(defconstant +pf-x+ 1)

(defconstant +pf-w+ 2)

(defconstant +pf-r+ 4)

;;; ELF64 program header size
(defconstant +elf64-phdr-size+ 56)

(defconstant +elf-page-size+ #x1000)

(defconstant +elf64-exec-base+ #x400000)

(defparameter +elf64-default-interpreter+ "/lib64/ld-linux-x86-64.so.2")

;;; ELF64 structure sizes (bytes)
(defconstant +elf64-ehdr-size+ 64)

(defconstant +elf64-shdr-size+ 64)

(defconstant +elf64-sym-size+  24)

(defconstant +elf64-rela-size+ 24)
