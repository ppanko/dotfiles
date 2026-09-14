;;; p3-r-tidyverse-completion.el --- Tidyverse column completion -*- lexical-binding: t; -*-

;;; Commentary:
;; Add a narrow dataframe-column completion source for common dplyr contexts.
;; Syntax recognition stays local and conservative.  The only live-session
;; query permitted is a names() lookup for a validated simple symbol in the
;; already-running project ESS process; arbitrary source expressions are never
;; evaluated for completion.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'p3-ess)

(declare-function company-begin-backend "company" (backend))
(declare-function ess-command "ess-inf"
                  (cmd &optional out-buffer sleep no-prompt-check wait proc
                       force-redisplay timeout))

(defvar company-backends)

(defconst p3/r-tidyverse--verbs
  '("mutate" "transmute" "filter" "select" "rename" "relocate"
    "arrange" "group_by" "summarise" "summarize" "distinct"
    "count" "add_count")
  "Dplyr verbs whose input data mask benefits from column completion.")

(defconst p3/r-tidyverse--schema-preserving-verbs
  '("filter" "arrange")
  "Supported upstream verbs known to preserve the full input schema.")

(defconst p3/r-tidyverse--query-timeout 0.1
  "Maximum seconds a synchronous live-schema query may block Emacs.")

(defvar-local p3/r-tidyverse--schema-cache nil
  "Cached live schemas for the current R source buffer.

Entries have the shape (SYMBOL PROCESS OBSERVED-AT COLUMNS).")

(defun p3/r-tidyverse--simple-symbol-p (text)
  "Return non-nil when TEXT is a safe simple R symbol."
  (and (stringp text)
       (string-match-p
        "\\`[[:alpha:].][[:alnum:]_.]*\\'"
        text)))

(defun p3/r-tidyverse--schema-command (symbol)
  "Return the safe R schema query for SYMBOL, or nil when SYMBOL is unsafe."
  (when (p3/r-tidyverse--simple-symbol-p symbol)
    (format
     (concat
      "local({.p3_x <- get0(\"%s\", inherits=TRUE, ifnotfound=NULL); "
      "if (!is.null(.p3_x)) cat(paste(base::names(.p3_x), "
      "collapse=intToUtf8(31L))); cat(\"\\n\")})\n")
     symbol)))

(defun p3/r-tidyverse--cache-entry-valid-p (entry process last-eval)
  "Return non-nil when ENTRY is reusable for PROCESS after LAST-EVAL."
  (and entry
       (eq (nth 1 entry) process)
       (let ((observed-at (nth 2 entry)))
         (and observed-at
              (or (null last-eval)
                  (time-less-p last-eval observed-at))))))

(defun p3/r-tidyverse--cache-put (symbol process observed-at columns)
  "Cache COLUMNS for SYMBOL, PROCESS, and OBSERVED-AT in this buffer."
  (setq p3/r-tidyverse--schema-cache
        (cons (list symbol process observed-at columns)
              (cl-remove symbol p3/r-tidyverse--schema-cache
                         :key #'car :test #'equal)))
  columns)

(defun p3/r-tidyverse--parse-schema-output (text)
  "Parse column names from schema query output TEXT."
  (let ((trimmed (string-trim text)))
    (unless (string-empty-p trimmed)
      (split-string trimmed (regexp-quote (char-to-string 31)) t))))

(defun p3/r-tidyverse--live-columns (symbol)
  "Return live column names for simple SYMBOL without starting R.

Only the already-running ESS process associated with the current project is
consulted.  A live lookup is synchronous but bounded by
`p3/r-tidyverse--query-timeout'.  Busy, missing, stale, timed-out, and errored
processes return nil quietly."
  (when-let* ((command (p3/r-tidyverse--schema-command symbol))
              (process-name (p3/ess-project-process))
              (process (get-process process-name)))
    (when (and (process-live-p process)
               (not (process-get process 'busy)))
      (let* ((last-eval (process-get process 'last-eval))
             (entry (assoc symbol p3/r-tidyverse--schema-cache)))
        (if (p3/r-tidyverse--cache-entry-valid-p entry process last-eval)
            (nth 3 entry)
          (condition-case nil
              (let ((columns
                     (with-temp-buffer
                       ;; Pass PROCESS explicitly.  Keep normal prompt checking
                       ;; so ESS waits for complete output, but cap that wait so
                       ;; completion cannot block the UI indefinitely.
                       (ess-command command (current-buffer) nil nil nil process
                                    nil p3/r-tidyverse--query-timeout)
                       (p3/r-tidyverse--parse-schema-output
                        (buffer-string)))))
                (p3/r-tidyverse--cache-put
                 symbol process (current-time) columns))
            (error nil)))))))

(defun p3/r-tidyverse--function-info (open)
  "Return (VERB START) for a supported dplyr call whose paren is OPEN."
  (save-excursion
    (goto-char open)
    (skip-chars-backward " \t\n\r")
    (let ((end (point)))
      (skip-chars-backward "A-Za-z0-9._:")
      (let* ((start (point))
             (raw (buffer-substring-no-properties start end))
             (verb (and (string-match
                         "\\([[:alpha:].][[:alnum:]_.]*\\)\\'" raw)
                        (match-string 1 raw))))
        (when (and verb
                   (member verb p3/r-tidyverse--verbs)
                   (or (equal raw verb)
                       (equal raw (concat "dplyr::" verb))
                       (equal raw (concat "dplyr:::" verb))))
          (list verb start))))))

(defun p3/r-tidyverse--current-call ()
  "Return plist describing the nearest supported dplyr call around point."
  (let ((state (syntax-ppss)))
    (unless (or (nth 3 state) (nth 4 state))
      (let ((open (nth 1 state))
            found)
        (while (and open (not found))
          (when-let ((info (p3/r-tidyverse--function-info open)))
            (setq found (list :verb (car info)
                              :function-start (cadr info)
                              :open open)))
          (unless found
            (setq open
                  (nth 1 (save-excursion (syntax-ppss open))))))
        found))))

(defun p3/r-tidyverse--pipe-before (position)
  "Return the start of a pipe ending immediately before POSITION, or nil."
  (save-excursion
    (goto-char position)
    (skip-chars-backward " \t\n\r")
    (let ((end (point)))
      (cond
       ((and (>= (- end (point-min)) 3)
             (equal (buffer-substring-no-properties (- end 3) end) "%>%"))
        (- end 3))
       ((and (>= (- end (point-min)) 2)
             (equal (buffer-substring-no-properties (- end 2) end) "|>"))
        (- end 2))))))

(defun p3/r-tidyverse--top-level-comma (open end)
  "Return first comma between OPEN and END belonging directly to that call."
  (save-excursion
    (goto-char (1+ open))
    (catch 'comma
      (while (search-forward "," end t)
        (let* ((position (1- (point)))
               (state (save-excursion (syntax-ppss position))))
          (when (and (not (nth 3 state))
                     (not (nth 4 state))
                     (eq (nth 1 state) open))
            (throw 'comma position))))
      nil)))

(defun p3/r-tidyverse--split-top-level-args (start end)
  "Split arguments between START and END at top-level commas."
  (let ((depth (car (save-excursion (syntax-ppss start))))
        (piece-start start)
        pieces)
    (save-excursion
      (goto-char start)
      (while (search-forward "," end t)
        (let* ((position (1- (point)))
               (state (save-excursion (syntax-ppss position))))
          (when (and (not (nth 3 state))
                     (not (nth 4 state))
                     (= (car state) depth))
            (push (string-trim
                   (buffer-substring-no-properties piece-start position))
                  pieces)
            (setq piece-start (point)))))
      (let ((last (string-trim
                   (buffer-substring-no-properties piece-start end))))
        (unless (string-empty-p last)
          (push last pieces))))
    (nreverse pieces)))

(defun p3/r-tidyverse--assignment (text)
  "Return (NAME . RHS) for a simple named argument TEXT, or nil."
  (when (string-match
         "\\`\\([[:alpha:].][[:alnum:]_.]*\\)[ \t\n\r]*=[ \t\n\r]*\\(.+\\)\\'"
         text)
    (cons (match-string 1 text)
          (string-trim (match-string 2 text)))))

(defun p3/r-tidyverse--grouped-schema-p (schema)
  "Return non-nil when SCHEMA records unresolved grouping state."
  (eq (car-safe schema) :p3-grouped))

(defun p3/r-tidyverse--schema-columns (schema)
  "Return plain column names represented by SCHEMA."
  (if (p3/r-tidyverse--grouped-schema-p schema)
      (cdr schema)
    schema))

(defun p3/r-tidyverse--replace-column (columns old new)
  "Return COLUMNS with OLD replaced by NEW, or nil when OLD is absent."
  (when (member old columns)
    (mapcar (lambda (column) (if (equal column old) new column)) columns)))

(defun p3/r-tidyverse--select-columns (columns args)
  "Derive a simple select/transmute-like output from COLUMNS and ARGS."
  (catch 'unsafe
    (let (result)
      (dolist (arg args)
        (cond
         ((p3/r-tidyverse--simple-symbol-p arg)
          (unless (member arg columns)
            (throw 'unsafe nil))
          (setq result (append result (list arg))))
         ((when-let ((assignment (p3/r-tidyverse--assignment arg)))
            (let ((name (car assignment))
                  (source (cdr assignment)))
              (unless (and (p3/r-tidyverse--simple-symbol-p source)
                           (member source columns))
                (throw 'unsafe nil))
              (setq result (append result (list name)))
              t)))
         (t (throw 'unsafe nil))))
      result)))

(defun p3/r-tidyverse--rename-columns (columns args)
  "Apply simple dplyr rename ARGS to COLUMNS, or nil when unsafe."
  (catch 'unsafe
    (let ((result (copy-sequence columns)))
      (dolist (arg args)
        (let ((assignment (p3/r-tidyverse--assignment arg)))
          (unless assignment
            (throw 'unsafe nil))
          (let ((updated
                 (p3/r-tidyverse--replace-column
                  result (cdr assignment) (car assignment))))
            (unless updated
              (throw 'unsafe nil))
            (setq result updated))))
      result)))

(defun p3/r-tidyverse--relocate-columns (columns args)
  "Apply simple relocate ARGS to COLUMNS while tracking any rename."
  (catch 'unsafe
    (let ((result (copy-sequence columns)))
      (dolist (arg args)
        (cond
         ((p3/r-tidyverse--simple-symbol-p arg)
          (unless (member arg result)
            (throw 'unsafe nil)))
         ((when-let ((assignment (p3/r-tidyverse--assignment arg)))
            (let ((name (car assignment))
                  (source (cdr assignment)))
              (unless (and (p3/r-tidyverse--simple-symbol-p source)
                           (member source result))
                (throw 'unsafe nil))
              (unless (member name '(".before" ".after"))
                (let ((updated
                       (p3/r-tidyverse--replace-column result source name)))
                  (unless updated
                    (throw 'unsafe nil))
                  (setq result updated)))
              t)))
         (t (throw 'unsafe nil))))
      result)))

(defun p3/r-tidyverse--group-by-schema (schema args)
  "Return conservative grouped SCHEMA for simple existing-column ARGS."
  (let ((columns (p3/r-tidyverse--schema-columns schema)))
    (cond
     ((null args) columns)
     ((cl-every (lambda (arg)
                  (and (p3/r-tidyverse--simple-symbol-p arg)
                       (member arg columns)))
                args)
      (cons :p3-grouped columns))
     (t nil))))

(defun p3/r-tidyverse--mutate-columns (columns args)
  "Apply simple named mutate ARGS to COLUMNS, or nil when unsafe."
  (catch 'unsafe
    (let ((result (copy-sequence columns)))
      (dolist (arg args)
        (let ((assignment (p3/r-tidyverse--assignment arg)))
          (unless assignment
            (throw 'unsafe nil))
          (let ((name (car assignment))
                (rhs (cdr assignment)))
            (when (member name '(".by" ".keep" ".before" ".after"))
              (throw 'unsafe nil))
            (if (equal rhs "NULL")
                (setq result (cl-remove name result :test #'equal))
              (unless (member name result)
                (setq result (append result (list name))))))))
      result)))

(defun p3/r-tidyverse--transmute-columns (columns args)
  "Derive simple transmute output from COLUMNS and ARGS, or nil when unsafe."
  (catch 'unsafe
    (let (result)
      (dolist (arg args)
        (cond
         ((p3/r-tidyverse--simple-symbol-p arg)
          (unless (member arg columns)
            (throw 'unsafe nil))
          (setq result (append result (list arg))))
         ((when-let ((assignment (p3/r-tidyverse--assignment arg)))
            (let ((name (car assignment))
                  (rhs (cdr assignment)))
              (when (member name '(".by" ".keep" ".before" ".after"))
                (throw 'unsafe nil))
              (unless (equal rhs "NULL")
                (setq result (append result (list name))))
              t)))
         (t (throw 'unsafe nil))))
      result)))

(defun p3/r-tidyverse--apply-stage (verb schema args)
  "Return schema after supported upstream VERB over SCHEMA with ARGS."
  (let ((grouped (p3/r-tidyverse--grouped-schema-p schema))
        (columns (p3/r-tidyverse--schema-columns schema)))
    (cond
     ((member verb p3/r-tidyverse--schema-preserving-verbs)
      schema)
     ((equal verb "group_by")
      (p3/r-tidyverse--group-by-schema schema args))
     ;; Once grouping is present, schema-changing verbs can retain or rewrite
     ;; group columns in ways this intentionally small model does not track.
     (grouped nil)
     ((equal verb "select")
      (p3/r-tidyverse--select-columns columns args))
     ((equal verb "rename")
      (p3/r-tidyverse--rename-columns columns args))
     ((equal verb "relocate")
      (p3/r-tidyverse--relocate-columns columns args))
     ((equal verb "mutate")
      (p3/r-tidyverse--mutate-columns columns args))
     ((equal verb "transmute")
      (p3/r-tidyverse--transmute-columns columns args))
     ;; distinct/count/summarise can change output schemas in ways that need more
     ;; than the small deterministic model owned here.  They remain supported as
     ;; current completion contexts but stop upstream propagation.
     (t nil))))

(defun p3/r-tidyverse--simple-symbol-before (end)
  "Return a safely delimited simple symbol ending before END, or nil."
  (save-excursion
    (goto-char end)
    (skip-chars-backward " \t\n\r")
    (let ((symbol-end (point)))
      (skip-chars-backward "A-Za-z0-9._")
      (let* ((start (point))
             (symbol (buffer-substring-no-properties start symbol-end)))
        (when (p3/r-tidyverse--simple-symbol-p symbol)
          (save-excursion
            (goto-char start)
            (skip-chars-backward " \t")
            (when (or (= (point) (point-min))
                      (eq (char-before) ?\n)
                      (memq (char-before) '(?\( ?, ?\; ?{))
                      (looking-back "<-" (max (point-min) (- (point) 2)))
                      (looking-back "=" (max (point-min) (1- (point)))))
              symbol)))))))

(defun p3/r-tidyverse--resolve-direct-stage (verb open close)
  "Resolve a closed direct VERB call spanning OPEN through CLOSE."
  (when-let ((comma (p3/r-tidyverse--top-level-comma open close)))
    (let ((source (string-trim
                   (buffer-substring-no-properties (1+ open) comma))))
      (when (p3/r-tidyverse--simple-symbol-p source)
        (when-let ((columns (p3/r-tidyverse--live-columns source)))
          (p3/r-tidyverse--apply-stage
           verb columns
           (p3/r-tidyverse--split-top-level-args (1+ comma) close)))))))

(defun p3/r-tidyverse--resolve-expression-before (end)
  "Safely resolve the dataframe schema for the expression ending at END."
  (save-excursion
    (goto-char end)
    (skip-chars-backward " \t\n\r")
    (let ((expression-end (point)))
      (cond
       ((and (> expression-end (point-min))
             (eq (char-before expression-end) ?\)))
        (condition-case nil
            (let* ((open (scan-sexps expression-end -1))
                   (info (and open (p3/r-tidyverse--function-info open))))
              ;; An arbitrary closed call is an unsafe boundary.  Do not look
              ;; through it for an earlier simple symbol.
              (when info
                (let* ((verb (car info))
                       (function-start (cadr info))
                       (pipe (p3/r-tidyverse--pipe-before function-start)))
                  (if pipe
                      (when-let ((schema
                                  (p3/r-tidyverse--resolve-expression-before
                                   pipe)))
                        (p3/r-tidyverse--apply-stage
                         verb schema
                         (p3/r-tidyverse--split-top-level-args
                          (1+ open) (1- expression-end))))
                    (p3/r-tidyverse--resolve-direct-stage
                     verb open (1- expression-end))))))
          (scan-error nil)))
       (t
        (when-let ((symbol
                    (p3/r-tidyverse--simple-symbol-before expression-end)))
          (p3/r-tidyverse--live-columns symbol)))))))

(defun p3/r-tidyverse-columns-at-point ()
  "Return safe incoming dataframe columns for the dplyr context at point."
  (when-let* ((call (p3/r-tidyverse--current-call))
              (open (plist-get call :open)))
    (let* ((function-start (plist-get call :function-start))
           (pipe (p3/r-tidyverse--pipe-before function-start)))
      (if pipe
          (when-let ((schema (p3/r-tidyverse--resolve-expression-before pipe)))
            (p3/r-tidyverse--schema-columns schema))
        (when-let ((comma (p3/r-tidyverse--top-level-comma open (point))))
          (let ((source (string-trim
                         (buffer-substring-no-properties
                          (1+ open) comma))))
            (when (p3/r-tidyverse--simple-symbol-p source)
              (p3/r-tidyverse--live-columns source))))))))

(defun p3/r-tidyverse--prefix-bounds ()
  "Return completion prefix bounds around point for a simple R name."
  (let ((end (point)))
    (save-excursion
      (skip-chars-backward "A-Za-z0-9._")
      (cons (point) end))))

(defun p3/r-tidyverse-completion-at-point ()
  "Return a non-exclusive CAPF for safe tidyverse dataframe columns."
  (when-let ((columns (p3/r-tidyverse-columns-at-point)))
    (let ((bounds (p3/r-tidyverse--prefix-bounds)))
      (list (car bounds) (cdr bounds) columns :exclusive 'no))))

(defun p3/r-tidyverse-company-backend (command &optional arg &rest _ignored)
  "Company backend adapter for tidyverse columns.

COMMAND and ARG follow Company's backend protocol; Company remains the visible
completion frontend."
  (pcase command
    ('interactive
     (when (fboundp 'company-begin-backend)
       (company-begin-backend 'p3/r-tidyverse-company-backend)))
    ('prefix
     (when (p3/r-tidyverse-columns-at-point)
       (let ((bounds (p3/r-tidyverse--prefix-bounds)))
         (buffer-substring-no-properties (car bounds) (cdr bounds)))))
    ('candidates
     (when-let ((columns (p3/r-tidyverse-columns-at-point)))
       (seq-filter (lambda (column) (string-prefix-p (or arg "") column))
                   columns)))
    ('sorted t)
    ('no-cache t)
    ('ignore-case nil)))

(defun p3/r-tidyverse--company-backends-with-columns (backends)
  "Return BACKENDS with the tidyverse backend before generic ESS R sources."
  (mapcar
   (lambda (backend)
     (if (and (listp backend)
              (memq 'company-R-objects backend)
              (not (memq 'p3/r-tidyverse-company-backend backend)))
         (if (eq (car backend) :separate)
             (cons :separate
                   (cons 'p3/r-tidyverse-company-backend (cdr backend)))
           (cons 'p3/r-tidyverse-company-backend backend))
       backend))
   backends))

(defun p3/r-tidyverse-completion-buffer-setup ()
  "Add tidyverse column completion to the current ESS R source buffer."
  (setq-local company-backends
              (p3/r-tidyverse--company-backends-with-columns
               company-backends))
  (add-hook 'completion-at-point-functions
            #'p3/r-tidyverse-completion-at-point nil t))

(defun p3/r-tidyverse-completion-setup ()
  "Install tidyverse completion after ordinary ESS buffer configuration."
  (add-hook 'ess-r-mode-hook
            #'p3/r-tidyverse-completion-buffer-setup 50))

(provide 'p3-r-tidyverse-completion)

;;; p3-r-tidyverse-completion.el ends here
