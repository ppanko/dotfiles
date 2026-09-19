;;; p3-package.el --- Resilient package bootstrap -*- lexical-binding: t; -*-

(require 'package)

(defvar p3/package-refresh-attempted nil
  "Non-nil after this Emacs session has attempted an automatic archive refresh.")

(declare-function use-package-as-symbol "use-package-core" (name))
(declare-function use-package-pin-package "use-package-ensure" (package archive))

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

(defun p3/package--archive-descriptor (package)
  "Return the selected archive descriptor for PACKAGE, if cached."
  (cadr (assq package package-archive-contents)))

(defun p3/package--user-package-directory-p (directory)
  "Return non-nil when DIRECTORY is contained in package-user-dir."
  (and (stringp directory)
       (file-directory-p package-user-dir)
       (file-in-directory-p
        (expand-file-name directory)
        (file-name-as-directory (file-truename package-user-dir)))))

(defun p3/package--descriptor-autoload-file (descriptor)
  "Return the generated autoload file for DESCRIPTOR."
  (let ((directory (package-desc-dir descriptor)))
    (when (stringp directory)
      (expand-file-name
       (format "%s-autoloads.el" (package-desc-name descriptor))
       directory))))

(defun p3/package--descriptor-healthy-p (descriptor)
  "Return non-nil when user DESCRIPTOR has usable generated autoloads."
  (let ((directory (package-desc-dir descriptor))
        (autoload-file (p3/package--descriptor-autoload-file descriptor)))
    (and (p3/package--user-package-directory-p directory)
         (file-directory-p directory)
         autoload-file
         (or (file-readable-p autoload-file)
             (file-readable-p (concat autoload-file "c"))))))

(defun p3/package-installation-healthy-p (package)
  "Return non-nil when PACKAGE is built in or outside repair scope.
User-installed packages must have a package directory and generated
autoloads."
  (or (package-built-in-p package)
      (let ((descriptor (car (p3/package--descriptors package))))
        (and descriptor
             (or (not (p3/package--user-package-directory-p
                       (package-desc-dir descriptor)))
                 (p3/package--descriptor-healthy-p descriptor))))))

(defun p3/package--repair-current-installation (package)
  "Regenerate PACKAGE autoloads when its user install is recoverable."
  (let* ((descriptor (car (p3/package--descriptors package)))
         (directory (and descriptor (package-desc-dir descriptor))))
    (when (and descriptor
               (p3/package--user-package-directory-p directory)
               (file-directory-p directory))
      (condition-case nil
          (progn
            (package-generate-autoloads package directory)
            (p3/package--descriptor-healthy-p descriptor))
        (error nil)))))

(defun p3/package--repair-incomplete-installed-packages ()
  "Repair missing generated autoloads before package activation."
  (dolist (entry package-alist)
    (let ((package (car entry))
          (descriptor (cadr entry)))
      (when (and descriptor
                 (p3/package--user-package-directory-p
                  (package-desc-dir descriptor))
                 (not (p3/package--descriptor-healthy-p descriptor)))
        (p3/package--repair-current-installation package)))))

(defun p3/package-setup ()
  "Configure package archives, repair local installs, and initialize packages."
  (setq package-archives
        '(("gnu" . "https://elpa.gnu.org/packages/")
          ("nongnu" . "https://elpa.nongnu.org/nongnu/")
          ("melpa" . "https://melpa.org/packages/"))
        package-archive-priorities
        '(("gnu" . 30)
          ("nongnu" . 20)
          ("melpa" . 10)))
  ;; Initialize the installed-package records without activating them.
  ;; Repair missing autoloads, then activate the repaired set once.
  (package-initialize t)
  (p3/package--repair-incomplete-installed-packages)
  (package-activate-all))

(defun p3/package--discard-broken-descriptor (package descriptor)
  "Discard broken user DESCRIPTOR for PACKAGE before reinstalling it."
  (let ((directory (package-desc-dir descriptor)))
    (unless (p3/package--user-package-directory-p directory)
      (error "Refusing to delete non-user package %s" package))
    (setq load-path (delete directory load-path))
    (if (file-directory-p directory)
        (package-delete descriptor t t)
      (let ((remaining
             (delq descriptor
                   (copy-sequence (p3/package--descriptors package)))))
        (setq package-alist (assq-delete-all package package-alist)
              package-activated-list (delq package package-activated-list))
        (when remaining
          (push (cons package remaining) package-alist))))))

(defun p3/package--install-with-refresh (package)
  "Install PACKAGE, refreshing stale archive metadata once on failure."
  (p3/package-prepare-pinned-package package)
  (condition-case _first-error
      (package-install (or (p3/package--archive-descriptor package)
                           package)
                       t)
    (error
     (p3/package-refresh-once)
     (p3/package-prepare-pinned-package package)
     (package-install (or (p3/package--archive-descriptor package)
                          package)
                      t))))

(defun p3/package-install-resilient (package)
  "Ensure PACKAGE is complete, repairing or reinstalling it when necessary."
  (let ((changed nil)
        (required-version nil))
    (when (and (package-installed-p package)
               (not (p3/package-installation-healthy-p package)))
      (setq changed t)
      (let ((descriptor (car (p3/package--descriptors package))))
        (setq required-version
              (and descriptor (package-desc-version descriptor)))
        (unless (p3/package--repair-current-installation package)
          (when descriptor
            (p3/package--discard-broken-descriptor package descriptor)))))

    (when (or required-version
              (not (p3/package-installation-healthy-p package)))
      (setq changed t)
      (p3/package--install-with-refresh package))

    (let ((descriptor (car (p3/package--descriptors package))))
      (unless (and descriptor
                   (or (null required-version)
                       (version-list-<=
                        required-version
                        (package-desc-version descriptor)))
                   (p3/package-installation-healthy-p package))
        (error
         "Package %s is incomplete after repair/install; expected a healthy package"
         package)))

    (when (and changed (not (package-built-in-p package)))
      (setq package-activated-list (delq package package-activated-list))
      (unless (package-activate package t)
        (error "Package %s could not be activated after repair/install"
               package)))
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
           (error "Package bootstrap failed for %s: %s"
                  package
                  (error-message-string err))))
  t))))

(provide 'p3-package)

;;; p3-package.el ends here
