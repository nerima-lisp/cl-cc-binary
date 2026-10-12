(in-package :cl-cc/binary)

(defun %dwo-write-string (buffer string)
  (check-type string string)
  (loop for character across string for code = (char-code character) do
    (when (or (zerop code) (<= #xd800 code #xdfff) (> code #x10ffff))
      (error "DWARF strings require non-NUL Unicode scalar values."))
    (cond
      ((< code #x80) (binary-buffer-write-u8 buffer code))
      ((< code #x800)
       (binary-buffer-write-u8 buffer (logior #xc0 (ash code -6)))
       (binary-buffer-write-u8 buffer (logior #x80 (logand code #x3f))))
      ((< code #x10000)
       (binary-buffer-write-u8 buffer (logior #xe0 (ash code -12)))
       (binary-buffer-write-u8 buffer (logior #x80 (logand (ash code -6) #x3f)))
       (binary-buffer-write-u8 buffer (logior #x80 (logand code #x3f))))
      (t
       (binary-buffer-write-u8 buffer (logior #xf0 (ash code -18)))
       (binary-buffer-write-u8 buffer (logior #x80 (logand (ash code -12) #x3f)))
       (binary-buffer-write-u8 buffer (logior #x80 (logand (ash code -6) #x3f)))
       (binary-buffer-write-u8 buffer (logior #x80 (logand code #x3f))))))
  (binary-buffer-write-u8 buffer 0))

(defun %dwo-unit (type dwo-id die)
  (check-type dwo-id (unsigned-byte 64))
  (let ((length (+ 16 (length die))))
    ;; DWARF32 reserves initial-length values >= 0xfffffff0.
    (when (>= length #xfffffff0)
      (error 'value-out-of-range :value length :bits 32 :signed-p nil))
    (with-byte-buffer (buffer)
      (binary-buffer-write-u32le buffer length)
      (binary-buffer-write-u16le buffer 5)
      (binary-buffer-write-u8 buffer type)
      (binary-buffer-write-u8 buffer 8)
      (binary-buffer-write-u32le buffer 0)
      (binary-buffer-write-u64le buffer dwo-id)
      (binary-buffer-write-bytes buffer die))))

(defun build-dwarf-skeleton-cu (dwo-name &key dwo-id (comp-dir "."))
  "Return DWARF5 skeleton .debug_info and .debug_abbrev bytes as two values.
The caller must share DWO-ID with BUILD-DWO-FILE. This metadata has no code
ranges, child DIEs or compiler integration. DWO-NAME is a lookup filename."
  (values
   (%dwo-unit 4 dwo-id
              (with-byte-buffer (die)
                (binary-buffer-write-u8 die 1)
                (%dwo-write-string die dwo-name)
                (%dwo-write-string die comp-dir)))
   ;; DW_TAG_skeleton_unit, no children; dwo_name/string, comp_dir/string,
   ;; use_UTF8/flag_present. Attribute and abbreviation lists terminate separately.
   (make-array 12 :element-type '(unsigned-byte 8)
               :initial-contents '(1 #x4a 0 #x76 8 #x1b 8 #x53 #x19 0 0 0))))

(defun %dwo-line-table (source-name comp-dir)
  (let ((header
          (with-byte-buffer (buffer)
            (binary-buffer-write-bytes
             buffer '(1 1 1 #xfb 14 13 0 1 1 1 1 0 0 0 1 0 0 1))
            ;; Directory path/string, followed by one directory.
            (binary-buffer-write-bytes buffer '(1 1 8 1))
            (%dwo-write-string buffer comp-dir)
            ;; File path/string and directory_index/udata; v5 indices start at 0.
            (binary-buffer-write-bytes buffer '(2 1 8 2 #x0f 1))
            (%dwo-write-string buffer source-name)
            (binary-buffer-write-u8 buffer 0))))
    (with-byte-buffer (buffer)
      (binary-buffer-write-u32le buffer (+ 8 (length header)))
      (binary-buffer-write-u16le buffer 5)
      (binary-buffer-write-u8 buffer 8)
      (binary-buffer-write-u8 buffer 0)
      (binary-buffer-write-u32le buffer (length header))
      (binary-buffer-write-bytes buffer header))))

(defun %dwo-elf64 (sections)
  ;; The ordinary ELF builder owns code/symbol sections. This container only
  ;; lays out the named, non-allocated metadata sections supplied here.
  (let* ((strings (make-strtab))
         (name-offsets (mapcar (lambda (section) (strtab-add strings (car section))) sections))
         (strings-name (strtab-add strings ".shstrtab"))
         (payloads (append (mapcar #'cdr sections) (list (strtab-bytes strings))))
         (offset 64)
         (offsets (mapcar (lambda (bytes) (prog1 offset (incf offset (length bytes)))) payloads))
         (shoff (align-up offset 8))
         (count (+ 2 (length sections))))
    (with-byte-buffer (buffer)
      (binary-buffer-write-bytes buffer '(#x7f #x45 #x4c #x46 2 1 1 0 0))
      (binary-buffer-write-pad buffer 7)
      (binary-buffer-write-u16le buffer +elf-type-rel+)
      (binary-buffer-write-u16le buffer +elf-machine-x86-64+)
      (binary-buffer-write-u32le buffer +elf-version-cur+)
      (binary-buffer-write-u64le buffer 0)
      (binary-buffer-write-u64le buffer 0)
      (binary-buffer-write-u64le buffer shoff)
      (binary-buffer-write-u32le buffer 0)
      (binary-buffer-write-u16le buffer 64)
      (binary-buffer-write-u16le buffer 0)
      (binary-buffer-write-u16le buffer 0)
      (binary-buffer-write-u16le buffer 64)
      (binary-buffer-write-u16le buffer count)
      (binary-buffer-write-u16le buffer (1- count))
      (dolist (bytes payloads) (binary-buffer-write-bytes buffer bytes))
      (binary-buffer-write-pad buffer (- shoff (length buffer)))
      (binary-buffer-write-pad buffer 64)
      (loop for bytes in payloads for position in offsets
            for name in (append name-offsets (list strings-name))
            for index from 1 do
        (elf64-write-shdr buffer name
                          (if (= index (1- count)) +sht-strtab+ +sht-progbits+)
                          0 position (length bytes) 0 0 1 0)))))

(defun build-dwo-file (source-name &key dwo-id (producer "cl-cc") (comp-dir "."))
  "Return a little-endian x86-64 ELF64 ET_REL metadata-only DWO file.
DWO-ID must match the skeleton's ID. The split CU has no child DIEs or code
mapping; its v5 line section contains a file table, not line instructions."
  (let ((info (%dwo-unit 5 dwo-id
                         (with-byte-buffer (die)
                           (binary-buffer-write-u8 die 1)
                           (%dwo-write-string die source-name)
                           (%dwo-write-string die producer))))
        (abbrev (make-array 12 :element-type '(unsigned-byte 8)
                            :initial-contents '(1 #x11 0 3 8 #x25 8 #x53 #x19 0 0 0))))
    (%dwo-elf64 (list (cons ".debug_info.dwo" info)
                      (cons ".debug_abbrev.dwo" abbrev)
                      (cons ".debug_line.dwo" (%dwo-line-table source-name comp-dir))))))

(defun dwarf-crc32 (bytes)
  (let ((crc #xffffffff))
    (loop for byte across bytes do
      (check-type byte (unsigned-byte 8))
      (setf crc (logxor crc byte))
      (dotimes (i 8)
        (setf crc (logxor (ash crc -1) (if (oddp crc) #xedb88320 0)))))
    (logxor crc #xffffffff)))

(defun build-gnu-debuglink-section (filename file-bytes)
  "Return basename/NUL/pad4/IEEE CRC32 for a separate debug file.
This GNU debuglink mechanism does not replace the skeleton/split DWO ID."
  (let ((basename (file-namestring (pathname filename))))
    (when (zerop (length basename)) (error "GNU debuglink requires a basename."))
    (with-byte-buffer (buffer)
      (%dwo-write-string buffer basename)
      (binary-buffer-write-pad buffer (mod (- (length buffer)) 4))
      (binary-buffer-write-u32le buffer (dwarf-crc32 file-bytes)))))
