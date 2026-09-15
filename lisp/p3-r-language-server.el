;;; p3-r-language-server.el --- Managed R language-server integration -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep editor tooling outside project libraries while using the same R
;; installation authority as ESS.  Eglot supplies semantic behavior; this file
;; only resolves/bootstrap the R-side server and preserves existing Company and
;; Flycheck ownership.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'p3-platform)

(defvar eglot-ignored-server-capabilities)
(defvar eglot-server-programs)
(defvar eglot-stay-out-of)

(declare-function eglot-hover-eldoc-function "eglot" (callback &rest ignored))
(declare-function eglot-managed-p "eglot" ())
(declare-function eglot-signature-eldoc-function "eglot" (callback &rest ignored))
(declare-function ess-r-eldoc-function "ess-r-completion" (&rest ignored))

(defconst p3/r-eglot-ignored-capabilities
  '(:documentFormattingProvider
    :documentRangeFormattingProvider
    :documentOnTypeFormattingProvider
    :semanticTokensProvider
    :foldingRangeProvider
    :typeHierarchyProvider
    :inlayHintProvider
    :inlineValueProvider
    :colorProvider
    :selectionRangeProvider
    :linkedEditingRangeProvider
    :codeLensProvider
    :documentLinkProvider)
  "R server capabilities intentionally outside the semantic workflow scope.")

(defvar p3/r-language-server-bootstrap-failed nil
  "Program/library key whose language-server bootstrap failed this session.")

(defvar p3/r-language-server-ready nil
  "Cons of R program and managed library known usable this session.")

(defvar p3/r-language-server-ready-fingerprint nil
  "Cheap local fingerprint of the R executable backing readiness state.")

(defvar p3/r-language-server-warning-key nil
  "Last R language-server setup problem already reported this session.")

(defvar-local p3/r-eglot-eldoc-owned-p nil
  "Non-nil when this buffer has switched R Eldoc ownership to Eglot.")

(defvar-local p3/r-eglot-ess-eldoc-was-present nil
  "Non-nil when ESS Eldoc was present before Eglot took R Eldoc ownership.")

