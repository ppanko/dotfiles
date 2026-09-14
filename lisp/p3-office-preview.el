;;; p3-office-preview.el --- Render Office artifacts for Emacs preview -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep Office preview as thin orchestration around established artifacts.
;; PPTX preview renders the actual exported deck with LibreOffice and opens the
;; resulting PDF in Emacs; it does not approximate PowerPoint layout itself.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'url-util)
(require 'p3-org-export)

(defgroup p3-office-preview nil
  "Preview Office artifacts using external renderers."
  :group 'p3-org-export)

(defcustom p3-office-libreoffice-program nil
  "Optional LibreOffice executable override.

When nil, discover `soffice' or `libreoffice' on `exec-path', then try the
standard native installation paths for the current platform."
  :type '(choice (const :tag "Auto-detect" nil) string)
  :group 'p3-office-preview)

(defcustom p3-office-preview-directory
  (expand-file-name "p3-office-preview/" temporary-file-directory)
  "Directory used for disposable rendered Office previews."
  :type 'directory
  :group 'p3-office-preview)

(defun p3-office--libreoffice-platform-candidates (&optional platform)
  "Return standard LibreOffice executable paths for PLATFORM.
PLATFORM defaults to `system-type'."
  (pcase (or platform system-type)
    ('windows-nt
     '("C:/Program Files/LibreOffice/program/soffice.exe"
       "C:/Program Files (x86)/LibreOffice/program/soffice.exe"))
    (_ nil)))

(defun p3-office--configured-libreoffice-executable ()
  "Resolve `p3-office-libreoffice-program', or return nil when unset/unusable."
  (when (and p3-office-libreoffice-program
             (not (string-empty-p p3-office-libreoffice-program)))
    (let ((configured (expand-file-name p3-office-libreoffice-program)))
      (cond
       ((file-executable-p configured) configured)
       ((executable-find p3-office-libreoffice-program))
       (t
        (user-error "Configured LibreOffice executable is not usable: %s"
                    p3-office-libreoffice-program))))))

(defun p3-office--libreoffice-executable ()
  "Return a usable LibreOffice executable or signal an actionable error."
  (or (p3-office--configured-libreoffice-executable)
      (executable-find "soffice")
      (executable-find "libreoffice")
      (seq-find #'file-executable-p
                (p3-office--libreoffice-platform-candidates))
      (user-error
       (concat
        "LibreOffice is not installed or could not be found; install LibreOffice "
        "or set p3-office-libreoffice-program"))))

(defun p3-office-preview--validate-pptx-source (source)
  "Return absolute readable PPTX SOURCE or signal `user-error'."
  (let ((source (expand-file-name source)))
    (unless (string-equal (downcase (or (file-name-extension source) ""))
                          "pptx")
      (user-error "PowerPoint preview expects a PPTX file"))
    (unless (file-readable-p source)
      (user-error "PPTX file is not readable: %s" source))
    source))

(defun p3-office-preview--pptx-directory (source)
  "Return the cache directory for PPTX SOURCE without creating it."
  (let* ((source (expand-file-name source))
         (base (file-name-base source))
         (identity (substring (secure-hash 'sha1 source) 0 12)))
    (expand-file-name (format "%s-%s" base identity)
                      p3-office-preview-directory)))

(defun p3-office-preview--file-url (path)
  "Return an encoded local file URL for PATH suitable for LibreOffice."
  (let* ((absolute (expand-file-name path))
         (normalized (subst-char-in-string ?\\ ?/ absolute))
         (url (concat "file://"
                      (unless (string-prefix-p "/" normalized) "/")
                      normalized)))
    (url-encode-url url)))

(defun p3-office-preview--pptx-arguments
    (source output-directory profile-url)
  "Build LibreOffice arguments to render PPTX SOURCE into OUTPUT-DIRECTORY.
PROFILE-URL names a disposable LibreOffice user profile for this render."
  (list (concat "-env:UserInstallation=" profile-url)
        "--headless"
        "--nologo"
        "--nodefault"
        "--norestore"
        "--convert-to" "pdf:impress_pdf_Export"
        "--outdir" output-directory
        source))

(defun p3-office-preview--rendered-pdf-path (source directory)
  "Return the PDF path LibreOffice should produce for SOURCE in DIRECTORY."
  (expand-file-name (concat (file-name-base source) ".pdf") directory))

(defun p3-office-preview--process-diagnostics (stderr-file stdout)
  "Combine STDERR-FILE contents and STDOUT into one diagnostic string."
  (let ((stderr
         (if (file-readable-p stderr-file)
             (with-temp-buffer
               (insert-file-contents stderr-file)
               (string-trim (buffer-string)))
           "")))
    (string-trim
     (concat stderr
             (unless (or (string-empty-p stderr)
                         (string-empty-p stdout))
               "\n")
             stdout))))

(defun p3-office-preview-pptx-run (source)
  "Render actual PPTX SOURCE to a cached PDF and return the PDF path.

Rendering occurs in a fresh staging directory below
`p3-office-preview-directory' with an isolated LibreOffice user profile. A
prior successful preview is replaced only after LibreOffice exits successfully
and produces a non-empty PDF."
  (setq source (p3-office-preview--validate-pptx-source source))
  (let* ((libreoffice (p3-office--libreoffice-executable))
         (preview-root (file-name-as-directory
                        (expand-file-name p3-office-preview-directory)))
         (preview-directory (p3-office-preview--pptx-directory source))
         (preview (p3-office-preview--rendered-pdf-path
                   source preview-directory)))
    (make-directory preview-root t)
    (let ((staging-directory
           (make-temp-file (expand-file-name ".render-" preview-root) t))
          (stderr-file (make-temp-file "p3-office-preview-stderr-"))
          (completed nil))
      (unwind-protect
          (with-temp-buffer
            (let* ((default-directory (file-name-directory source))
                   (profile-url
                    (p3-office-preview--file-url
                     (expand-file-name "libreoffice-profile"
                                       staging-directory)))
                   (arguments
                    (p3-office-preview--pptx-arguments
                     source staging-directory profile-url))
                   (status
                    (apply #'process-file
                           libreoffice nil (list (current-buffer) stderr-file)
                           nil arguments))
                   (stdout (string-trim (buffer-string)))
                   (diagnostics
                    (p3-office-preview--process-diagnostics
                     stderr-file stdout))
                   (staged-pdf
                    (p3-office-preview--rendered-pdf-path
                     source staging-directory)))
              (unless (and (integerp status) (zerop status))
                (user-error "LibreOffice PPTX preview failed (status %s): %s"
                            status diagnostics))
              (unless (and (file-regular-p staged-pdf)
                           (> (file-attribute-size
                               (file-attributes staged-pdf))
                              0))
                (user-error
                 "LibreOffice completed but did not produce a usable PDF: %s"
                 (if (string-empty-p diagnostics)
                     staged-pdf
                   diagnostics)))
              (make-directory preview-directory t)
              (rename-file staged-pdf preview t)
              (setq completed t)))
        (when (file-exists-p stderr-file)
          (delete-file stderr-file))
        (when (file-directory-p staging-directory)
          (delete-directory staging-directory t)))
      (unless completed
        (user-error "PPTX preview did not complete"))
      (message "Rendered PPTX preview: %s" preview)
      preview)))

(defun p3-office-preview--open-pdf (path)
  "Open rendered PDF PATH in another window, refreshing an existing buffer."
  (when-let ((buffer (get-file-buffer path)))
    (with-current-buffer buffer
      (unless (buffer-modified-p)
        (revert-buffer t t))))
  (find-file-other-window path))

;;;###autoload
(defun p3/office-preview-pptx (source)
  "Render existing PPTX SOURCE with LibreOffice and open its PDF preview."
  (interactive (list (read-file-name "Preview PPTX: " nil nil t)))
  (p3-office-preview--open-pdf
   (p3-office-preview-pptx-run source)))

;;;###autoload
(defun p3/org-export-pptx-preview (&optional reference-document)
  "Export the current Org file to PPTX, render that artifact, and preview it.

REFERENCE-DOCUMENT, when non-nil, overrides the configured PPTX reference
presentation for this export. Interactively, a prefix argument prompts for a
one-off reference presentation."
  (interactive
   (list (when current-prefix-arg
           (p3-org-export--read-reference 'pptx))))
  (let* ((pptx (p3-org-export-run 'pptx reference-document))
         (pdf (p3-office-preview-pptx-run pptx)))
    (p3-office-preview--open-pdf pdf)
    pdf))

(provide 'p3-office-preview)

;;; p3-office-preview.el ends here
