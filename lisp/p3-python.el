;;; p3-python.el --- Python workflow helpers -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'python)
(require 'seq)
(require 'p3-project)

(defvar eglot-server-programs)

(defvar p3/python-language-server-bootstrap-failed nil
  "System-Python/server key whose basedpyright bootstrap failed this session.")

(defvar p3/python-language-server-warning-shown nil
  "Non-nil after warning that managed basedpyright needs explicit bootstrap.")

(defun p3/python-project-interpreter ()
  "Return the project-local Python executable, when one exists."
  (when-let ((root (p3/project-root)))
    (seq-some
     (lambda (relative)
       (let ((executable (expand-file-name relative root)))
         (and (file-executable-p executable) executable)))
     (if (eq system-type 'windows-nt)
         '(".venv/Scripts/python.exe" "venv/Scripts/python.exe")
       '(".venv/bin/python" "venv/bin/python")))))

(defun p3/python-setup-project-interpreter ()
  "Use a project's `.venv` or `venv` interpreter for this buffer."
  (when-let ((interpreter (p3/python-project-interpreter)))
    (setq-local python-shell-interpreter interpreter)
    (setq-local python-shell-virtualenv-root
                (file-name-directory
                 (directory-file-name
                  (file-name-directory interpreter))))))

(defun p3/python-display-shell ()
  "Start the Python shell and display it without leaving the source buffer."
  (interactive)
  (let ((process
         (or (python-shell-get-process)
             (save-window-excursion
               (run-python (python-shell-calculate-command) nil nil)))))
    (display-buffer (process-buffer process))))

(defun p3/python-tools-path (file)
  "Return FILE's path in the OS-specific Python tools environment."
  (expand-file-name
   file
   (expand-file-name
    (if (eq system-type 'windows-nt)
        "python-tools/windows/"
      "python-tools/linux/")
    user-emacs-directory)))

(defun p3/python-language-server-executable ()
  "Return managed basedpyright when it is already prepared, or nil.
This readiness check performs no provisioning and is safe in file-visit hooks."
  (let ((server
         (p3/python-tools-path
          (if (eq system-type 'windows-nt)
              "Scripts/basedpyright-langserver.exe"
            "bin/basedpyright-langserver"))))
    (and (file-executable-p server) server)))

(defun p3/python-ensure-language-server ()
  "Install and return the managed basedpyright language-server executable.

A failed bootstrap is attempted only once per system-Python/server pair during
an Emacs session.  Use `p3/python-bootstrap-language-server' to retry after
fixing the underlying problem."
  (let* ((windows-p (eq system-type 'windows-nt))
         (system-python (or (executable-find (if windows-p "python" "python3"))
                            (executable-find "python")))
         (tool-python (p3/python-tools-path
                       (if windows-p "Scripts/python.exe" "bin/python")))
         (server (p3/python-tools-path
                  (if windows-p
                      "Scripts/basedpyright-langserver.exe"
                    "bin/basedpyright-langserver")))
         (key (cons system-python server)))
    (cond
     ((file-executable-p server)
      (setq p3/python-language-server-bootstrap-failed nil)
      server)
     ((null system-python)
      nil)
     ((equal p3/python-language-server-bootstrap-failed key)
      nil)
     (t
      (condition-case err
          (progn
            (make-directory (file-name-directory tool-python) t)
            (unless (file-executable-p tool-python)
              (call-process system-python nil "*p3-python-bootstrap*" nil
                            "-m" "venv"
                            (file-name-directory
                             (directory-file-name
                              (file-name-directory tool-python)))))
            (when (file-executable-p tool-python)
              (message "Installing basedpyright for Python support...")
              (call-process tool-python nil "*p3-python-bootstrap*" nil
                            "-m" "pip" "install" "--upgrade" "basedpyright"))
            (if (file-executable-p server)
                (progn
                  (setq p3/python-language-server-bootstrap-failed nil)
                  server)
              (setq p3/python-language-server-bootstrap-failed key)
              (display-warning
               'p3/python
               (concat
                "Could not prepare basedpyright. Python editing remains available; "
                "see *p3-python-bootstrap*, fix the underlying problem, then run "
                "M-x p3/python-bootstrap-language-server to retry.")
               :warning)
              nil))
        (error
         (setq p3/python-language-server-bootstrap-failed key)
         (display-warning
          'p3/python
          (format
           (concat
            "Could not prepare basedpyright: %s. Python editing remains available; "
            "see *p3-python-bootstrap*, fix the underlying problem, then run "
            "M-x p3/python-bootstrap-language-server to retry.")
           (error-message-string err))
          :warning)
         nil))))))

;;;###autoload
(defun p3/python-bootstrap-language-server ()
  "Retry preparation of the managed basedpyright language server."
  (interactive)
  (setq p3/python-language-server-bootstrap-failed nil
        p3/python-language-server-warning-shown nil)
  (if-let ((server (p3/python-ensure-language-server)))
      (message "Python language server ready: %s" (abbreviate-file-name server))
    (user-error
     "Python language-server bootstrap failed; see *p3-python-bootstrap*")))

(defun p3/python-eglot-ensure ()
  "Start Eglot when managed basedpyright is already prepared.
Never create environments or install packages from a file-visit hook."
  (if-let ((server (p3/python-language-server-executable)))
      (progn
        (setq p3/python-language-server-warning-shown nil)
        (require 'eglot)
        (setq eglot-server-programs
              (cons `((python-mode python-ts-mode) . (,server "--stdio"))
                    (cl-remove-if
                     (lambda (entry)
                       (equal (car entry) '(python-mode python-ts-mode)))
                     eglot-server-programs)))
        (eglot-ensure))
    (unless p3/python-language-server-warning-shown
      (setq p3/python-language-server-warning-shown t)
      (display-warning
       'p3/python
       (concat
        "Managed basedpyright is not prepared. Python editing remains available; "
        "run M-x p3/python-bootstrap-language-server once to enable semantic support.")
       :warning))))

(defun p3/python-send-region-or-paragraph-and-step ()
  "Send the region, or current paragraph, then move to the next statement."
  (interactive)
  (let (beg end)
    (if (use-region-p)
        (setq beg (region-beginning)
              end (region-end))
      (mark-paragraph)
      (setq beg (region-beginning)
            end (region-end)))
    (python-shell-send-region beg end)
    (p3/python-display-shell)
    (goto-char end)
    (deactivate-mark)
    (python-nav-forward-statement)))

(defun p3/python-disable-flycheck ()
  "Disable Flycheck in Python buffers when Eglot/Flymake owns diagnostics."
  (when (and (boundp 'flycheck-mode)
             flycheck-mode
             (fboundp 'flycheck-mode))
    (flycheck-mode -1)))

(provide 'p3-python)

;;; p3-python.el ends here
