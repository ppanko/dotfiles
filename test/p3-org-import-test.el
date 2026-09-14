;;; p3-org-import-test.el --- Tests for incoming Office conversion -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)

(defconst p3-org-import-test--config-directory
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path
             (expand-file-name "lisp" p3-org-import-test--config-directory))

(require 'p3-org-export)

(defmacro p3-org-import-test--with-temp-directory (binding &rest body)
  "Bind BINDING to a temporary directory while evaluating BODY."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,binding (make-temp-file "p3-org-import-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,binding t))))

(defun p3-org-import-test--contents (path)
  "Return text contents of PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(defun p3-org-import-test--write-png (path)
  "Write a tiny valid PNG image to PATH."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert
     (base64-decode-string
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII="))
    (let ((coding-system-for-write 'binary))
      (write-region (point-min) (point-max) path nil 'silent))))

(ert-deftest p3-office-import-docx-default-paths-are-predictable ()
  (let* ((source "/tmp/example.docx")
         (paths (p3-office-import--docx-paths source)))
    (should (equal (plist-get paths :output) "/tmp/example.org"))
    (should (equal (plist-get paths :media-directory)
                   "/tmp/example-media"))))

(ert-deftest p3-office-import-docx-arguments-preserve-review-information ()
  (should
   (equal
    (p3-office-import--docx-arguments
     "/tmp/example.docx"
     "/tmp/example.org"
     "/tmp/example-media")
    '("--from=docx+styles"
      "--to=org"
      "--track-changes=all"
      "--extract-media=example-media"
      "/tmp/example.docx"
      "-o"
      "/tmp/example.org"))))

(ert-deftest p3-office-import-docx-notice-is-durable-and-explicitly-lossy ()
  (let ((notice
         (p3-office-import--docx-notice "/tmp/incoming.docx" "")))
    (should (string-match-p "incoming\\.docx" notice))
    (should (string-match-p "potentially lossy" notice))
    (should (string-match-p "original DOCX" notice))))

(ert-deftest p3-office-import-docx-rejects-non-docx-input ()
  (should-error
   (p3-office-import-docx-run "/tmp/not-word.txt")
   :type 'user-error))

(ert-deftest p3-office-import-docx-refuses-to-overwrite-existing-output ()
  (p3-org-import-test--with-temp-directory directory
    (let* ((source (expand-file-name "incoming.docx" directory))
           (output (expand-file-name "incoming.org" directory))
           (sentinel "keep me"))
      (with-temp-file source
        (insert "not a real docx"))
      (with-temp-file output
        (insert sentinel))
      (should-error (p3-office-import-docx-run source) :type 'user-error)
      (should (equal (p3-org-import-test--contents output) sentinel)))))

(ert-deftest p3-office-import-docx-runs-realistic-document-through-pandoc ()
  (skip-unless (executable-find "pandoc"))
  (p3-org-import-test--with-temp-directory directory
    (let* ((markdown (expand-file-name "source.md" directory))
           (figure (expand-file-name "example.png" directory))
           (source (expand-file-name "incoming.docx" directory))
           (default-directory directory))
      (p3-org-import-test--write-png figure)
      (with-temp-file markdown
        (insert
         "# Incoming report\n\n"
         "A paragraph with **bold** text.\n\n"
         "- First item\n"
         "- Second item\n\n"
         "| Name | Value |\n"
         "|---|---:|\n"
         "| A | 1 |\n\n"
         "![Example figure](example.png)\n"))
      (should
       (zerop
        (call-process "pandoc" nil nil nil
                      "--from=markdown" "--to=docx"
                      markdown "-o" source)))
      (let* ((output (p3-office-import-docx-run source))
             (paths (p3-office-import--docx-paths source))
             (media-directory (plist-get paths :media-directory))
             (contents (p3-org-import-test--contents output)))
        (should (equal output (expand-file-name "incoming.org" directory)))
        (should (string-match-p "potentially lossy" contents))
        (should (string-match-p "\\* Incoming report" contents))
        (should (string-match-p "First item" contents))
        (should (string-match-p "| Name" contents))
        (should (string-match-p "incoming-media" contents))
        (should-not (string-match-p (regexp-quote directory) contents))
        (should (file-directory-p media-directory))
        (should (directory-files-recursively media-directory "\\.png\\'"))))))

(provide 'p3-org-import-test)

;;; p3-org-import-test.el ends here
