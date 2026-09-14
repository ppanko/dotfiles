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
  (let ((p3-office-libreoffice-program "/opt/libreoffice/program/soffice"))
    (cl-letf (((symbol-function 'file-executable-p)
               (lambda (path)
                 (equal path p3-office-libreoffice-program))))
      (should
       (equal (p3-office--libreoffice-executable)
              p3-office-libreoffice-program)))))

(ert-deftest p3-office-preview-libreoffice-discovers-windows-default ()
  (let ((p3-office-libreoffice-program nil)
        (system-type 'windows-nt))
    (cl-letf (((symbol-function 'executable-find) (lambda (_name) nil))
              ((symbol-function 'file-executable-p)
               (lambda (path)
                 (equal path
                        "C:/Program Files/LibreOffice/program/soffice.exe"))))
      (should
       (equal (p3-office--libreoffice-executable)
              "C:/Program Files/LibreOffice/program/soffice.exe")))))

(ert-deftest p3-office-preview-pptx-arguments-render-with-impress-filter ()
  (let ((source "/tmp/slides.pptx")
        (output-directory "/tmp/render"))
    (should
     (equal
      (p3-office-preview--pptx-arguments source output-directory)
      (list "--headless"
            "--nologo"
            "--nodefault"
            "--norestore"
            "--convert-to" "pdf:impress_pdf_Export"
            "--outdir" output-directory
            source)))))

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

(ert-deftest p3-office-preview-pptx-command-opens-rendered-pdf ()
  (let (opened)
    (cl-letf (((symbol-function 'p3-office-preview-pptx-run)
               (lambda (source)
                 (should (equal source "/tmp/slides.pptx"))
                 "/tmp/slides.pdf"))
              ((symbol-function 'find-file-other-window)
               (lambda (path)
                 (setq opened path))))
      (p3/office-preview-pptx "/tmp/slides.pptx")
      (should (equal opened "/tmp/slides.pdf")))))

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
              ((symbol-function 'find-file-other-window)
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
