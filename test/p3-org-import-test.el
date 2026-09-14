;;; p3-org-import-test.el --- Tests for incoming Office conversion -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)

(defconst p3-org-import-test--config-directory
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defconst p3-org-import-test--libreoffice-pptx-fixture
  (expand-file-name "test/fixtures/libreoffice-incoming.pptx"
                    p3-org-import-test--config-directory)
  "Compact incoming PPTX fixture derived from a LibreOffice-generated deck.")

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
  (p3-org-import-test--with-temp-directory directory
    (let* ((source (expand-file-name "example.docx" directory))
           (paths (p3-office-import--docx-paths source)))
      (should (equal (plist-get paths :output)
                     (expand-file-name "example.org" directory)))
      (should (equal (plist-get paths :media-directory)
                     (expand-file-name "example-media" directory))))))

(ert-deftest p3-office-import-docx-arguments-use-content-recovery-contract ()
  (p3-org-import-test--with-temp-directory directory
    (let ((source (expand-file-name "example.docx" directory))
          (output (expand-file-name "example.org" directory))
          (media-directory (expand-file-name "example-media" directory)))
      (should
       (equal
        (p3-office-import--docx-arguments source output media-directory)
        (list "--from=docx"
              "--to=org"
              "--extract-media=example-media"
              source
              "-o"
              output))))))

(ert-deftest p3-office-import-docx-notice-is-durable-and-explicitly-lossy ()
  (p3-org-import-test--with-temp-directory directory
    (let* ((source (expand-file-name "incoming.docx" directory))
           (notice (p3-office-import--docx-notice source "")))
      (should (string-match-p "incoming\\.docx" notice))
      (should (string-match-p "potentially lossy" notice))
      (should (string-match-p "original DOCX" notice))
      (should (string-match-p "custom Word styles" notice))
      (should (string-match-p "review metadata" notice))
      (should (string-match-p "not retained" notice)))))

