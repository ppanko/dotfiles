;;; p3-packages.el --- Resilient package lifecycle helpers -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep package bootstrap version-aware without hard-coding dependency
;; versions.  Requirements come from package metadata.  Package mutations
;; leave a marker so stale bytecode is rebuilt in a fresh Emacs process before
;; the normal configuration is loaded.

;;; Code:

(require 'cl-lib)
(require 'package)
(require 'seq)

(declare-function use-package-as-symbol "use-package-core" (name))
(declare-function use-package-pin-package "use-package-ensure" (package archive))

(defvar p3/package-refresh-attempted nil
  "Non-nil after this Emacs session has attempted an archive refresh.")

(defvar p3/package-restart-required nil
  "Non-nil when package state changed and normal config loading should stop.")

(defvar p3/package-rebuild-marker
  (expand-file-name ".package-rebuild-needed" user-emacs-directory)
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

(defun p3/package-recompile-if-needed ()
  "Recompile installed packages once when the rebuild marker exists.
Delete the marker only after a successful recompilation."
  (when (file-exists-p p3/package-rebuild-marker)
    (package-recompile-all)
    (delete-file p3/package-rebuild-marker)
    (setq p3/package-restart-required nil)))

(defun p3/package-installed-desc (package)
  "Return the newest externally installed descriptor for PACKAGE, or nil."
  (let ((descriptors (cdr (assq package package-alist))))
    (car
     (sort (copy-sequence descriptors)
           (lambda (a b)
             (version-list-< (package-desc-version b)
                             (package-desc-version a)))))))

(defun p3/package-unsatisfied-requirements (descriptor)
  "Return unsatisfied version requirements declared by DESCRIPTOR."
  (seq-filter
   (lambda (requirement)
     (not (package-installed-p (car requirement) (cadr requirement))))
   (package-desc-reqs descriptor)))

(defun p3/package-archive-desc (package minimum-version)
  "Return newest archive descriptor for PACKAGE satisfying MINIMUM-VERSION."
  (let ((descriptors (cdr (assq package package-archive-contents))))
    (car
     (sort
      (seq-filter
       (lambda (descriptor)
         (not (version-list-< (package-desc-version descriptor)
                             minimum-version)))
       (copy-sequence descriptors))
      (lambda (a b)
        (version-list-< (package-desc-version b)
                        (package-desc-version a)))))))

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
Refresh stale archive metadata once on failure.  Any successful installation
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

(defun p3/package-ensure-requirements (package &optional seen)
  "Ensure metadata-declared requirements for PACKAGE recursively.
SEEN prevents dependency cycles.  Requirement versions come only from package
metadata; this configuration does not encode dependency version numbers."
  (unless (memq package seen)
    (when-let ((descriptor (p3/package-installed-desc package)))
      (dolist (requirement (package-desc-reqs descriptor))
        (let ((dependency (car requirement))
              (minimum-version (cadr requirement)))
          (p3/package-install-resilient dependency minimum-version)
          (p3/package-ensure-requirements dependency (cons package seen)))))))

(defun p3/package-use-package-target (form)
  "Return the package ensured by a static use-package FORM, or nil."
  (when (and (consp form)
             (eq (car form) 'use-package)
             (symbolp (cadr form)))
    (let* ((name (cadr form))
           (arguments (cddr form))
           (ensure-tail (memq :ensure arguments)))
      (cond
       ((and ensure-tail (null (cadr ensure-tail))) nil)
       ((null ensure-tail) name)
       ((eq (cadr ensure-tail) t) name)
       ((symbolp (cadr ensure-tail)) (cadr ensure-tail))
       ((and (consp (cadr ensure-tail))
             (symbolp (car (cadr ensure-tail))))
        (car (cadr ensure-tail)))
       (t name)))))

(defun p3/package-config-packages (path)
  "Return statically declared package targets from use-package forms in PATH."
  (let (packages)
    (cl-labels
        ((walk
          (form)
          (when (consp form)
            (unless (memq (car form) '(quote function))
              (when-let ((package (p3/package-use-package-target form)))
                (unless (memq package packages)
                  (setq packages (append packages (list package)))))
              (mapc #'walk form)))))
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        (condition-case nil
            (while t
              (walk (read (current-buffer))))
          (end-of-file nil))))
    packages))

(defun p3/package-preflight-config (path)
  "Ensure package requirements for static use-package declarations in PATH.
Return non-nil only when the package graph was already healthy.  If package
state must be repaired, leave normal configuration loading for the next fresh
Emacs process."
  (condition-case err
      (progn
        (dolist (package (p3/package-config-packages path))
          (p3/package-install-resilient package)
          (p3/package-ensure-requirements package))
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
  "Ensure packages requested by use-package NAME with normalized ARGS."
  (dolist (ensure args)
    (let ((package (if (eq ensure t)
                       (use-package-as-symbol name)
                     ensure)))
      (when package
        (when (consp package)
          (use-package-pin-package (car package) (cdr package))
          (setq package (car package)))
        (condition-case err
            (progn
              (p3/package-install-resilient package)
              (p3/package-ensure-requirements package))
          (error
           (display-warning
            'use-package
            (format "Failed to install %s: %s"
                    package
                    (error-message-string err))
            :error))))))
  t)

(provide 'p3-packages)

;;; p3-packages.el ends here
