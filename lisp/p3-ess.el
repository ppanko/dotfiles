;;; p3-ess.el --- Project-aware ESS runtime behavior -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep ESS process ownership and project-session coordination out of the
;; literate configuration.  Project identity is delegated to p3-project so ESS,
;; Python, R helpers, and terminal workflows use the same root abstraction.

;;; Code:

(require 'p3-project)

(declare-function R "ess-r-mode")

(defvar ess-local-process-name nil)

(defvar p3/ess-project-processes
  (make-hash-table :test #'equal)
  "Map project roots to ESS process names.")

(defvar-local p3/ess-project-root-cache nil
  "Cached project root for the current buffer.")

(defun p3/ess-project-root ()
  "Return the current shared project root, caching it buffer-locally."
  (or p3/ess-project-root-cache
      (setq p3/ess-project-root-cache
            (file-name-as-directory
             (expand-file-name (or (p3/project-root) default-directory))))))

(defun p3/ess-process-live-p (name)
  "Return non-nil if NAME names a live process."
  (when-let ((process (get-process name)))
    (process-live-p process)))

(defun p3/ess-project-process ()
  "Return the live ESS process name for the current project, or nil."
  (let* ((root (p3/ess-project-root))
         (name (gethash root p3/ess-project-processes)))
    (cond
     ((null name)
      nil)
     ((p3/ess-process-live-p name)
      name)
     (t
      (remhash root p3/ess-project-processes)
      nil))))

(defun p3/ess-register-current-process ()
  "Register the current inferior ESS process to its project."
  (when (and (derived-mode-p 'inferior-ess-mode)
             ess-local-process-name)
    (puthash (p3/ess-project-root)
             ess-local-process-name
             p3/ess-project-processes)))

(defun p3/ess-ensure-project-process (&rest _)
  "Ensure the current source buffer has a project-specific ESS process."
  (let ((process (p3/ess-project-process)))
    (unless process
      ;; Lazily create R only when evaluation is requested.  Keep this
      ;; interactive so ESS retains its normal startup/prompt behavior.
      (save-window-excursion
        (call-interactively #'R))
      (setq process (p3/ess-project-process)))
    (unless process
      (user-error "Unable to create ESS process"))
    (setq-local ess-local-process-name process)))

(defun p3/ess-force-buffer-current-symbol ()
  "Return the ESS function guarded by project-process advice."
  'ess-force-buffer-current)

(defun p3/ess-install-process-advice ()
  "Install project-process selection advice exactly once."
  (let ((target (p3/ess-force-buffer-current-symbol)))
    (when (and (fboundp target)
               (not (advice-member-p #'p3/ess-ensure-project-process target)))
      (advice-add target :before #'p3/ess-ensure-project-process))))

(defun p3/ess-setup ()
  "Install project-aware ESS hooks and process-selection advice."
  (add-hook 'inferior-ess-mode-hook #'p3/ess-register-current-process)
  (if (featurep 'ess-inf)
      (p3/ess-install-process-advice)
    (with-eval-after-load 'ess-inf
      (p3/ess-install-process-advice))))

(provide 'p3-ess)

;;; p3-ess.el ends here
