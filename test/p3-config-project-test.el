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
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt directory)
                         (when (equal directory (file-name-directory project-file))
                           'fake-project)))
                      ((symbol-function 'project-root)
                       (lambda (_project) root)))
              (p3/project-route-file loose-file)
              (should (p3-config-project-test--general-tab-p
                       (p3-config-project-test--current-tab)))
              (p3/project-route-file project-file)
              (should
               (equal (alist-get 'p3-project-root
                                 (cdr (p3-config-project-test--current-tab)))
                      (p3/project-normalize-root root))))))
      (when (file-exists-p loose-file) (delete-file loose-file))
      (delete-directory root t))))

(ert-deftest p3-config-project-routing-ignores-nil-and-remote-files ()
  (p3-config-project-test--with-clean-tabs
    (let ((tab-count (length (tab-bar-tabs))))
      (p3/project-route-file nil)
      (p3/project-route-file "/ssh:example:/tmp/file.txt")
      (let ((default-directory "/ssh:example:/tmp/"))
        (cl-letf (((symbol-function 'project-current)
                   (lambda (&rest _)
                     (ert-fail "project detection attempted for remote file"))))
          (p3/project-route-file "relative.txt")))
      (should (= (length (tab-bar-tabs)) tab-count))
      (should-not (p3-config-project-test--general-tab-p
                   (p3-config-project-test--current-tab))))))

(ert-deftest p3-config-project-routes-displayed-visits-not-background-reads ()
  (let* ((p3/config-lisp-directory
          (expand-file-name "lisp" p3-config-project-test--root))
         (find-file-hook nil)
         (project-root (make-temp-file "p3-routing-current-project-" t))
         (loose-root (make-temp-file "p3-routing-loose-root-" t))
         (loose-file (expand-file-name "loose.txt" loose-root)))
    (unwind-protect
        (progn
          (with-temp-file loose-file (insert "loose\n"))
          (p3-config-project-test--with-clean-tabs
            (p3/config-load-module 'p3-config-project)
            (p3/project-switch-to-tab project-root)
            (let ((project-tab-count (length (tab-bar-tabs))))
              (find-file-noselect loose-file)
              (should (= (length (tab-bar-tabs)) project-tab-count))
              (should
               (equal (alist-get 'p3-project-root
                                 (cdr (p3-config-project-test--current-tab)))
                      (p3/project-normalize-root project-root)))
              (find-file loose-file)
              (should (p3-config-project-test--general-tab-p
                       (p3-config-project-test--current-tab)))
              (should (file-equal-p buffer-file-name loose-file)))))
      (when-let ((buffer (get-file-buffer loose-file)))
        (kill-buffer buffer))
      (delete-directory loose-root t)
      (delete-directory project-root t))))

(ert-deftest p3-config-project-wires-routing-to-file-opening-commands ()
  (let ((p3/config-lisp-directory
         (expand-file-name "lisp" p3-config-project-test--root))
        (find-file-hook nil))
    (p3/config-load-module 'p3-config-project)
    (should-not (memq #'p3/project-route-current-file find-file-hook))
    (should (advice-member-p #'p3/project-route-file 'find-file))
    (should (advice-member-p #'p3/project-route-file 'find-file-other-window))
    (should (advice-member-p #'p3/project-route-file 'find-file-read-only))))

(provide 'p3-config-project-test)

;;; p3-config-project-test.el ends here
