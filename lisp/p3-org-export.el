;;; p3-org-export.el --- Pandoc export workflow for Org -*- lexical-binding: t; -*-

(require 'org)
(require 'org-element)
(require 'oc)
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
     :arguments ("--fail-if-warnings")
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
     :arguments ("--fail-if-warnings")
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

(defun p3-org-export--citation-arguments ()
  "Return Pandoc citation arguments for the current Org buffer.
Use Org's own bibliography resolver so local `#+BIBLIOGRAPHY' declarations
and `org-cite-global-bibliography' are combined with the same semantics Org
uses for citation lookup."
  (when (p3-org-export--citations-present-p)
    (let ((bibliographies
           (mapcar #'expand-file-name
                   (org-cite-list-bibliography-files))))
      (unless bibliographies
        (user-error
         "Org document contains citations but no bibliography is configured"))
      (cons
       "--citeproc"
       (mapcar
        (lambda (bibliography)
          (unless (file-readable-p bibliography)
            (user-error "Bibliography is not readable: %s" bibliography))
          (concat "--bibliography=" bibliography))
        bibliographies)))))

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

(defun p3-office-import--paths (source)
  "Return predictable sibling Org and media paths for Office SOURCE."
  (let* ((source (expand-file-name source))
         (base (file-name-sans-extension source)))
    (list :output (concat base ".org")
          :media-directory (concat base "-media"))))

(defun p3-office-import--docx-paths (source)
  "Return predictable import paths for DOCX SOURCE."
  (p3-office-import--paths source))

(defun p3-office-import--pptx-paths (source)
  "Return predictable import paths for PPTX SOURCE."
  (p3-office-import--paths source))

(defun p3-office-import--arguments (input-format source output media-directory)
  "Build Pandoc content-recovery arguments for INPUT-FORMAT SOURCE."
  (let ((media-path
         (file-relative-name media-directory
                             (file-name-directory (expand-file-name source)))))
    (list (concat "--from=" input-format)
          "--to=org"
          (concat "--extract-media=" media-path)
          source "-o" output)))

(defun p3-office-import--docx-arguments (source output media-directory)
  "Build Pandoc arguments for recovering DOCX SOURCE content into Org OUTPUT."
  (p3-office-import--arguments "docx" source output media-directory))

(defun p3-office-import--pptx-arguments (source output media-directory)
  "Build Pandoc arguments for recovering PPTX SOURCE content into Org OUTPUT."
  (p3-office-import--arguments "pptx" source output media-directory))

(defun p3-office-import--diagnostic-notice (diagnostics)
  "Return commented Pandoc DIAGNOSTICS for an imported Org file."
  (unless (string-empty-p diagnostics)
    (concat
     "# Pandoc diagnostics reported during conversion:\n"
     (mapconcat (lambda (line) (concat "# " line))
                (split-string diagnostics "\n" t)
                "\n")
     "\n")))

(defun p3-office-import--docx-notice (source diagnostics)
  "Return the durable DOCX content-recovery notice for SOURCE and DIAGNOSTICS."
  (concat
   "# P3 Office import: " (file-name-nondirectory source) "\n"
   "# This DOCX -> Org conversion recovers document content and is potentially "
   "lossy. Keep the original DOCX as the fidelity reference.\n"
   "# Custom Word styles and review metadata (tracked changes/comments) are not "
   "retained as reliable Org semantics; consult the original DOCX for them, "
   "layout, and native Word objects.\n"
   (p3-office-import--diagnostic-notice diagnostics)
   "\n"))

(defun p3-office-import--pptx-notice (source diagnostics)
  "Return the durable PPTX content-recovery notice for SOURCE and DIAGNOSTICS."
  (concat
   "# P3 Office import: " (file-name-nondirectory source) "\n"
   "# This PPTX -> Org conversion recovers slide content and is potentially "
   "lossy. Keep the original PPTX as the fidelity reference.\n"
   "# Slide geometry, themes, speaker notes, charts, animations, and native "
   "PowerPoint objects are not retained as reliable Org semantics.\n"
   (p3-office-import--diagnostic-notice diagnostics)
   "\n"))

(defun p3-office-import--validate-source (source extension label)
  "Return absolute SOURCE after validating EXTENSION and readability for LABEL."
  (let ((source (expand-file-name source)))
    (unless (string-equal (downcase (or (file-name-extension source) ""))
                          extension)
      (user-error "Incoming Office import expects a %s file" label))
    (unless (file-readable-p source)
      (user-error "%s file is not readable: %s" label source))
    source))

(defun p3-office-import--validate-docx-source (source)
  "Return absolute DOCX SOURCE after validating it."
  (p3-office-import--validate-source source "docx" "DOCX"))

(defun p3-office-import--validate-pptx-source (source)
  "Return absolute PPTX SOURCE after validating it."
  (p3-office-import--validate-source source "pptx" "PPTX"))

(defun p3-office-import--pandoc-supports-input-format-p (input-format)
  "Return non-nil when Pandoc advertises INPUT-FORMAT as an exact reader name."
  (let ((pandoc (p3-org-export--pandoc-executable)))
    (with-temp-buffer
      (let ((status
             (process-file pandoc nil (current-buffer) nil
                           "--list-input-formats")))
        (and (integerp status)
             (zerop status)
             (member input-format
                     (split-string (buffer-string)
                                   "[\r\n]+" t "[[:space:]]+")))))))

(defun p3-office-import--run-content-recovery
    (source input-format notice-function)
  "Recover SOURCE INPUT-FORMAT content into Org using NOTICE-FUNCTION."
  (let* ((paths (p3-office-import--paths source))
         (output (plist-get paths :output))
         (media-directory (plist-get paths :media-directory))
         (output-directory (file-name-directory output))
         (pandoc (p3-org-export--pandoc-executable)))
    (when (file-exists-p output)
      (user-error "Refusing to overwrite existing Org import: %s" output))
    (when (file-exists-p media-directory)
      (user-error "Refusing to overwrite existing media directory: %s"
                  media-directory))
    (let ((temporary-output
           (make-temp-file
            (expand-file-name
             (format ".p3-%s-import-" input-format)
             output-directory)
            nil ".org"))
          (stderr-file
           (make-temp-file (format "p3-%s-import-stderr-" input-format)))
          (completed nil))
      (unwind-protect
          (with-temp-buffer
            (let* ((default-directory (file-name-directory source))
                   (arguments
                    (p3-office-import--arguments
                     input-format source temporary-output media-directory))
                   (status
                    (apply #'process-file
                           pandoc nil (list (current-buffer) stderr-file)
                           nil arguments))
                   (stdout (string-trim (buffer-string)))
                   (stderr
                    (with-temp-buffer
                      (insert-file-contents stderr-file)
                      (string-trim (buffer-string))))
                   (diagnostics
                    (string-trim
                     (concat stderr
                             (unless (string-empty-p stderr) "\n")
                             stdout))))
              (unless (and (integerp status) (zerop status))
                (user-error "Pandoc %s import failed (status %s): %s"
                            (upcase input-format) status diagnostics))
              (let ((converted
                     (with-temp-buffer
                       (insert-file-contents temporary-output)
                       (buffer-string))))
                (with-temp-file temporary-output
                  (insert (funcall notice-function source diagnostics))
                  (insert converted)))
              (rename-file temporary-output output)
              (setq completed t)))
        (when (file-exists-p stderr-file)
          (delete-file stderr-file))
        (unless completed
          (when (file-exists-p temporary-output)
            (delete-file temporary-output))
          (when (file-directory-p media-directory)
            (delete-directory media-directory t))))
      (message "Imported %s to %s" source output)
      output)))

(defun p3-office-import-docx-run (source)
  "Recover incoming DOCX SOURCE content into a sibling Org file.

Embedded media is extracted to a sibling `-media' directory. Existing output
or media paths are never silently overwritten. Custom Word styles and review
metadata are not treated as preserved Org semantics; the generated notice keeps
that loss explicit. Pandoc diagnostics are also retained in the generated Org."
  (setq source (p3-office-import--validate-docx-source source))
  (p3-office-import--run-content-recovery
   source "docx" #'p3-office-import--docx-notice))

(defun p3-office-import-pptx-run (source)
  "Recover supported incoming PPTX SOURCE content into a sibling Org file.

Pandoc PPTX input is required. Slide geometry, themes, speaker notes, charts,
animations, and native PowerPoint objects remain authoritative in the original
PPTX rather than being treated as preserved Org semantics."
  (setq source (p3-office-import--validate-pptx-source source))
  (unless (p3-office-import--pandoc-supports-input-format-p "pptx")
    (user-error
     "Pandoc does not support PPTX input; install Pandoc 3.8.3 or newer"))
  (p3-office-import--run-content-recovery
   source "pptx" #'p3-office-import--pptx-notice))

(defun p3/office-import-docx (source)
  "Recover incoming DOCX SOURCE content to a sibling Org file and open it.

This is a content-recovery convenience, not a lossless round-trip. The
original DOCX remains authoritative for Word-specific styling, review metadata,
layout, and native objects."
  (interactive (list (read-file-name "Import DOCX: " nil nil t)))
  (find-file (p3-office-import-docx-run source)))

(defun p3/office-import-pptx (source)
  "Recover supported incoming PPTX SOURCE content to sibling Org and open it.

This is a content-recovery convenience, not a lossless round-trip. The
original PPTX remains authoritative for presentation-specific visual semantics."
  (interactive (list (read-file-name "Import PPTX: " nil nil t)))
  (find-file (p3-office-import-pptx-run source)))

(defun p3-org-export-setup ()
  "Install the Org export command and restore standard Org link opening."
  (define-key org-mode-map (kbd "C-c C-o") #'org-open-at-point)
  (define-key org-mode-map (kbd "C-c E") #'p3/org-export))

(provide 'p3-org-export)

;;; p3-org-export.el ends here
