;;; p3-config-project-test.el --- Native project config boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'project)
(require 'seq)
(require 'tab-bar)
(require 'p3-config-loader)
(require 'p3-project)

(defconst p3-config-project-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-project-test--contents (relative)
  "Return contents of repository file RELATIVE."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name relative p3-config-project-test--root))
    (buffer-string)))

(defun p3-config-project-test--current-tab ()
  "Return the current Tab Bar tab alist."
  (seq-find (lambda (tab) (eq (car tab) 'current-tab))
            (tab-bar-tabs)))

(defun p3-config-project-test--general-tab-p (tab)
  "Return non-nil when TAB is the General workspace."
  (alist-get 'p3-general-workspace (cdr tab)))

(defmacro p3-config-project-test--with-clean-tabs (&rest body)
  "Run BODY with one unclaimed tab, restoring frame state afterward."
  (declare (indent 0) (debug t))
  `(let ((saved-tabs (frame-parameter nil 'tabs))
         (saved-window-configuration (current-window-configuration)))
     (unwind-protect
         (progn
           (set-frame-parameter nil 'tabs nil)
           (tab-bar-tabs)
           (delete-other-windows)
           ,@body)
       (set-frame-parameter nil 'tabs saved-tabs)
       (set-window-configuration saved-window-configuration))))

(ert-deftest p3-config-project-binds-native-project-prefixes ()
  (let ((p3/config-lisp-directory
         (expand-file-name "lisp" p3-config-project-test--root))
        (old-c-c-p (lookup-key global-map (kbd "C-c p")))
        (old-s-p (lookup-key global-map (kbd "s-p"))))
    (unwind-protect
        (progn
          (p3/config-load-module 'p3-config-project)
          (should (featurep 'p3-config-project))
          (should (eq (lookup-key global-map (kbd "C-c p"))
                      project-prefix-map))
          (should (eq (lookup-key global-map (kbd "s-p"))
                      project-prefix-map))
          (should (eq (lookup-key global-map (kbd "C-x p"))
                      project-prefix-map)))
      (define-key global-map (kbd "C-c p") old-c-c-p)
      (define-key global-map (kbd "s-p") old-s-p))))

(ert-deftest p3-config-project-config-org-has-one-native-owner ()
  (let ((contents (p3-config-project-test--contents "config.org")))
    (should
     (string-match-p
      (regexp-quote "(p3/config-load-module 'p3-config-project)")
      contents))
    (dolist (forbidden '("(use-package projectile"
                          "p3/projectile-r-project-file-p"
                          "projectile-command-map"
                          "projectile-register-project-type"
                          "(projectile-mode +1)"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(ert-deftest p3-config-project-general-workspace-claims-current-tab ()
  (p3-config-project-test--with-clean-tabs
    (let ((tab-count (length (tab-bar-tabs))))
      (p3/project-switch-to-general-tab)
      (should (= (length (tab-bar-tabs)) tab-count))
      (should (p3-config-project-test--general-tab-p
               (p3-config-project-test--current-tab)))
      (should (equal (alist-get 'name
                                (cdr (p3-config-project-test--current-tab)))
                     "General")))))

(ert-deftest p3-config-project-general-workspace-is-reused ()
  (let ((root (make-temp-file "p3-general-workspace-project-" t)))
    (unwind-protect
        (p3-config-project-test--with-clean-tabs
          (p3/project-switch-to-general-tab)
          (p3/project-switch-to-tab root)
          (let ((tab-count (length (tab-bar-tabs))))
            (p3/project-switch-to-general-tab)
            (should (= (length (tab-bar-tabs)) tab-count))
            (should (p3-config-project-test--general-tab-p
                     (p3-config-project-test--current-tab)))))
      (delete-directory root t))))

(ert-deftest p3-config-project-routes-local-file-by-project-membership ()
  (let* ((root (make-temp-file "p3-file-routing-project-" t))
         (project-file (expand-file-name "inside.txt" root))
         (loose-file (make-temp-file "p3-file-routing-loose-")))
    (unwind-protect
        (progn
          (with-temp-file project-file (insert "inside\n"))
          (p3-config-project-test--with-clean-tabs
            (with-temp-buffer
              (setq buffer-file-name loose-file)
              (cl-letf (((symbol-function 'project-current)
                         (lambda (&optional _maybe-prompt _directory) nil)))
                (p3/project-route-current-file)
                (should (p3-config-project-test--general-tab-p
                         (p3-config-project-test--current-tab)))))
            (with-temp-buffer
              (setq buffer-file-name project-file)
              (cl-letf (((symbol-function 'project-current)
                         (lambda (&optional _maybe-prompt _directory)
                           'fake-project))
                        ((symbol-function 'project-root)
                         (lambda (_project) root)))
                (p3/project-route-current-file)
                (should
                 (equal (alist-get 'p3-project-root
                                   (cdr (p3-config-project-test--current-tab)))
                        (p3/project-normalize-root root)))))))
      (when (file-exists-p loose-file) (delete-file loose-file))
      (delete-directory root t))))

(ert-deftest p3-config-project-routing-ignores-nonfile-and-remote-buffers ()
  (p3-config-project-test--with-clean-tabs
    (let ((tab-count (length (tab-bar-tabs))))
      (with-temp-buffer
        (setq buffer-file-name nil)
        (p3/project-route-current-file))
      (with-temp-buffer
        (setq buffer-file-name "/ssh:example:/tmp/file.txt")
        (p3/project-route-current-file))
      (should (= (length (tab-bar-tabs)) tab-count))
      (should-not (p3-config-project-test--general-tab-p
                   (p3-config-project-test--current-tab))))))

(ert-deftest p3-config-project-wires-file-routing-through-find-file-hook ()
  (let ((p3/config-lisp-directory
         (expand-file-name "lisp" p3-config-project-test--root))
        (find-file-hook find-file-hook))
    (p3/config-load-module 'p3-config-project)
    (should (memq #'p3/project-route-current-file find-file-hook))))

(provide 'p3-config-project-test)

;;; p3-config-project-test.el ends here
