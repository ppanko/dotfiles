;;; p3-packages.el --- Resilient package lifecycle helpers -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep package bootstrap version-aware without hard-coding dependency
;; versions. Requirements come from installed package metadata. Package
;; mutations leave a marker so user-installed bytecode is rebuilt in a fresh
;; Emacs process before the normal configuration is loaded.

;;; Code:

(require 'cl-lib)
(require 'package)
(require 'seq)

(declare-function use-package-as-symbol "use-package-core" (name))
(declare-function use-package-pin-package "use-package-ensure" (package archive))

(define-error 'p3/package-restart-needed
  "Package state changed; restart Emacs before loading repaired packages")

(defvar p3/package-refresh-attempted nil
  "Non-nil after this Emacs session has attempted an archive refresh.")

(defvar p3/package-restart-required nil
  "Non-nil when package state changed and normal config loading should stop.")

(defvar p3/package-rebuild-marker
  (expand-file-name ".p3-rebuild-needed" package-user-dir)
  "Marker file requesting one fresh-process package recompilation.")

(defun p3/package-refresh-once ()
  "Refresh package metadata at most once automatically per Emacs session."
  (unless p3/package-refresh-attempted
    (setq p3/package-refresh-attempted t)
    (package-refresh-contents)))

(defun p3/package-prepare-pinned-package (package)
  "Reload archive metadata needed for pinned PACKAGE, if any."
  (when (assoc package (bound-and-true-p package-pinned-packages))
    (package-read-all-archive-contents)))

(defun p3/package-mark-rebuild-needed ()
  "Record that package bytecode must be rebuilt on the next fresh startup."
  (make-directory (file-name-directory p3/package-rebuild-marker) t)
  (with-temp-file p3/package-rebuild-marker
    (insert "Package state changed; rebuild before loading config.\n"))
  (setq p3/package-restart-required t))

(defun p3/package-user-installed-descs ()
  "Return active package descriptors owned by `package-user-dir'."
  (let ((root (file-name-as-directory (expand-file-name package-user-dir))))
    (cl-loop
     for (_package . descriptors) in package-alist
     for descriptor = (car descriptors)
     for directory = (and descriptor (package-desc-dir descriptor))
     when (and (stringp directory)
               (file-in-directory-p (expand-file-name directory) root))
     collect descriptor)))

(defun p3/package-recompile-user-packages ()
  "Recompile active package.el packages installed under `package-user-dir'."
  (dolist (descriptor (p3/package-user-installed-descs))
    (package-recompile descriptor)))

(defun p3/package-recompile-if-needed ()
  "Recompile user packages once when the rebuild marker exists.
Delete the marker only after every recompilation succeeds."
  (when (file-exists-p p3/package-rebuild-marker)
    (p3/package-recompile-user-packages)
    (delete-file p3/package-rebuild-marker)
    (setq p3/package-restart-required nil)))

(defun p3/package-installed-desc (package)
  "Return the active externally installed descriptor for PACKAGE, or nil."
  (cadr (assq package package-alist)))

(defun p3/package-unsatisfied-requirements (descriptor)
  "Return unsatisfied version requirements declared by DESCRIPTOR."
  (seq-filter
   (lambda (requirement)
     (not (package-installed-p (car requirement) (cadr requirement))))
   (package-desc-reqs descriptor)))

(defun p3/package-archive-desc (package minimum-version)
  "Return preferred archive descriptor satisfying MINIMUM-VERSION for PACKAGE.
`package-archive-contents' is already ordered by package/archive priority, so
preserve that ordering instead of choosing solely by numerical version."
  (seq-find
   (lambda (descriptor)
     (not (version-list-< (package-desc-version descriptor)
                         minimum-version)))
   (cdr (assq package package-archive-contents))))

(defun p3/package-install-from-archive (package minimum-version)
  "Install PACKAGE, requiring MINIMUM-VERSION when non-nil.
Versioned installs use an archive descriptor directly so an outdated built-in
package cannot incorrectly satisfy the request."
  (if minimum-version
      (progn
        (unless (assq package package-archive-contents)
          (p3/package-refresh-once)
          (p3/package-prepare-pinned-package package))
        (let ((descriptor (p3/package-archive-desc package minimum-version)))
          (unless descriptor
            (error "No archive version of %s satisfies %s"
                   package (package-version-join minimum-version)))
          (let ((package-install-upgrade-built-in t))
            (package-install descriptor t))))
    (package-install package t)))

(defun p3/package-install-resilient (package &optional minimum-version)
  "Ensure PACKAGE is installed at optional MINIMUM-VERSION.
Refresh stale archive metadata once on failure. Any successful installation
marks the package tree for recompilation in a fresh Emacs process."
  (unless (package-installed-p package minimum-version)
    (p3/package-prepare-pinned-package package)
    (condition-case _first-error
        (p3/package-install-from-archive package minimum-version)
      (error
       (p3/package-refresh-once)
       (p3/package-prepare-pinned-package package)
       (p3/package-install-from-archive package minimum-version)))
    (p3/package-mark-rebuild-needed)))

(defun p3/package-bootstrap-ready-p ()
  "Prepare package state for normal configuration loading.
Recompile stale user bytecode first, then ensure `use-package' exists. Return
nil on any repair or failure so this Emacs process remains a stock recovery
session instead of loading a mixed package graph."
  (condition-case err
      (progn
        (p3/package-recompile-if-needed)
        (p3/package-install-resilient 'use-package)
        (not p3/package-restart-required))
    (error
     (display-warning
      'p3/package
      (format "Package bootstrap failed; loading stock Emacs only: %s"
              (error-message-string err))
      :error)
     nil)))

(defun p3/package-ensure-requirements (package &optional seen)
  "Ensure metadata-declared requirements for PACKAGE recursively.
SEEN prevents dependency cycles. Requirement versions come only from package
metadata; this configuration does not encode dependency version numbers."
  (unless (memq package seen)
    (when-let ((descriptor (p3/package-installed-desc package)))
      (dolist (requirement (p3/package-unsatisfied-requirements descriptor))
        (p3/package-install-resilient (car requirement) (cadr requirement)))
      (dolist (requirement (package-desc-reqs descriptor))
        (p3/package-ensure-requirements (car requirement)
                                        (cons package seen))))))

(defun p3/package-preflight-installed ()
  "Validate requirements for every installed external package.
Return non-nil only when the installed package graph was already healthy. If
repair is required or validation fails, leave normal config loading disabled
for this process so stock Emacs commands remain usable."
  (condition-case err
      (progn
        (dolist (entry package-alist)
          (p3/package-ensure-requirements (car entry)))
        (not p3/package-restart-required))
    (error
     (display-warning
      'p3/package
      (format "Package preflight failed; loading stock Emacs only: %s"
              (error-message-string err))
      :error)
     nil)))

(defun p3/package-menu-execute-with-rebuild-marker (original &rest args)
  "Mark package bytecode dirty before calling ORIGINAL with ARGS."
  (p3/package-mark-rebuild-needed)
  (apply original args))

(defun p3/package-install-update-advice ()
  "Arrange for package-menu mutations to request a fresh-process rebuild."
  (unless (advice-member-p #'p3/package-menu-execute-with-rebuild-marker
                           #'package-menu-execute)
    (advice-add #'package-menu-execute :around
                #'p3/package-menu-execute-with-rebuild-marker)))

(defun p3/use-package-ensure (name args _state)
  "Ensure packages requested by use-package NAME with normalized ARGS.
If installation or dependency repair changes package state, signal
`p3/package-restart-needed' so the current declaration cannot load against a
mixed old/new dependency graph. Installation failures propagate to use-package,
which catches and reports declaration errors without corrupting later startup."
  (dolist (ensure args)
    (let ((package (if (eq ensure t)
                       (use-package-as-symbol name)
                     ensure)))
      (when package
        (when (consp package)
          (use-package-pin-package (car package) (cdr package))
          (setq package (car package)))
        (p3/package-install-resilient package)
        (p3/package-ensure-requirements package))))
  (when p3/package-restart-required
    (signal 'p3/package-restart-needed nil))
  t)

(provide 'p3-packages)

;;; p3-packages.el ends here