(defun p3/r-language-server-warn-once (key message)
  "Report MESSAGE once for language-server problem KEY."
  (unless (equal key p3/r-language-server-warning-key)
    (setq p3/r-language-server-warning-key key)
    (display-warning 'p3/r-language-server message :warning)))

(defun p3/r-language-server-platform-key ()
  "Return a filesystem-safe key for the current platform."
  (pcase system-type
    ('windows-nt "windows")
    ('gnu/linux "linux")
    (_ (replace-regexp-in-string "/" "-" (symbol-name system-type)))))

(defun p3/r-version (&optional program)
  "Return the full version of R from PROGRAM, or nil when unavailable."
  (when-let ((program (or program (p3/r-program))))
    (with-temp-buffer
      (let ((status
             (call-process
              program nil t nil
              "--slave" "--vanilla" "-e"
              "cat(paste(R.version$major, R.version$minor, sep='.'))")))
        (when (and (integerp status) (zerop status))
          (let ((version (string-trim (buffer-string))))
            (and (string-match-p "\\`[0-9]+\\.[0-9]+" version)
                 version)))))))

(defun p3/r-major-minor-version (version)
  "Return major.minor from R VERSION, or nil when VERSION is malformed."
  (when (and version
             (string-match "\\`\\([0-9]+\\.[0-9]+\\)" version))
    (match-string 1 version)))

(defun p3/r-language-server-tool-root ()
  "Return the normalized machine-local root for managed R editor tools."
  (let* ((raw (replace-regexp-in-string
               "\\\\" "/" user-emacs-directory t t))
         (absolute
          (cond
           ((and (eq system-type 'windows-nt)
                 (string-match "\\`\\([A-Za-z]\\):/" raw))
            (concat (downcase (match-string 1 raw)) (substring raw 1)))
           ((and (eq system-type 'gnu/linux)
                 (string-prefix-p "/" raw))
            raw)
           (t (expand-file-name raw)))))
    (file-name-as-directory absolute)))

(defun p3/r-language-server-library (version)
  "Return the managed editor-tool library for R VERSION."
  (when-let ((major-minor (p3/r-major-minor-version version)))
    (file-name-as-directory
     (concat
      (p3/r-language-server-tool-root)
      (format "r-tools/%s/R-%s/library"
              (p3/r-language-server-platform-key)
              major-minor)))))

(defun p3/r-language-server-state-file ()
  "Return the machine-local readiness file for managed R semantic tooling."
  (expand-file-name
   (format "r-tools/%s/current-language-server.el"
           (p3/r-language-server-platform-key))
   (p3/r-language-server-tool-root)))

(defun p3/r-program-fingerprint (program)
  "Return a cheap local fingerprint for PROGRAM, or nil when unavailable.
The fingerprint uses only filesystem metadata and never launches R, so it is
safe to compare from a file-visit hook."
  (condition-case nil
      (let* ((resolved (file-truename program))
             (attributes (file-attributes resolved 'string)))
        (when attributes
          (list resolved
                (file-attribute-size attributes)
                (file-attribute-modification-time attributes)
                (file-attribute-file-identifier attributes))))
    (file-error nil)))

(defun p3/r-language-server-write-state (program library)
  "Persist PROGRAM and LIBRARY as the prepared R semantic-tool state."
  (let* ((fingerprint (p3/r-program-fingerprint program))
         (ready (cons program library))
         (state (and fingerprint
                     (list :program program
                           :library library
                           :fingerprint fingerprint)))
         (file (p3/r-language-server-state-file)))
    (unless state
      (user-error "Cannot fingerprint R executable for semantic-tool readiness"))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (prin1 state (current-buffer))
      (insert "\n"))
    (setq p3/r-language-server-ready ready
          p3/r-language-server-ready-fingerprint fingerprint)
    ready))

(defun p3/r-language-server-read-state ()
  "Return persisted prepared R semantic-tool state, or nil when unavailable."
  (let ((file (p3/r-language-server-state-file)))
    (when (file-readable-p file)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents file)
            (let* ((state (read (current-buffer)))
                   (program (plist-get state :program))
                   (library (plist-get state :library))
                   (fingerprint (plist-get state :fingerprint)))
              (and (listp state)
                   (stringp program)
                   (stringp library)
                   (listp fingerprint)
                   state)))
        (error nil)))))

(defun p3/r-language-server-clear-state ()
  "Forget persisted and in-session R semantic-tool readiness."
  (setq p3/r-language-server-ready nil
        p3/r-language-server-ready-fingerprint nil)
  (let ((file (p3/r-language-server-state-file)))
    (when (file-exists-p file)
      (delete-file file))))

(defun p3/r-language-server-ready-state ()
  "Return prepared R semantic-tool state using only cheap local checks."
  (let* ((persisted (and (null p3/r-language-server-ready)
                         (p3/r-language-server-read-state)))
         (state (or p3/r-language-server-ready
                    (and persisted
                         (cons (plist-get persisted :program)
                               (plist-get persisted :library)))))
         (fingerprint (or p3/r-language-server-ready-fingerprint
                          (and persisted (plist-get persisted :fingerprint)))))
    (when-let* ((state state)
                (program (car state))
                (library (cdr state))
                ((file-executable-p program))
                ((file-readable-p
                  (expand-file-name "languageserver/DESCRIPTION" library)))
                (current-fingerprint (p3/r-program-fingerprint program))
                ((equal fingerprint current-fingerprint)))
      (setq p3/r-language-server-ready state
            p3/r-language-server-ready-fingerprint current-fingerprint)
      state)))

(defun p3/r-string-literal (text)
  "Return TEXT as a double-quoted R string literal."
  (let ((text (replace-regexp-in-string "\\\\" "/" text t t)))
    (format "\"%s\""
            (replace-regexp-in-string "\"" "\\\\\"" text t t))))

(defun p3/r-language-server-library-expression (library body)
  "Return R code that prepends LIBRARY before evaluating BODY."
  (format ".libPaths(c(%s, .libPaths())); %s"
          (p3/r-string-literal (directory-file-name library))
          body))

(defun p3/r-call-managed-tool-process (program library destination display expression)
  "Run PROGRAM for managed R tooling with LIBRARY isolated from user/site libs.
DESTINATION and DISPLAY are passed through to `call-process'.  EXPRession runs
with LIBRARY as `R_LIBS', while `R_LIBS_USER' and `R_LIBS_SITE' are explicitly
set to NULL so R cannot satisfy editor-tool dependencies from incidental
machine-global libraries.  R's own `.Library' remains available."
  (let ((process-environment (copy-sequence process-environment)))
    (setenv "R_LIBS" (directory-file-name library))
    (setenv "R_LIBS_USER" "NULL")
    (setenv "R_LIBS_SITE" "NULL")
    (call-process program nil destination display
                  "--slave" "--vanilla" "-e" expression)))

(defun p3/r-language-server-installed-p (program library)
  "Return non-nil when PROGRAM can load `languageserver' from LIBRARY itself."
  (let* ((library-literal
          (p3/r-string-literal (directory-file-name library)))
         (expression
          (format
           (concat
            "quit(status=if (tryCatch({"
            "loadNamespace(\"languageserver\", lib.loc=%s); TRUE"
            "}, error=function(e) FALSE)) 0L else 1L)")
           library-literal))
         (status
          (p3/r-call-managed-tool-process
           program library nil nil expression)))
    (and (integerp status) (zerop status))))

(defun p3/r-install-language-server (program library)
  "Install released CRAN `languageserver' with PROGRAM into LIBRARY.
Return non-nil only when the installed package can subsequently be loaded."
  (make-directory library t)
  (let* ((buffer (get-buffer-create "*p3-r-language-server-bootstrap*"))
         (expression
          (format
           (concat "install.packages(\"languageserver\", lib=%s, "
                   "repos=\"https://cloud.r-project.org\", dependencies=NA)")
           (p3/r-string-literal (directory-file-name library))))
         status)
    (with-current-buffer buffer
      (erase-buffer))
    (message "Installing R languageserver into %s..."
             (abbreviate-file-name library))
    (setq status
          (p3/r-call-managed-tool-process
           program library buffer t expression))
    (if (and (integerp status)
             (zerop status)
             (p3/r-language-server-installed-p program library))
        t
      (display-warning
       'p3/r-language-server
       (format
        (concat "Could not install R languageserver with %s. "
                "See %s for CRAN/build output.")
        program (buffer-name buffer))
       :warning)
      nil)))

(defun p3/r-ensure-language-server ()
  "Return a usable managed `languageserver' library, bootstrapping if needed."
  (if-let ((program (p3/r-program)))
      (if (and p3/r-language-server-ready
               (equal program (car p3/r-language-server-ready)))
          (cdr p3/r-language-server-ready)
        (if-let* ((version (p3/r-version program))
                  (library (p3/r-language-server-library version)))
            (let ((key (cons program library)))
              (cond
               ((p3/r-language-server-installed-p program library)
                (setq p3/r-language-server-bootstrap-failed nil
                      p3/r-language-server-warning-key nil
                      p3/r-language-server-ready key
                      p3/r-language-server-ready-fingerprint
                      (p3/r-program-fingerprint program))
                library)
               ((equal p3/r-language-server-bootstrap-failed key)
                nil)
               (t
                (condition-case err
                    (if (p3/r-install-language-server program library)
                        (progn
                          (setq p3/r-language-server-bootstrap-failed nil
                                p3/r-language-server-warning-key nil
                                p3/r-language-server-ready key
                                p3/r-language-server-ready-fingerprint
                                (p3/r-program-fingerprint program))
                          library)
                      (setq p3/r-language-server-bootstrap-failed key)
                      nil)
                  (error
                   (setq p3/r-language-server-bootstrap-failed key)
                   (p3/r-language-server-warn-once
                    (list 'bootstrap key)
                    (format
                     (concat "R languageserver bootstrap failed with %s: %s. "
                             "ESS remains available; fix the underlying problem, "
                             "then run M-x p3/r-bootstrap-language-server to retry.")
                     program (error-message-string err)))
                   nil)))))
          (p3/r-language-server-warn-once
           (list 'version program)
           (format
            (concat "Could not determine the version of R at %s. "
                    "ESS remains available; check the configured R executable, "
                    "then run M-x p3/r-bootstrap-language-server to retry.")
            program))
          nil))
    (p3/r-language-server-warn-once
     'no-r
     (concat
      "No usable R executable is configured for semantic R support. "
      "ESS editing remains available; install/configure R, then run "
      "M-x p3/r-bootstrap-language-server to retry."))
    nil))

;;;###autoload
(defun p3/r-bootstrap-language-server ()
  "Retry preparation of the managed R language server explicitly."
  (interactive)
  (setq p3/r-language-server-bootstrap-failed nil
        p3/r-language-server-warning-key nil)
  (p3/r-language-server-clear-state)
  (condition-case err
      (if-let* ((library (p3/r-ensure-language-server))
                (program (p3/r-program)))
          (progn
            (p3/r-language-server-write-state program library)
            (message "R languageserver ready: %s"
                     (abbreviate-file-name library)))
        (user-error "R languageserver bootstrap failed; see warnings/output buffer"))
    (file-error
     (let ((message (error-message-string err)))
       (p3/r-language-server-warn-once
        (list 'bootstrap message)
        (format "R languageserver bootstrap failed: %s" message))
       (user-error "R languageserver bootstrap failed: %s" message)))))

(defun p3/r-language-server-command ()
  "Return the Eglot command only when managed R tooling is already prepared."
  (if-let ((program (p3/r-program)))
      (if-let ((state (p3/r-language-server-ready-state)))
          (if (equal program (car state))
              (let ((library (cdr state)))
                (setq p3/r-language-server-warning-key nil)
                (list
                 program "--slave" "-e"
                 (p3/r-language-server-library-expression
                  library "languageserver::run()")))
            (p3/r-language-server-warn-once
             (list 'stale program (car state))
             (concat
              "Prepared R semantic tooling belongs to a different R executable. "
              "ESS/editing remains available; run "
              "M-x p3/r-bootstrap-language-server to refresh it."))
            nil)
        (p3/r-language-server-warn-once
         'not-ready
         (concat
          "Managed R languageserver is not prepared. ESS/editing remains available; "
          "run M-x p3/r-bootstrap-language-server once to enable semantic support."))
        nil)
    (p3/r-language-server-warn-once
     'no-r
     (concat
      "No usable R executable is configured for semantic R support. "
      "ESS editing remains available; install/configure R, then run "
      "M-x p3/r-bootstrap-language-server to retry."))
    nil))

(defun p3/r-eglot-sync-eldoc-ownership ()
  "Keep Eglot hover as the sole R documentation provider while managed.
Leave ESS Eldoc untouched when Eglot is configured to stay out of Eldoc, and
restore the exact pre-Eglot ESS provider state when Eglot stops managing the
buffer."
  (if (eglot-managed-p)
      (when (memq #'eglot-hover-eldoc-function eldoc-documentation-functions)
        (unless p3/r-eglot-eldoc-owned-p
          (setq p3/r-eglot-ess-eldoc-was-present
                (and (memq #'ess-r-eldoc-function
                           eldoc-documentation-functions)
                     t)
                p3/r-eglot-eldoc-owned-p t))
        (remove-hook 'eldoc-documentation-functions #'ess-r-eldoc-function t)
        (remove-hook 'eldoc-documentation-functions
                     #'eglot-signature-eldoc-function t))
    (when p3/r-eglot-eldoc-owned-p
      (when p3/r-eglot-ess-eldoc-was-present
        (add-hook 'eldoc-documentation-functions #'ess-r-eldoc-function nil t))
      (setq p3/r-eglot-ess-eldoc-was-present nil
            p3/r-eglot-eldoc-owned-p nil))))

(defun p3/r-eglot-ensure ()
  "Start R Eglot with only the semantic capabilities owned by this workflow."
  (condition-case err
      (when-let ((command (p3/r-language-server-command)))
        (require 'eglot)
        (add-hook 'eglot-managed-mode-hook
                  #'p3/r-eglot-sync-eldoc-ownership nil t)
        (setq-local
         eglot-stay-out-of
         (cl-remove-duplicates
          (append '(flymake "company") eglot-stay-out-of)
          :test #'equal))
        (setq-local
         eglot-ignored-server-capabilities
         (cl-remove-duplicates
          (append p3/r-eglot-ignored-capabilities
                  eglot-ignored-server-capabilities)
          :test #'eq))
        (setq-local eglot-server-programs (copy-tree eglot-server-programs))
        (setf (alist-get '(R-mode ess-r-mode)
                         eglot-server-programs nil nil #'equal)
              command)
        (eglot-ensure)
        (when (eglot-managed-p)
          (p3/r-eglot-sync-eldoc-ownership)))
    (error
     (let ((message (error-message-string err)))
       (p3/r-language-server-warn-once
        (list 'startup message)
        (format
         (concat "R semantic setup failed: %s. ESS/editing remains available; "
                 "fix the R setup and run M-x p3/r-bootstrap-language-server "
                 "to retry.")
         message)))
     nil)))

(defun p3/r-language-server-setup ()
  "Install the R language-server hook exactly once and after R buffer setup."
  (add-hook 'ess-r-mode-hook #'p3/r-eglot-ensure 90))

(provide 'p3-r-language-server)

;;; p3-r-language-server.el ends here