(ert-deftest p3-office-import-docx-retains-pandoc-stderr-diagnostics ()
  (p3-org-import-test--with-temp-directory directory
    (let ((source (expand-file-name "incoming.docx" directory)))
      (with-temp-file source
        (insert "placeholder"))
      (cl-letf (((symbol-function 'p3-org-export--pandoc-executable)
                 (lambda () "pandoc"))
                ((symbol-function 'process-file)
                 (lambda (_program _infile destination _display &rest args)
                   (let ((output (cadr (member "-o" args))))
                     (with-temp-file output
                       (insert "* Converted\n"))
                     (when (and (consp destination)
                                (stringp (cadr destination)))
                       (with-temp-file (cadr destination)
                         (insert "synthetic import warning\n"))))
                   0)))
        (let* ((output (p3-office-import-docx-run source))
               (contents (p3-org-import-test--contents output)))
          (should (string-match-p "synthetic import warning" contents)))))))

(ert-deftest p3-office-import-docx-rejects-non-docx-input ()
  (p3-org-import-test--with-temp-directory directory
    (should-error
     (p3-office-import-docx-run
      (expand-file-name "not-word.txt" directory))
     :type 'user-error)))

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
        (should (string-match-p "custom Word styles" contents))
        (should (string-match-p "review metadata" contents))
        (should (string-match-p "\\* Incoming report" contents))
        (should (string-match-p "First item" contents))
        (should (string-match-p "| Name" contents))
        (should (string-match-p "incoming-media" contents))
        (should-not (string-match-p (regexp-quote directory) contents))
        (should (file-directory-p media-directory))
        (should (directory-files-recursively media-directory "\\.png\\'"))))))

(ert-deftest p3-office-import-pandoc-input-format-detection-is-exact ()
  (cl-letf (((symbol-function 'p3-org-export--pandoc-executable)
             (lambda () "pandoc"))
            ((symbol-function 'process-file)
             (lambda (_program _infile destination _display &rest _args)
               (with-current-buffer destination
                 (insert "docx\nnot-pptx\npptx\nxlsx\n"))
               0)))
    (should (p3-office-import--pandoc-supports-input-format-p "pptx"))
    (should-not (p3-office-import--pandoc-supports-input-format-p "pdfx"))))

(ert-deftest p3-office-import-pandoc-input-format-probe-failure-is-actionable ()
  (cl-letf (((symbol-function 'p3-org-export--pandoc-executable)
             (lambda () "pandoc"))
            ((symbol-function 'process-file)
             (lambda (&rest _args) 17)))
    (let ((error
           (should-error
            (p3-office-import--pandoc-supports-input-format-p "pptx")
            :type 'user-error)))
      (should
       (string-match-p "Could not query Pandoc input formats.*status 17"
                       (error-message-string error))))))

(ert-deftest p3-office-import-pptx-default-paths-are-predictable ()
  (p3-org-import-test--with-temp-directory directory
    (let* ((source (expand-file-name "slides.pptx" directory))
           (paths (p3-office-import--pptx-paths source)))
      (should (equal (plist-get paths :output)
                     (expand-file-name "slides.org" directory)))
      (should (equal (plist-get paths :media-directory)
                     (expand-file-name "slides-media" directory))))))

(ert-deftest p3-office-import-pptx-arguments-use-content-recovery-contract ()
  (p3-org-import-test--with-temp-directory directory
    (let ((source (expand-file-name "slides.pptx" directory))
          (output (expand-file-name "slides.org" directory))
          (media-directory (expand-file-name "slides-media" directory)))
      (should
       (equal
        (p3-office-import--pptx-arguments source output media-directory)
        (list "--from=pptx"
              "--to=org"
              "--extract-media=slides-media"
              source
              "-o"
              output))))))

(ert-deftest p3-office-import-pptx-notice-is-durable-and-explicitly-lossy ()
  (p3-org-import-test--with-temp-directory directory
    (let* ((source (expand-file-name "incoming.pptx" directory))
           (notice (p3-office-import--pptx-notice source "")))
      (should (string-match-p "incoming\\.pptx" notice))
      (should (string-match-p "potentially lossy" notice))
      (should (string-match-p "original PPTX" notice))
      (should (string-match-p "slide geometry" notice))
      (should (string-match-p "speaker notes" notice))
      (should (string-match-p "charts" notice))
      (should (string-match-p "animations" notice))
      (should (string-match-p "not retained" notice)))))

(ert-deftest p3-office-import-pptx-requires-pandoc-reader-support ()
  (p3-org-import-test--with-temp-directory directory
    (let ((source (expand-file-name "incoming.pptx" directory)))
      (with-temp-file source
        (insert "placeholder"))
      (cl-letf (((symbol-function 'p3-org-export--pandoc-executable)
                 (lambda () "pandoc"))
                ((symbol-function 'p3-office-import--pandoc-supports-input-format-p)
                 (lambda (_format) nil)))
        (let ((error
               (should-error (p3-office-import-pptx-run source)
                             :type 'user-error)))
          (should
           (string-match-p "Pandoc 3\\.8\\.3 or newer"
                           (error-message-string error))))))))

(ert-deftest p3-office-import-pptx-runs-libreoffice-deck-through-pandoc ()
  (skip-unless
   (and (executable-find "pandoc")
        (p3-office-import--pandoc-supports-input-format-p "pptx")))
  (p3-org-import-test--with-temp-directory directory
    (let* ((source (expand-file-name "incoming.pptx" directory))
           (default-directory directory))
      (copy-file p3-org-import-test--libreoffice-pptx-fixture source)
      (let* ((output (p3-office-import-pptx-run source))
             (paths (p3-office-import--pptx-paths source))
             (media-directory (plist-get paths :media-directory))
             (contents (p3-org-import-test--contents output)))
        (should (equal output (expand-file-name "incoming.org" directory)))
        (should (string-match-p "potentially lossy" contents))
        (should (string-match-p "External deck" contents))
        (should (string-match-p "Alpha point" contents))
        (should (string-match-p "Beta point" contents))
        (should (string-match-p "Image slide" contents))
        (should (string-match-p "incoming-media" contents))
        (should-not (string-match-p (regexp-quote directory) contents))
        (should (file-directory-p media-directory))
        (should (directory-files-recursively media-directory "\\.png\\'"))))))

(provide 'p3-org-import-test)

;;; p3-org-import-test.el ends here
