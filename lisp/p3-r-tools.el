;;; p3-r-tools.el --- R project scaffolding and ESS commands -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep R templates, project generation, and interactive R helpers out of the
;; main Emacs configuration.  Project creation is non-destructive unless an
;; explicit overwrite argument is supplied.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'p3-project)

(declare-function ess-eval-linewise "ess-inf")
(declare-function ess-eval-region-or-function-or-paragraph "ess-mode")
(declare-function ess-get-process "ess-inf" (&optional name))
(declare-function ess-send-string "ess-inf" (process string &optional visibly))
(declare-function ess-symbol-at-point "ess-inf")
(declare-function inferior-ess-r-force "ess-r-mode")

(defvar ess-local-process-name)

(defgroup p3-r nil
  "Personal R and ESS workflow commands."
  :group 'ess
  :prefix "p3-r-")

(defcustom p3-r-author "Pavel Panko"
  "Author inserted into generated R documents."
  :type 'string
  :group 'p3-r)

(defcustom p3-r-template-directory
  (expand-file-name "templates/r" user-emacs-directory)
  "Directory containing R project and insertion templates."
  :type 'directory
  :group 'p3-r)

(defcustom p3-r-default-profile 'targets
  "Default profile offered by `p3-r-new-project'."
  :type '(choice (const analysis) (const targets))
  :group 'p3-r)

(defcustom p3-r-target-workers 10
  "Number of local workers written to a Targets project."
  :type 'integer
  :group 'p3-r)

(defcustom p3-r-helper-file-candidates
  '("R/utils.R" "R/99_helperFunctions.R")
  "Project-relative R helper files, in preferred order."
  :type '(repeat string)
  :group 'p3-r)

(defconst p3-r--common-project-files
  '((:path "{{project-name}}.Rproj" :template "project.Rproj.tmpl")
    (:path ".gitignore" :template "gitignore.tmpl")
    (:path "R/01_prepareData.R" :template "script.R.tmpl"
           :title "Preprocess data")
    (:path "R/02_computeResults.R" :template "script.R.tmpl"
           :title "Compute results"))
  "Files shared by all R project profiles.")

(defcustom p3-r-project-profiles
  '((analysis
     :description "General analysis project"
     :directories ("R" "data" "data-raw" "output" "reports"
                   "reports/graphics" "bin")
     :files ((:path "R/utils.R" :template "utils.R.tmpl"
              :title "Helper functions")))
    (targets
     :description "Targets pipeline with renv and local workers"
     :directories ("R" "data" "data-raw" "output" "reports"
                   "reports/graphics" "bin")
     :files ((:path "R/utils.R" :template "targets-utils.R.tmpl"
              :title "Helper functions")
             (:path "_targets.R" :template "targets.R.tmpl"
              :title "_targets pipeline"))))
  "R project profiles.

Each entry is (NAME :description STRING :directories (DIR...)
:files (FILE...)).  A FILE is a plist with :path and either :template or
:content; it may also provide a :title placeholder value."
  :type '(alist :key-type symbol :value-type sexp)
  :group 'p3-r)

(defun p3-r--template-path (name)
  "Return the absolute path for template NAME."
  (let ((path (expand-file-name name p3-r-template-directory)))
    (unless (file-readable-p path)
      (user-error "R template is not readable: %s" path))
    path))

(defun p3-r--read-template (name)
  "Read template NAME and return its contents."
  (with-temp-buffer
    (insert-file-contents (p3-r--template-path name))
    (buffer-string)))

(defun p3-r--render-string (text values)
  "Render TEXT by replacing placeholders from VALUES.

VALUES is an alist whose keys are symbols corresponding to {{key}}
placeholders.  Signal an error if any placeholder remains unresolved."
  (dolist (entry values)
    (let ((placeholder (format "{{%s}}" (car entry)))
          (value (format "%s" (cdr entry))))
      (setq text
            (replace-regexp-in-string
             (regexp-quote placeholder) value text t t))))
  (when (string-match "{{[^}\n]+}}" text)
    (user-error "Unresolved R template placeholder: %s"
                (match-string 0 text)))
  text)

(defun p3-r-render-template (name values)
  "Render template NAME using placeholder VALUES."
  (p3-r--render-string (p3-r--read-template name) values))

(defun p3-r--profile (name)
  "Return profile NAME or signal a user-facing error."
  (or (assq name p3-r-project-profiles)
      (user-error "Unknown R project profile: %s" name)))

(defun p3-r--profile-names ()
  "Return configured R project profile names."
  (mapcar #'car p3-r-project-profiles))

(defun p3-r--read-profile ()
  "Prompt for an R project profile."
  (intern
   (completing-read
    "R project profile: "
    (mapcar #'symbol-name (p3-r--profile-names))
    nil t nil nil (symbol-name p3-r-default-profile))))

(defun p3-r--template-values (project-name &optional title)
  "Return standard template values for PROJECT-NAME and optional TITLE."
  `((author . ,p3-r-author)
    (date . ,(format-time-string "%m/%d/%Y"))
    (project-name . ,project-name)
    (target-workers . ,p3-r-target-workers)
    (title . ,(or title ""))))

(defun p3-r--project-plan (project-root profile-name)
  "Return the rendered file plan for PROJECT-ROOT and PROFILE-NAME."
  (let* ((profile (p3-r--profile profile-name))
         (project-name
          (file-name-nondirectory (directory-file-name project-root)))
         (specs (append p3-r--common-project-files
                        (plist-get (cdr profile) :files))))
    (mapcar
     (lambda (spec)
       (let* ((values (p3-r--template-values
                       project-name (plist-get spec :title)))
              (relative-path
               (p3-r--render-string (plist-get spec :path) values))
              (contents
               (if-let ((template (plist-get spec :template)))
                   (p3-r-render-template template values)
                 (or (plist-get spec :content) ""))))
         (cons (expand-file-name relative-path project-root) contents)))
     specs)))

(defun p3-r--existing-destinations (plan)
  "Return destination paths in PLAN that already exist."
  (seq-filter #'file-exists-p (mapcar #'car plan)))

(defun p3-r--write-plan (plan overwrite)
  "Write rendered PLAN, allowing replacement only when OVERWRITE is non-nil."
  (let ((existing (p3-r--existing-destinations plan)))
    (when (and existing (not overwrite))
      (user-error
       "Refusing to overwrite existing R project files: %s"
       (mapconcat #'abbreviate-file-name existing ", ")))
    (dolist (entry plan)
      (let ((path (car entry)))
        (make-directory (file-name-directory path) t)
        (with-temp-file path
          (insert (cdr entry)))))))

;;;###autoload
(defun p3-r-new-project (project-root profile &optional overwrite)
  "Create an R project at PROJECT-ROOT using PROFILE.

Existing files are never replaced unless OVERWRITE is non-nil.  Interactively,
a prefix argument enables replacement after the destination list is checked."
  (interactive
   (list (directory-file-name
          (expand-file-name
           (read-directory-name "Create R project at: " nil nil nil)))
         (p3-r--read-profile)
         current-prefix-arg))
  (let* ((root (file-name-as-directory (expand-file-name project-root)))
         (profile-entry (p3-r--profile profile))
         (plan (p3-r--project-plan root profile)))
    (when (and (file-exists-p (directory-file-name root))
               (not (file-directory-p root)))
      (user-error "R project destination is not a directory: %s" root))
    ;; Check every destination before creating or modifying anything.
    (when-let ((existing (and (not overwrite)
                              (p3-r--existing-destinations plan))))
      (user-error
       "Refusing to overwrite existing R project files: %s"
       (mapconcat #'abbreviate-file-name existing ", ")))
    (make-directory root t)
    (dolist (directory (plist-get (cdr profile-entry) :directories))
      (make-directory (expand-file-name directory root) t))
    (p3-r--write-plan plan overwrite)
    (message "Created %s R project: %s" profile (abbreviate-file-name root))
    root))

(defun p3-r--insert-template (name values)
  "Insert rendered template NAME using VALUES."
  (insert (p3-r-render-template name values)))

;;;###autoload
(defun p3-r-insert-script-header (title)
  "Insert a knitr-compatible R script header with TITLE."
  (interactive "sTitle: ")
  (p3-r--insert-template
   "script.R.tmpl"
   (p3-r--template-values
    (file-name-base (or buffer-file-name (buffer-name))) title)))

;;;###autoload
(defun p3-r-insert-word-report-header ()
  "Insert the header and setup chunk for a Word-oriented R report."
  (interactive)
  (p3-r--insert-template
   "word-report.R.tmpl"
   (p3-r--template-values
    (file-name-base (or buffer-file-name (buffer-name))) "")))

;;;###autoload
(defun p3-r-insert-chunk (header)
  "Insert an R Markdown chunk named HEADER and leave point in its body."
  (interactive "sHeader: ")
  (p3-r--insert-template "chunk.Rmd.tmpl" `((header . ,header)))
  (forward-line -1))

;;;###autoload
(defun p3-r-insert-pipe ()
  "Insert a magrittr pipe and newline without triggering ESS reindent."
  (interactive)
  (just-one-space 1)
  (insert "%>%\n"))

(defun p3-r--ess-process ()
  "Return the current ESS process or signal a user-facing error."
  (or (ess-get-process ess-local-process-name)
      (user-error "No current ESS R process")))

(defun p3-r-ess-run (code)
  "Run arbitrary R CODE in the current ESS process."
  (interactive "sR code: ")
  (ess-send-string (p3-r--ess-process) (concat code "\n") t))

(defun p3-r-ess-run-at-point (template)
  "Run R TEMPLATE after substituting its %s with the symbol at point."
  (interactive "sR code template (use %s for symbol): ")
  (if-let ((symbol (ess-symbol-at-point)))
      (ess-send-string
       (p3-r--ess-process) (format template symbol) t)
    (user-error "No valid R symbol at point")))

;;;###autoload
(defun p3-r-targets-make ()
  "Run `targets::tar_make()' in the current ESS process."
  (interactive)
  (inferior-ess-r-force)
  (p3-r-ess-run "targets::tar_make()"))

;;;###autoload
(defun p3-r-targets-make-debug ()
  "Run `targets::tar_make()' without callr or crew."
  (interactive)
  (inferior-ess-r-force)
  (p3-r-ess-run
   "targets::tar_make(callr_function = NULL, use_crew = FALSE, as_job = FALSE)"))

;;;###autoload
(defun p3-r-targets-load-at-point ()
  "Load the Targets object named at point into the current ESS process."
  (interactive)
  (inferior-ess-r-force)
  (p3-r-ess-run-at-point "targets::tar_load(%s)"))

;;;###autoload
(defun p3-r-shiny-run-app (&optional prompt-for-arguments)
  "Run `shiny::runApp()'.

With PROMPT-FOR-ARGUMENTS, ask for additional arguments."
  (interactive "P")
  (inferior-ess-r-force)
  (ess-eval-linewise
   "shiny::runApp(\".\")\n" "Running app" prompt-for-arguments
   '("" (read-string "Arguments: " "recompile = TRUE"))))

;;;###autoload
(defun p3-r-load-view-data-frame ()
  "Load the template `view_df()' helper into the current ESS process."
  (p3-r-ess-run (p3-r--read-template "view-df.R")))

;;;###autoload
(defun p3-r-view-data-frame-at-point ()
  "Open the R data frame at point with the `view_df()' helper."
  (interactive)
  (inferior-ess-r-force)
  (p3-r-ess-run-at-point "view_df(%s)"))

;;;###autoload
(defun p3-r-evaluate-library-section ()
  "Select and evaluate the R setup section surrounding point."
  (interactive)
  (let ((section-end
         (save-excursion (re-search-backward "#' ### 1\\." nil t)))
        (section-start
         (save-excursion (re-search-backward "#' ### 0\\." nil t))))
    (unless (and section-start section-end)
      (user-error "Could not find R sections 0 and 1 before point"))
    (save-excursion
      (goto-char section-start)
      (push-mark section-end t t)
      (ess-eval-region-or-function-or-paragraph))))

;;;###autoload
(defun p3-r-write-to-read (&optional beginning end)
  "Convert write/save calls between BEGINNING and END to matching read calls.

Use the active region when available; otherwise process the entire buffer."
  (interactive)
  (let ((start (or beginning (and (use-region-p) (region-beginning)) (point-min)))
        (finish (copy-marker
                 (or end (and (use-region-p) (region-end)) (point-max)))))
    (save-excursion
      (goto-char start)
      (while (re-search-forward
              "\\(write\\|save\\)_?\\([a-zA-Z_]+\\)(\\([^,]+\\),\\s-*dataout(\"\\([^\"]+\\)\")"
              finish t)
        (let* ((operation (match-string 1))
               (format-name (match-string 2))
               (data (match-string 3))
               (filename (match-string 4))
               (read-operation
                (concat "read"
                        (if (string-equal operation "save") "" "_")
                        format-name)))
          (replace-match
           (format "%s <- %s(latest(\"%s\"))"
                   data read-operation filename)
           t nil))))
    (set-marker finish nil)))

(defun p3-r--copy-source-files (source-dir target-directory)
  "Copy R and R Markdown files from SOURCE-DIR to TARGET-DIRECTORY."
  (dolist (file (directory-files
                 source-dir t "\\.\\(?:[Rr]\\|[Rr]md\\)\\'"))
    (copy-file file target-directory t)))

;;;###autoload
(defun p3-r-archive-scripts ()
  "Archive R scripts from the current project's R or src directory."
  (interactive)
  (unless buffer-file-name
    (user-error "Current buffer is not visiting an R file"))
  (let* ((source-directory (file-name-directory buffer-file-name))
         (project-root (p3/project-root))
         (directory-name
          (file-name-nondirectory (directory-file-name source-directory))))
    (unless project-root
      (user-error "Current buffer is not in a project"))
    (unless (member directory-name '("R" "src"))
      (user-error "Current R file is not in an R or src directory"))
    (let ((target-directory
           (expand-file-name
            (format-time-string "Archive/%Y-%m-%d/%H-%M-%S") project-root)))
      (make-directory target-directory t)
      (p3-r--copy-source-files source-directory target-directory)
      (message "Archived R scripts to %s"
               (abbreviate-file-name target-directory)))))

;;;###autoload
(defun p3-r-open-helper-file ()
  "Open the first existing configured R helper file in the current project."
  (interactive)
  (let ((root (p3/project-root)))
    (unless root
      (user-error "Current buffer is not in a project"))
    (if-let ((path
              (seq-find #'file-exists-p
                        (mapcar (lambda (relative)
                                  (expand-file-name relative root))
                                p3-r-helper-file-candidates))))
        (find-file path)
      (user-error "No R helper file found in %s" root))))

(defvar-keymap p3-r-command-map
  :doc "Commands for R projects, templates, and ESS."
  "p" #'p3-r-new-project
  "h" #'p3-r-insert-script-header
  "w" #'p3-r-insert-word-report-header
  "c" #'p3-r-insert-chunk
  "i" #'p3-r-insert-pipe
  "s" #'p3-r-shiny-run-app
  "a" #'p3-r-archive-scripts
  "m" #'p3-r-targets-make
  "d" #'p3-r-targets-make-debug
  "l" #'p3-r-targets-load-at-point
  "v" #'p3-r-view-data-frame-at-point
  "r" #'p3-r-write-to-read
  "f" #'p3-r-open-helper-file)

;; Compatibility names retained for existing keybindings and muscle memory.
(defalias 'p3/ess-r-shiny-run-app #'p3-r-shiny-run-app)
(defalias 'p3/add-pipe-and-step #'p3-r-insert-pipe)
(defalias 'p3/insert-r-chunk #'p3-r-insert-chunk)
(defalias 'p3/insert-roxygenated-header #'p3-r-insert-script-header)
(defalias 'p3/insert-word-roxygenated-header #'p3-r-insert-word-report-header)
(defalias 'p3/ess-run #'p3-r-ess-run)
(defalias 'p3/ess-run-at-point #'p3-r-ess-run-at-point)
(defalias 'p3/tar-make #'p3-r-targets-make)
(defalias 'p3/tar-make-debug #'p3-r-targets-make-debug)
(defalias 'p3/tar-load-at-point #'p3-r-targets-load-at-point)
(defalias 'p3/load-view-df-function #'p3-r-load-view-data-frame)
(defalias 'p3/r-view-df-at-point #'p3-r-view-data-frame-at-point)
(defalias 'p3/ess-library-and-source #'p3-r-evaluate-library-section)
(defalias 'write-to-read-conversion-multi #'p3-r-write-to-read)
(defalias 'p3/archive-r-scripts #'p3-r-archive-scripts)
(defalias 'p3/projectile-open-r-helper-functions-file #'p3-r-open-helper-file)

(defun p3/generate-roxygen-header (title &optional minimal)
  "Return a rendered R script header for TITLE.

When MINIMAL is non-nil, omit the setup section."
  (p3-r-render-template
   (if minimal "utils.R.tmpl" "script.R.tmpl")
   (p3-r--template-values "" title)))

(defun p3/create-r-project-dir-structure (&optional include-targets)
  "Compatibility command for `p3-r-new-project'.

With INCLUDE-TARGETS, preselect the Targets profile."
  (interactive "P")
  (let ((p3-r-default-profile
         (if include-targets 'targets p3-r-default-profile)))
    (call-interactively #'p3-r-new-project)))

(provide 'p3-r-tools)

;;; p3-r-tools.el ends here
