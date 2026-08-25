;;; p3-python.el --- Python workflow helpers -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'python)
(require 'seq)
(require 'p3-core)

(defvar eglot-server-programs)

(defun p3/python-project-interpreter ()
  "Return the project-local Python executable, when one exists."
  (when-let ((root (p3/project-el-root)))
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

(defun p3/python-ensure-language-server ()
  "Install and return the managed basedpyright language-server executable."
  (let* ((windows-p (eq system-type 'windows-nt))
         (system-python (or (executable-find (if windows-p "python" "python3"))
                            (executable-find "python")))
         (tool-python (p3/python-tools-path
                       (if windows-p "Scripts/python.exe" "bin/python")))
         (server (p3/python-tools-path
                  (if windows-p
                      "Scripts/basedpyright-langserver.exe"
                    "bin/basedpyright-langserver"))))
    (when (and system-python (not (file-executable-p server)))
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
                      "-m" "pip" "install" "--upgrade" "basedpyright")))
    (and (file-executable-p server) server)))

(defun p3/python-eglot-ensure ()
  "Start Eglot with the managed basedpyright language server."
  (when-let ((server (p3/python-ensure-language-server)))
    (require 'eglot)
    (setq eglot-server-programs
          (cons `((python-mode python-ts-mode) . (,server "--stdio"))
                (cl-remove-if
                 (lambda (entry)
                   (equal (car entry) '(python-mode python-ts-mode)))
                 eglot-server-programs)))
    (eglot-ensure)))

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
