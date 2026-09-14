;;; p3-office-preview-test.el --- Tests for Office preview workflow -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)

(defconst p3-office-preview-test--config-directory
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defconst p3-office-preview-test--pptx-fixture
  (expand-file-name "test/fixtures/libreoffice-incoming.pptx"
                    p3-office-preview-test--config-directory)
  "LibreOffice-generated PPTX fixture used by preview integration tests.")

(add-to-list 'load-path
             (expand-file-name "lisp" p3-office-preview-test--config-directory))

(require 'p3-org-export)
(require 'p3-office-preview)

(defmacro p3-office-preview-test--with-temp-directory (binding &rest body)
  "Bind BINDING to a temporary directory while evaluating BODY."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,binding (make-temp-file "p3-office-preview-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,binding t))))

(defun p3-office-preview-test--pdf-p (path)
  "Return non-nil when PATH starts with the PDF signature."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally path nil 0 4)
    (equal (buffer-string) "%PDF")))

(ert-deftest p3-office-preview-libreoffice-uses-configured-program ()
  (let ((p3-office-libreoffice-program "custom-soffice"))
    (cl-letf (((symbol-function 'file-executable-p) (lambda (_path) nil))
              ((symbol-function 'executable-find)
               (lambda (name)
                 (when (equal name "custom-soffice")
                   "/resolved/custom-soffice"))))
      (should
       (equal (p3-office--libreoffice-executable)
              "/resolved/custom-soffice")))))

(ert-deftest p3-office-preview-libreoffice-windows-candidates-prefer-console-launcher ()
  (let ((candidates (p3-office--libreoffice-platform-candidates 'windows-nt)))
    (should
     (equal (car candidates)
            "C:/Program Files/LibreOffice/program/soffice.com"))
    (should
     (member "C:/Program Files/LibreOffice/program/soffice.exe" candidates))))

(ert-deftest p3-office-preview-libreoffice-windows-path-prefers-console-launcher ()
  (let ((p3-office-libreoffice-program nil))
    (cl-letf (((symbol-function 'executable-find)
               (lambda (name)
                 (cond
                  ((equal name "soffice.com") "C:/tools/soffice.com")
                  ((equal name "soffice.exe") "C:/tools/soffice.exe")
                  (t nil))))
              ((symbol-function 'file-executable-p) (lambda (_path) nil))
              ((symbol-function 'p3-office--libreoffice-platform-candidates)
               (lambda (&optional _platform) nil)))
      (should
       (equal (p3-office--libreoffice-executable)
              "C:/tools/soffice.com")))))

(ert-deftest p3-office-preview-pptx-arguments-render-with-isolated-impress-profile ()
  (let ((source "/tmp/slides.pptx")
        (output-directory "/tmp/render")
        (profile-url "file:///isolated-profile"))
    (should
     (equal
      (p3-office-preview--pptx-arguments
       source output-directory profile-url)
      (list "-env:UserInstallation=file:///isolated-profile"
            "--headless"
            "--nologo"
            "--nodefault"
            "--norestore"
            "--convert-to" "pdf:impress_pdf_Export"
            "--outdir" output-directory
            source)))))

(ert-deftest p3-office-preview-pptx-directories-separate-same-named-sources ()
  (let ((p3-office-preview-directory "/tmp/p3-preview-root"))
    (should-not
     (equal (p3-office-preview--pptx-directory "/tmp/a/slides.pptx")
            (p3-office-preview--pptx-directory "/tmp/b/slides.pptx")))))

(ert-deftest p3-office-preview-pptx-run-preserves-last-good-preview-on-failure ()
  (p3-office-preview-test--with-temp-directory directory
    (let* ((source (expand-file-name "slides.pptx" directory))
           (p3-office-preview-directory
            (expand-file-name "preview-cache" directory))
           (preview-directory
            (p3-office-preview--pptx-directory source))
           (preview (expand-file-name "slides.pdf" preview-directory))
           (sentinel "previous preview"))
      (with-temp-file source
        (insert "placeholder"))
      (make-directory preview-directory t)
      (with-temp-file preview
        (insert sentinel))
      (cl-letf (((symbol-function 'p3-office--libreoffice-executable)
                 (lambda () "soffice"))
                ((symbol-function 'process-file)
                 (lambda (&rest _args) 7)))
        (should-error (p3-office-preview-pptx-run source) :type 'user-error)
        (with-temp-buffer
          (insert-file-contents preview)
          (should (equal (buffer-string) sentinel)))))))

(ert-deftest p3-office-preview-pptx-run-rejects-missing-rendered-pdf ()
  (p3-office-preview-test--with-temp-directory directory
    (let* ((source (expand-file-name "slides.pptx" directory))
           (p3-office-preview-directory
            (expand-file-name "preview-cache" directory)))
      (with-temp-file source
        (insert "placeholder"))
      (cl-letf (((symbol-function 'p3-office--libreoffice-executable)
                 (lambda () "soffice"))
                ((symbol-function 'process-file)
                 (lambda (&rest _args) 0)))
        (let ((error
               (should-error (p3-office-preview-pptx-run source)
                             :type 'user-error)))
          (should
           (string-match-p "did not produce.*PDF"
                           (error-message-string error))))))))

(ert-deftest p3-office-preview-pptx-command-opens-rendered-pdf ()
  (let (opened)
    (cl-letf (((symbol-function 'p3-office-preview-pptx-run)
               (lambda (source)
                 (should (equal source "/tmp/slides.pptx"))
                 "/tmp/slides.pdf"))
              ((symbol-function 'p3-office-preview--open-pdf)
               (lambda (path)
                 (setq opened path))))
      (p3/office-preview-pptx "/tmp/slides.pptx")
      (should (equal opened "/tmp/slides.pdf")))))

(ert-deftest p3-office-preview-open-pdf-refreshes-an-existing-buffer ()
  (p3-office-preview-test--with-temp-directory directory
    (let* ((path (expand-file-name "preview.txt" directory))
           (buffer nil))
      (with-temp-file path
        (insert "old"))
      (setq buffer (find-file-noselect path))
      (unwind-protect
          (progn
            (with-temp-file path
              (insert "new"))
            (cl-letf (((symbol-function 'find-file-other-window)
                       (lambda (_path) buffer)))
              (p3-office-preview--open-pdf path))
            (with-current-buffer buffer
              (should (equal (buffer-string) "new"))))
        (when (buffer-live-p buffer)
          (set-buffer-modified-p nil)
          (kill-buffer buffer))))))

(ert-deftest p3-org-export-pptx-preview-renders-the-exported-artifact ()
  (let (rendered opened)
    (cl-letf (((symbol-function 'p3-org-export-run)
               (lambda (profile &optional _reference)
                 (should (eq profile 'pptx))
                 "/tmp/exported-deck.pptx"))
              ((symbol-function 'p3-office-preview-pptx-run)
               (lambda (source)
                 (setq rendered source)
                 "/tmp/exported-deck.pdf"))
              ((symbol-function 'p3-office-preview--open-pdf)
               (lambda (path)
                 (setq opened path))))
      (p3/org-export-pptx-preview)
      (should (equal rendered "/tmp/exported-deck.pptx"))
      (should (equal opened "/tmp/exported-deck.pdf")))))

(ert-deftest p3-office-preview-pptx-renders-real-libreoffice-deck ()
  (skip-unless
   (or (executable-find "soffice")
       (executable-find "libreoffice")))
  (p3-office-preview-test--with-temp-directory directory
    (let* ((source (expand-file-name "external-deck.pptx" directory))
           (p3-office-preview-directory
            (expand-file-name "preview-cache" directory)))
      (copy-file p3-office-preview-test--pptx-fixture source)
      (let ((preview (p3-office-preview-pptx-run source)))
        (should (file-exists-p preview))
        (should (> (file-attribute-size (file-attributes preview)) 0))
        (should (p3-office-preview-test--pdf-p preview))))))

(provide 'p3-office-preview-test)

;;; p3-office-preview-test.el ends here
