;;; p3-org-export.el --- Pandoc export workflow for Org -*- lexical-binding: t; -*-

(require 'org)
(require 'org-element)
(require 'ox)
(require 'subr-x)

(defgroup p3-org-export nil
  "Personal Org export helpers backed by Pandoc."
  :group 'org-export)

(defcustom p3-org-export-reference-docx nil
  "Default reference DOCX used for Word exports.
A project can override this variable with directory-local settings."
  :type '(choice (const :tag "Pandoc default" nil) file)
  :group 'p3-org-export)

(defcustom p3-org-export-reference-pptx nil
  "Default reference PPTX used for PowerPoint exports.
A project can override this variable with directory-local settings."
  :type '(choice (const :tag "Pandoc default" nil) file)
  :group 'p3-org-export)

(defcustom p3-org-export-pandoc-program "pandoc"
  "Pandoc executable used by the Org export workflow."
  :type 'string
  :group 'p3-org-export)

(defconst p3-org-export-profiles
  '((docx
     :label "Word document (.docx)"
     :extension "docx"
     :format "docx"
     :reference-variable p3-org-export-reference-docx)
    (gfm
     :label "Markdown (.md, GFM)"
     :extension "md"
     :format "gfm"
     :arguments ("--standalone" "--wrap=none"))
    (pptx
     :label "PowerPoint (.pptx)"
     :extension "pptx"
     :format "pptx"
     :reference-variable p3-org-export-reference-pptx))
  "Pandoc output profiles exposed by `p3/org-export'.")

(defun p3-org-export--profile-id (profile)
  "Normalize PROFILE to its symbol identifier."
  (cond
   ((symbolp profile) profile)
   ((stringp profile) (intern (downcase profile)))
   (t profile)))

(defun p3-org-export--profile (profile)
  "Return the export profile plist for PROFILE.
Signal `user-error' when PROFILE is unknown."
  (let* ((profile-id (p3-org-export--profile-id profile))
         (spec (alist-get profile-id p3-org-export-profiles)))
    (or spec
        (user-error "Unsupported Org export profile: %s" profile))))

(defun p3-org-export--read-profile ()
  "Prompt for and return an Org export profile identifier."
  (let* ((choices
          (mapcar
           (lambda (entry)
             (cons (plist-get (cdr entry) :label) (car entry)))
           p3-org-export-profiles))
         (choice
          (completing-read "Export as: " (mapcar #'car choices) nil t)))
    (cdr (assoc choice choices))))

(defun p3-org-export--default-reference (profile)
  "Return the configured default reference document for PROFILE."
  (when-let ((variable
              (plist-get (p3-org-export--profile profile)
                         :reference-variable)))
    (symbol-value variable)))

(defun p3-org-export--read-reference (profile)
  "Prompt for a reference document suitable for PROFILE."
  (let* ((default (p3-org-export--default-reference profile))
         (directory (and default (file-name-directory
                                  (expand-file-name default)))))
    (read-file-name "Reference document: " directory default t)))

(defun p3-org-export--validate-reference (reference-document)
  "Return an absolute REFERENCE-DOCUMENT path after validating it."
  (when reference-document
    (let ((reference-document (expand-file-name reference-document)))
      (unless (file-readable-p reference-document)
        (user-error "Reference document is not readable: %s"
                    reference-document))
      reference-document)))

(defun p3-org-export--output-file (profile)
  "Return the output filename for PROFILE in the current Org buffer.
Honor Org's standard #+EXPORT_FILE_NAME keyword when present."
  (let* ((extension
          (plist-get (p3-org-export--profile profile) :extension))
         (output
          (org-export-output-file-name (concat "." extension) nil)))
    (expand-file-name output)))

(defun p3-org-export--citations-present-p ()
  "Return non-nil when the current Org buffer contains Org citations."
  (org-element-map (org-element-parse-buffer) 'citation
    (lambda (_citation) t)
    nil t))

(defun p3-org-export--local-bibliography-p ()
  "Return non-nil when the current Org buffer declares a bibliography."
  (not (null (cdr (assoc "BIBLIOGRAPHY"
                         (org-collect-keywords '("BIBLIOGRAPHY")))))))

(defun p3-org-export--global-bibliographies ()
  "Return `org-cite-global-bibliography' normalized to a list."
  (let ((bibliography
         (and (boundp 'org-cite-global-bibliography)
              org-cite-global-bibliography)))
    (cond
     ((null bibliography) nil)
     ((stringp bibliography) (list bibliography))
     ((listp bibliography) bibliography)
     (t
      (user-error "Invalid org-cite global bibliography: %S" bibliography)))))

(defun p3-org-export--citation-arguments ()
  "Return Pandoc citation arguments for the current Org buffer.
Use a document-local #+BIBLIOGRAPHY declaration when present.  Otherwise,
pass `org-cite-global-bibliography' explicitly to Pandoc."
  (when (p3-org-export--citations-present-p)
    (let ((arguments '("--citeproc")))
      (if (p3-org-export--local-bibliography-p)
          arguments
        (let ((bibliographies (p3-org-export--global-bibliographies)))
          (unless bibliographies
            (user-error
             "Org document contains citations but no bibliography is configured"))
          (append
           arguments
           (mapcar
            (lambda (bibliography)
              (let ((path (expand-file-name bibliography)))
                (unless (file-readable-p path)
                  (user-error "Bibliography is not readable: %s" path))
                (concat "--bibliography=" path)))
            bibliographies)))))))

(defun p3-org-export--arguments
    (profile source output reference-document &optional document-arguments)
  "Build Pandoc arguments for PROFILE from SOURCE to OUTPUT.
REFERENCE-DOCUMENT, when non-nil, is passed through `--reference-doc'.
DOCUMENT-ARGUMENTS contains source-specific Pandoc options such as citation
processing arguments."
  (let* ((spec (p3-org-export--profile profile))
         (format (plist-get spec :format))
         (extra-arguments (plist-get spec :arguments)))
    (append
     (list "--from=org" (concat "--to=" format))
     extra-arguments
     document-arguments
     (list source "-o" output)
     (when reference-document
       (list (concat "--reference-doc=" reference-document))))))

(defun p3-org-export--pandoc-executable ()
  "Return the configured Pandoc executable or signal `user-error'."
  (or (executable-find p3-org-export-pandoc-program)
      (user-error "Pandoc is not installed or is not on exec-path")))

(defun p3-org-export-run (profile &optional reference-document)
  "Export the current Org file using PROFILE.
REFERENCE-DOCUMENT overrides the profile's configured default when non-nil."
  (unless (derived-mode-p 'org-mode)
    (user-error "Current buffer is not an Org buffer"))
  (unless buffer-file-name
    (user-error "Current Org buffer is not visiting a file"))
  (when (buffer-modified-p)
    (save-buffer))
  (let* ((profile-id (p3-org-export--profile-id profile))
         (_profile (p3-org-export--profile profile-id))
         (pandoc (p3-org-export--pandoc-executable))
         (source (expand-file-name buffer-file-name))
         (output (p3-org-export--output-file profile-id))
         (reference
          (p3-org-export--validate-reference
           (or reference-document
               (p3-org-export--default-reference profile-id))))
         (document-arguments (p3-org-export--citation-arguments))
         (arguments
          (p3-org-export--arguments
           profile-id source output reference document-arguments)))
    (with-temp-buffer
      (let* ((default-directory (file-name-directory source))
             (status
              (apply #'process-file
                     pandoc nil (current-buffer) nil arguments))
             (diagnostics (string-trim (buffer-string))))
        (unless (and (integerp status) (zerop status))
          (user-error "Pandoc export failed (status %s): %s"
                      status diagnostics))))
    (message "Exported %s" output)
    output))

(defun p3/org-export (&optional profile prompt-reference)
  "Export the current Org file through a named Pandoc PROFILE.
Interactively, prompt for the profile.  With a prefix argument, also prompt
for a reference document when the selected profile supports one."
  (interactive (list nil current-prefix-arg))
  (let* ((profile-id
          (p3-org-export--profile-id
           (or profile (p3-org-export--read-profile))))
         (spec (p3-org-export--profile profile-id))
         (reference
          (if (and prompt-reference
                   (plist-get spec :reference-variable))
              (p3-org-export--read-reference profile-id)
            (p3-org-export--default-reference profile-id))))
    (p3-org-export-run profile-id reference)))

(defun p3/org-export-to-office (output-format &optional template-file)
  "Compatibility wrapper for the former Office-only exporter.
OUTPUT-FORMAT must be either `docx' or `pptx'.  TEMPLATE-FILE, when non-nil,
overrides the configured reference document.  Interactively, a prefix
argument prompts for a one-off reference document."
  (interactive
   (let* ((format
           (completing-read "Office output format: " '("docx" "pptx") nil t))
          (profile (intern format)))
     (list format
           (when current-prefix-arg
             (p3-org-export--read-reference profile)))))
  (unless (member (p3-org-export--profile-id output-format) '(docx pptx))
    (user-error "Unsupported Office output format: %s" output-format))
  (p3-org-export-run output-format template-file))

(defun p3-org-export--update-keybinding-atlas ()
  "Update the runtime keybinding atlas for the Org export workflow."
  (when (boundp 'p3/keybinding-sections)
    (let* ((sections (copy-tree (symbol-value 'p3/keybinding-sections)))
           (org-section (assoc "Org" sections)))
      (when org-section
        (let (bindings)
          (dolist (entry (cdr org-section))
            (setq bindings
                  (append
                   bindings
                   (cond
                    ((equal (car entry) "C-c C-o")
                     '(("C-c C-o" . "open link at point")
                       ("C-c E" . "export Org file")))
                    ((equal (car entry) "C-c E") nil)
                    (t (list entry))))))
          (setcdr org-section bindings)))
      (set 'p3/keybinding-sections sections))))

(defun p3-org-export-setup ()
  "Install the Org export command and restore standard Org link opening."
  (define-key org-mode-map (kbd "C-c C-o") #'org-open-at-point)
  (define-key org-mode-map (kbd "C-c E") #'p3/org-export)
  (p3-org-export--update-keybinding-atlas)
  (when (fboundp 'which-key-add-key-based-replacements)
    (which-key-add-key-based-replacements
     "C-c E" "export Org file")))

(provide 'p3-org-export)

;;; p3-org-export.el ends here
