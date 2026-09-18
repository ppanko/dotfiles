;;; p3-package.el --- Resilient package bootstrap -*- lexical-binding: t; -*-

(require 'package)

(defvar p3/package-refresh-attempted nil
  "Non-nil after this Emacs session has attempted an automatic archive refresh.")

(declare-function use-package-as-symbol "use-package-core" (name))
(declare-function use-package-pin-package "use-package-ensure" (package archive))

(defun p3/package-setup ()
  "Configure package archives and initialize installed packages."
  (setq package-archives
        '(("gnu" . "https://elpa.gnu.org/packages/")
          ("nongnu" . "https://elpa.nongnu.org/nongnu/")
          ("melpa" . "https://melpa.org/packages/"))
        package-archive-priorities
        '(("gnu" . 30)
          ("nongnu" . 20)
          ("melpa" . 10)))
  (package-initialize))

(defun p3/package-refresh-once ()
  "Refresh package metadata at most once automatically per Emacs session."
  (unless p3/package-refresh-attempted
    (setq p3/package-refresh-attempted t)
    (package-refresh-contents)))

(defun p3/package-prepare-pinned-package (package)
  "Reload archive metadata needed for pinned PACKAGE, if any."
  (when (assoc package (bound-and-true-p package-pinned-packages))
    (package-read-all-archive-contents)))

(defun p3/package--descriptors (package)
  "Return installed descriptors recorded for PACKAGE."
  (cdr (assq package package-alist)))

(defun p3/package--descriptor-autoload-file (descriptor)
  "Return the generated autoload file for DESCRIPTOR."
  (let ((directory (package-desc-dir descriptor)))
    (when (stringp directory)
      (expand-file-name
       (format "%s-autoloads.el" (package-desc-name descriptor))
       directory))))

(defun p3/package--descriptor-healthy-p (descriptor)
  "Return non-nil when DESCRIPTOR has a usable installed package directory."
  (let ((directory (package-desc-dir descriptor))
        (autoload-file (p3/package--descriptor-autoload-file descriptor)))
    (and (stringp directory)
         (file-directory-p directory)
         autoload-file
         (or (file-readable-p autoload-file)
             (file-readable-p (concat autoload-file "c"))))))

(defun p3/package-installation-healthy-p (package)
  "Return non-nil when PACKAGE is built in or its newest install is complete."
  (or (package-built-in-p package)
      (let ((descriptor (car (p3/package--descriptors package))))
        (and descriptor
             (p3/package--descriptor-healthy-p descriptor)))))

(defun p3/package--repair-current-installation (package)
  "Regenerate PACKAGE autoloads when its installed directory is recoverable."
  (let* ((descriptor (car (p3/package--descriptors package)))
         (directory (and descriptor (package-desc-dir descriptor))))
    (when (and descriptor
               (stringp directory)
               (file-directory-p directory))
      (condition-case nil
          (progn
            (package-generate-autoloads package directory)
            (p3/package--descriptor-healthy-p descriptor))
        (error nil)))))

(defun p3/package--user-package-directory-p (directory)
  "Return non-nil when DIRECTORY is safely contained in `package-user-dir'."
  (and (stringp directory)
       (file-directory-p package-user-dir)
       (file-exists-p directory)
       (file-in-directory-p
        (file-truename directory)
        (file-name-as-directory (file-truename package-user-dir)))))

(defun p3/package--forget-broken-descriptor (package descriptor)
  "Forget broken DESCRIPTOR for PACKAGE and remove its user package directory."
  (let* ((directory (package-desc-dir descriptor))
         (remaining
          (delq descriptor
                (copy-sequence (p3/package--descriptors package)))))
    (when (stringp directory)
      (setq load-path (delete directory load-path))
      (when (p3/package--user-package-directory-p directory)
        (delete-directory directory t)))
    (setq package-alist (assq-delete-all package package-alist)
          package-activated-list (delq package package-activated-list))
    (when remaining
      (push (cons package remaining) package-alist))))

(defun p3/package--install-with-refresh (package)
  "Install PACKAGE, refreshing stale archive metadata once on failure."
  (p3/package-prepare-pinned-package package)
  (condition-case _first-error
      (package-install package t)
    (error
     (p3/package-refresh-once)
     (p3/package-prepare-pinned-package package)
     (package-install package t))))

(defun p3/package-install-resilient (package)
  "Ensure PACKAGE is complete, repairing or reinstalling it when necessary."
  (let ((changed nil))
    (when (and (package-installed-p package)
               (not (p3/package-installation-healthy-p package)))
      (setq changed t)
      (unless (p3/package--repair-current-installation package)
        (let ((descriptor (car (p3/package--descriptors package))))
          (when descriptor
            (p3/package--forget-broken-descriptor package descriptor)))))

    (unless (p3/package-installation-healthy-p package)
      (setq changed t)
      (p3/package--install-with-refresh package))

    (unless (p3/package-installation-healthy-p package)
      (error
       "Package `%s' is incomplete after repair/install; expected readable generated autoloads"
       package))

    (when (and changed (not (package-built-in-p package)))
      (setq package-activated-list (delq package package-activated-list))
      (unless (package-activate package t)
        (error "Package `%s' could not be activated after repair/install" package)))
    package))

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
            (p3/package-install-resilient package)
          (error
           (error "Package bootstrap failed for `%s': %s"
                  package
                  (error-message-string err)))))))
  t)

(provide 'p3-package)

;;; p3-package.el ends here
