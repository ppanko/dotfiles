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

(defun p3-config-project-test--tab-root (tab)
  "Return TAB's P3 project root, if any."
  (alist-get 'p3-project-root (cdr tab)))

(defun p3-config-project-test--project-tab-roots ()
  "Return project tab roots in displayed left-to-right order."
  (delq nil
        (mapcar #'p3-config-project-test--tab-root (tab-bar-tabs))))

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

(ert-deftest p3-config-project-general-workspace-preserves-explicit-user-tab ()
  (p3-config-project-test--with-clean-tabs
    (tab-rename "Writing")
    (let ((tab-count (length (tab-bar-tabs))))
      (p3/project-switch-to-general-tab)
      (should (= (length (tab-bar-tabs)) (1+ tab-count)))
      (should (p3-config-project-test--general-tab-p
               (p3-config-project-test--current-tab)))
      (should
       (seq-some
        (lambda (tab)
          (and (equal (alist-get 'name (cdr tab)) "Writing")
               (alist-get 'explicit-name (cdr tab))
               (not (p3-config-project-test--general-tab-p tab))))
        (tab-bar-tabs))))))

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

(ert-deftest p3-config-project-switching-existing-file-buffer-routes-workspace ()
  (let* ((p3/config-lisp-directory
          (expand-file-name "lisp" p3-config-project-test--root))
         (root-a (make-temp-file "p3-buffer-route-a-" t))
         (root-b (make-temp-file "p3-buffer-route-b-" t))
         (file-b (expand-file-name "inside-b.txt" root-b))
         buffer-b)
    (unwind-protect
        (progn
          (with-temp-file file-b (insert "inside b\n"))
          (setq buffer-b (find-file-noselect file-b))
          (p3-config-project-test--with-clean-tabs
            (p3/config-load-module 'p3-config-project)
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt directory)
                         (cond
                          ((and directory
                                (file-in-directory-p directory root-a))
                           'project-a)
                          ((and directory
                                (file-in-directory-p directory root-b))
                           'project-b))))
                      ((symbol-function 'project-root)
                       (lambda (project)
                         (pcase project
                           ('project-a root-a)
                           ('project-b root-b)))))
              (p3/project-switch-to-tab root-a)
              (switch-to-buffer buffer-b)
              (should
               (equal (alist-get 'p3-project-root
                                 (cdr (p3-config-project-test--current-tab)))
                      (p3/project-normalize-root root-b))))))
      (when (buffer-live-p buffer-b) (kill-buffer buffer-b))
      (delete-directory root-a t)
      (delete-directory root-b t))))

(ert-deftest p3-config-project-split-keeps-cross-project-buffer-local ()
  (let* ((p3/config-lisp-directory
          (expand-file-name "lisp" p3-config-project-test--root))
         (root-a (make-temp-file "p3-split-route-a-" t))
         (root-b (make-temp-file "p3-split-route-b-" t))
         (file-a (expand-file-name "inside-a.txt" root-a))
         (file-b (expand-file-name "inside-b.txt" root-b))
         buffer-a
         buffer-b)
    (unwind-protect
        (progn
          (with-temp-file file-a (insert "inside a\n"))
          (with-temp-file file-b (insert "inside b\n"))
          (setq buffer-a (find-file-noselect file-a)
                buffer-b (find-file-noselect file-b))
          (p3-config-project-test--with-clean-tabs
            (p3/config-load-module 'p3-config-project)
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt directory)
                         (let ((dir (or directory default-directory)))
                           (cond
                            ((file-in-directory-p dir root-a) 'project-a)
                            ((file-in-directory-p dir root-b) 'project-b)))))
                      ((symbol-function 'project-root)
                       (lambda (project)
                         (pcase project
                           ('project-a root-a)
                           ('project-b root-b)))))
              (p3/project-switch-to-tab root-a)
              (switch-to-buffer buffer-a)
              (let* ((left (selected-window))
                     (right (split-window-right))
                     (tab-count (length (tab-bar-tabs)))
                     (root-a-normal (p3/project-normalize-root root-a))
                     (root-b-normal (p3/project-normalize-root root-b)))
                (select-window right)
                (switch-to-buffer buffer-b)
                (should (= (length (tab-bar-tabs)) tab-count))
                (should
                 (equal (p3-config-project-test--tab-root
                         (p3-config-project-test--current-tab))
                        root-a-normal))
                (should (eq (window-buffer right) buffer-b))
                (should (eq (window-buffer left) buffer-a))
                (should (equal (p3/project-normalize-root (p3/project-root))
                               root-b-normal))
                (select-window left)
                (should (equal (p3/project-normalize-root (p3/project-root))
                               root-a-normal))))))
      (when (buffer-live-p buffer-a) (kill-buffer buffer-a))
      (when (buffer-live-p buffer-b) (kill-buffer buffer-b))
      (delete-directory root-a t)
      (delete-directory root-b t))))

(ert-deftest p3-config-project-transient-popup-does-not-enable-split-routing ()
  (p3-config-project-test--with-clean-tabs
    (let ((popup (split-window-right)))
      (set-window-parameter popup 'quit-restore '(window window nil nil))
      (should (p3/project--workspace-routing-p))
      (set-window-parameter popup 'quit-restore nil)
      (should-not (p3/project--workspace-routing-p)))))

(ert-deftest p3-config-project-collapsed-cross-project-split-reconciles-workspace ()
  (let* ((p3/config-lisp-directory
          (expand-file-name "lisp" p3-config-project-test--root))
         (root-a (make-temp-file "p3-collapse-route-a-" t))
         (root-b (make-temp-file "p3-collapse-route-b-" t))
         (file-a (expand-file-name "inside-a.txt" root-a))
         (file-b (expand-file-name "inside-b.txt" root-b))
         buffer-a
         buffer-b)
    (unwind-protect
        (progn
          (with-temp-file file-a (insert "inside a\n"))
          (with-temp-file file-b (insert "inside b\n"))
          (setq buffer-a (find-file-noselect file-a)
                buffer-b (find-file-noselect file-b))
          (p3-config-project-test--with-clean-tabs
            (p3/config-load-module 'p3-config-project)
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt directory)
                         (let ((dir (or directory default-directory)))
                           (cond
                            ((file-in-directory-p dir root-a) 'project-a)
                            ((file-in-directory-p dir root-b) 'project-b)))))
                      ((symbol-function 'project-root)
                       (lambda (project)
                         (pcase project
                           ('project-a root-a)
                           ('project-b root-b)))))
              ;; Establish both canonical workspaces, then compose B inside A.
              (p3/project-switch-to-tab root-b)
              (switch-to-buffer buffer-b)
              (p3/project-switch-to-tab root-a)
              (switch-to-buffer buffer-a)
              (let* ((right (split-window-right))
                     (a (p3/project-normalize-root root-a))
                     (b (p3/project-normalize-root root-b)))
                (select-window right)
                (switch-to-buffer buffer-b)
                (should
                 (equal (p3-config-project-test--tab-root
                         (p3-config-project-test--current-tab))
                        a))
                (should (= (length (window-list nil 'nomini)) 2))

                ;; Keeping only B ends composition: B becomes the canonical
                ;; current workspace and A retains its pre-composition layout.
                (delete-other-windows)
                (should
                 (equal (p3-config-project-test--tab-root
                         (p3-config-project-test--current-tab))
                        b))
                (should
                 (equal (p3-config-project-test--project-tab-roots)
                        (list b a)))

                (p3/project-switch-to-tab root-a)
                (should (= (length (window-list nil 'nomini)) 2))
                (should-not (get-buffer-window buffer-b))))))
      (when (buffer-live-p buffer-a) (kill-buffer buffer-a))
      (when (buffer-live-p buffer-b) (kill-buffer buffer-b))
      (delete-directory root-a t)
      (delete-directory root-b t))))

(ert-deftest p3-config-project-other-window-file-visit-keeps-current-tab ()
  (let* ((p3/config-lisp-directory
          (expand-file-name "lisp" p3-config-project-test--root))
         (root-a (make-temp-file "p3-other-window-a-" t))
         (root-b (make-temp-file "p3-other-window-b-" t))
         (file-b (expand-file-name "inside-b.txt" root-b))
         buffer-b)
    (unwind-protect
        (progn
          (with-temp-file file-b (insert "inside b\n"))
          (p3-config-project-test--with-clean-tabs
            (p3/config-load-module 'p3-config-project)
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt directory)
                         (when (and directory
                                    (file-in-directory-p directory root-b))
                           'project-b)))
                      ((symbol-function 'project-root)
                       (lambda (_project) root-b)))
              (p3/project-switch-to-tab root-a)
              (let ((tab-count (length (tab-bar-tabs)))
                    (root-a-normal (p3/project-normalize-root root-a)))
                (find-file-other-window file-b)
                (should (= (length (tab-bar-tabs)) tab-count))
                (should (= (length (window-list nil 'nomini)) 2))
                (should
                 (window-parameter
                  (selected-window) 'p3-project-workspace-window))
                (should-not (p3/project--workspace-routing-p))
                (should
                 (equal (p3-config-project-test--tab-root
                         (p3-config-project-test--current-tab))
                        root-a-normal))
                (setq buffer-b
                      (seq-find
                       (lambda (buffer)
                         (when-let
                             ((visited
                               (buffer-local-value 'buffer-file-name buffer)))
                           (file-equal-p visited file-b)))
                       (buffer-list)))
                (should buffer-b)))))
      (when (buffer-live-p buffer-b)
        (kill-buffer buffer-b))
      (delete-directory root-a t)
      (delete-directory root-b t))))

(ert-deftest p3-config-project-native-tab-selection-updates-mru-order ()
  (let* ((p3/config-lisp-directory
          (expand-file-name "lisp" p3-config-project-test--root))
         (root-a (make-temp-file "p3-native-tab-a-" t))
         (root-b (make-temp-file "p3-native-tab-b-" t))
         (root-c (make-temp-file "p3-native-tab-c-" t)))
    (unwind-protect
        (p3-config-project-test--with-clean-tabs
          (p3/config-load-module 'p3-config-project)
          (let ((a (p3/project-normalize-root root-a))
                (b (p3/project-normalize-root root-b))
                (c (p3/project-normalize-root root-c)))
            (p3/project-switch-to-tab root-a)
            (p3/project-switch-to-tab root-b)
            (p3/project-switch-to-tab root-c)
            (should (equal (p3-config-project-test--project-tab-roots)
                           (list c b a)))
            (tab-bar-select-tab 3)
            (should (equal (p3-config-project-test--project-tab-roots)
                           (list a c b)))))
      (delete-directory root-a t)
      (delete-directory root-b t)
      (delete-directory root-c t))))

(ert-deftest p3-config-project-norecord-preview-keeps-current-workspace ()
  (let* ((p3/config-lisp-directory
          (expand-file-name "lisp" p3-config-project-test--root))
         (root-a (make-temp-file "p3-buffer-preview-a-" t))
         (root-b (make-temp-file "p3-buffer-preview-b-" t))
         (file-b (expand-file-name "inside-b.txt" root-b))
         buffer-b)
    (unwind-protect
        (progn
          (with-temp-file file-b (insert "inside b\n"))
          (setq buffer-b (find-file-noselect file-b))
          (p3-config-project-test--with-clean-tabs
            (p3/config-load-module 'p3-config-project)
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt directory)
                         (cond
                          ((and directory
                                (file-in-directory-p directory root-a))
                           'project-a)
                          ((and directory
                                (file-in-directory-p directory root-b))
                           'project-b))))
                      ((symbol-function 'project-root)
                       (lambda (project)
                         (pcase project
                           ('project-a root-a)
                           ('project-b root-b)))))
              (p3/project-switch-to-tab root-a)
              (switch-to-buffer buffer-b 'norecord)
              (should
               (equal (alist-get 'p3-project-root
                                 (cdr (p3-config-project-test--current-tab)))
                      (p3/project-normalize-root root-a))))))
      (when (buffer-live-p buffer-b) (kill-buffer buffer-b))
      (delete-directory root-a t)
      (delete-directory root-b t))))

(ert-deftest p3-config-project-consult-preview-accept-restores-origin-workspace ()
  (let* ((p3/config-lisp-directory
          (expand-file-name "lisp" p3-config-project-test--root))
         (root-a (make-temp-file "p3-consult-preview-a-" t))
         (root-b (make-temp-file "p3-consult-preview-b-" t))
         (file-a (expand-file-name "inside-a.txt" root-a))
         (file-b (expand-file-name "inside-b.txt" root-b))
         buffer-a
         buffer-b)
    (unwind-protect
        (progn
          (with-temp-file file-a (insert "inside a\n"))
          (with-temp-file file-b (insert "inside b\n"))
          (setq buffer-a (find-file-noselect file-a)
                buffer-b (find-file-noselect file-b))
          (p3-config-project-test--with-clean-tabs
            (p3/config-load-module 'p3-config-project)
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt directory)
                         (cond
                          ((and directory
                                (file-in-directory-p directory root-a))
                           'project-a)
                          ((and directory
                                (file-in-directory-p directory root-b))
                           'project-b))))
                      ((symbol-function 'project-root)
                       (lambda (project)
                         (pcase project
                           ('project-a root-a)
                           ('project-b root-b)))))
              (p3/project-switch-to-tab root-a)
              (switch-to-buffer buffer-a)
              (let ((p3/project--buffer-preview-active t)
                    (p3/project--buffer-preview-origins nil))
                (switch-to-buffer buffer-b 'norecord)
                (switch-to-buffer buffer-b))
              (p3/project-switch-to-tab root-a)
              (should (eq (window-buffer) buffer-a)))))
      (when (buffer-live-p buffer-a) (kill-buffer buffer-a))
      (when (buffer-live-p buffer-b) (kill-buffer buffer-b))
      (delete-directory root-a t)
      (delete-directory root-b t))))

(ert-deftest p3-config-project-transient-buffer-keeps-current-project-workspace ()
  (let* ((p3/config-lisp-directory
          (expand-file-name "lisp" p3-config-project-test--root))
         (root (make-temp-file "p3-transient-project-" t))
         (transient (generate-new-buffer "*p3-dashboard*")))
    (unwind-protect
        (p3-config-project-test--with-clean-tabs
          (p3/config-load-module 'p3-config-project)
          (p3/project-switch-to-tab root)
          (let ((expected-root (p3/project-normalize-root root))
                (expected-name
                 (file-name-nondirectory (directory-file-name root))))
            (switch-to-buffer transient)
            (should
             (equal (alist-get 'p3-project-root
                               (cdr (p3-config-project-test--current-tab)))
                    expected-root))
            (should
             (equal (alist-get 'name
                               (cdr (p3-config-project-test--current-tab)))
                    expected-name))))
      (when (buffer-live-p transient) (kill-buffer transient))
      (delete-directory root t))))

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

(ert-deftest p3-config-project-failed-read-only-visit-keeps-current-workspace ()
  (let* ((p3/config-lisp-directory
          (expand-file-name "lisp" p3-config-project-test--root))
         (project-root (make-temp-file "p3-read-only-project-" t))
         (loose-root (make-temp-file "p3-read-only-loose-" t))
         (missing-file (expand-file-name "missing.txt" loose-root)))
    (unwind-protect
        (p3-config-project-test--with-clean-tabs
          (p3/config-load-module 'p3-config-project)
          (p3/project-switch-to-tab project-root)
          (let ((tab-count (length (tab-bar-tabs)))
                (expected-root (p3/project-normalize-root project-root)))
            (should-error (find-file-read-only missing-file))
            (should (= (length (tab-bar-tabs)) tab-count))
            (should
             (equal (alist-get 'p3-project-root
                               (cdr (p3-config-project-test--current-tab)))
                    expected-root))))
      (delete-directory loose-root t)
      (delete-directory project-root t))))

(ert-deftest p3-config-project-wires-routing-to-file-opening-commands ()
  (let ((p3/config-lisp-directory
         (expand-file-name "lisp" p3-config-project-test--root))
        (find-file-hook nil))
    (p3/config-load-module 'p3-config-project)
    (should-not find-file-hook)
    (should (advice-member-p #'p3/project-with-file-routing 'find-file))
    (should-not
     (advice-member-p #'p3/project-with-file-routing 'find-file-other-window))
    (should
     (advice-member-p #'p3/project-with-file-context 'find-file-other-window))
    (should-not (advice-member-p #'p3/project-with-file-routing 'find-file-read-only))
    (should-not (advice-member-p #'p3/project-route-file 'find-file))
    (should-not (advice-member-p #'p3/project-route-file 'find-file-other-window))))

(ert-deftest p3-config-project-wires-routing-to-buffer-switches ()
  (let ((p3/config-lisp-directory
         (expand-file-name "lisp" p3-config-project-test--root)))
    (p3/config-load-module 'p3-config-project)
    (should (advice-member-p #'p3/project-route-buffer 'switch-to-buffer))
    (should-not
     (advice-member-p #'p3/project-route-buffer 'switch-to-buffer-other-window))
    (should
     (advice-member-p #'p3/project-with-buffer-context
                      'switch-to-buffer-other-window))
    (should
     (advice-member-p #'p3/project--after-tab-select 'tab-bar-select-tab))
    (should
     (memq #'p3/project-reconcile-window-composition
           window-configuration-change-hook))))

(provide 'p3-config-project-test)

;;; p3-config-project-test.el ends here