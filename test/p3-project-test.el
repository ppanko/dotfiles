;;; p3-project-test.el --- Tests for p3-project -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'project)
(require 'seq)
(require 'tab-bar)

(defconst p3-project-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-project-test--root))

(require 'p3-project)

(defun p3-project-test--canonical-directory (directory)
  "Return DIRECTORY in normalized form for root comparisons."
  (file-name-as-directory (file-truename directory)))

(defun p3-project-test--contents (relative)
  "Return contents of repository file RELATIVE."
  (with-temp-buffer
    (insert-file-contents (expand-file-name relative p3-project-test--root))
    (buffer-string)))

(defun p3-project-test--current-tab ()
  "Return the current Tab Bar tab alist."
  (seq-find (lambda (tab) (eq (car tab) 'current-tab))
            (tab-bar-tabs)))

(defun p3-project-test--tab-root (tab)
  "Return TAB's P3 project-root metadata, if any."
  (alist-get 'p3-project-root (cdr tab)))

(defun p3-project-test--set-current-tab-root (root)
  "Set the current tab's P3 project-root metadata to ROOT."
  (let* ((tabs (tab-bar-tabs))
         (tab (seq-find (lambda (item) (eq (car item) 'current-tab)) tabs)))
    (setcdr tab
            (cons (cons 'p3-project-root root)
                  (assq-delete-all 'p3-project-root (cdr tab))))
    (tab-bar-tabs-set tabs)))

(defun p3-project-test--matching-tab-count (root)
  "Return the number of tabs whose P3 project root equals ROOT."
  (cl-count-if (lambda (tab)
                 (equal (p3-project-test--tab-root tab) root))
               (tab-bar-tabs)))

(defmacro p3-project-test--with-clean-tabs (&rest body)
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

(ert-deftest p3-project-root-delegates-to-project-el ()
  (cl-letf (((symbol-function 'project-current)
             (lambda (&optional _maybe-prompt _directory) 'fake-project))
            ((symbol-function 'project-root)
             (lambda (_project) "/tmp/native-project/")))
    (should (equal (p3/project-root) "/tmp/native-project/"))))

(ert-deftest p3-project-plain-git-project-is-detected-from-descendant ()
  (skip-unless (executable-find "git"))
  (let* ((root (make-temp-file "p3-project-git-" t))
         (child (expand-file-name "src/subdir" root)))
    (unwind-protect
        (progn
          (should
           (zerop (call-process "git" nil nil nil "-C" root "init" "-q")))
          (make-directory child t)
          (let ((default-directory child))
            (should
             (equal (p3-project-test--canonical-directory (p3/project-root))
                    (p3-project-test--canonical-directory root)))))
      (delete-directory root t))))

(ert-deftest p3-project-init-prefers-newer-source-before-early-local-requires ()
  (let ((path (expand-file-name "init.el" p3-project-test--root)))
    (with-temp-buffer
      (insert-file-contents path)
      (let* ((contents (buffer-string))
             (newer (string-match
                     (regexp-quote "(setq load-prefer-newer t)") contents))
             (project (string-match
                       (regexp-quote "(require 'p3-project)") contents))
             (loader (string-match
                      (regexp-quote "(require 'p3-config-loader)") contents)))
        (should newer)
        (should project)
        (should loader)
        (should (< newer project))
        (should (< newer loader))))))

(ert-deftest p3-project-legacy-projectile-marker-is-detected-from-descendant ()
  (let* ((root (make-temp-file "p3-project-marker-" t))
         (child (expand-file-name "R/subdir" root)))
    (unwind-protect
        (progn
          (make-directory child t)
          (with-temp-file (expand-file-name ".projectile" root))
          (let ((default-directory child))
            (should
             (equal (p3-project-test--canonical-directory (p3/project-root))
                    (p3-project-test--canonical-directory root)))))
      (delete-directory root t))))

(ert-deftest p3-project-legacy-projectile-marker-wins-over-outer-git-root ()
  (skip-unless (executable-find "git"))
  (let* ((outer (make-temp-file "p3-project-legacy-outer-" t))
         (inner (expand-file-name "analysis" outer))
         (child (expand-file-name "R" inner)))
    (unwind-protect
        (progn
          (should
           (zerop (call-process "git" nil nil nil "-C" outer "init" "-q")))
          (make-directory child t)
          (with-temp-file (expand-file-name ".projectile" inner))
          (let ((default-directory child))
            (should
             (equal (p3-project-test--canonical-directory (p3/project-root))
                    (p3-project-test--canonical-directory inner)))))
      (delete-directory outer t))))

(ert-deftest p3-project-rproj-marker-only-project-is-detected-from-descendant ()
  (let* ((root (make-temp-file "p3-project-rproj-" t))
         (child (expand-file-name "R/subdir" root)))
    (unwind-protect
        (progn
          (make-directory child t)
          (with-temp-file (expand-file-name "analysis.Rproj" root))
          (let ((default-directory child))
            (should
             (equal (p3-project-test--canonical-directory (p3/project-root))
                    (p3-project-test--canonical-directory root)))))
      (delete-directory root t))))

(ert-deftest p3-project-inner-rproj-marker-bounds-project-files ()
  (skip-unless (executable-find "git"))
  (let* ((outer (make-temp-file "p3-project-outer-rproj-" t))
         (inner (expand-file-name "analysis" outer))
         (child (expand-file-name "R/subdir" inner))
         (inner-file (expand-file-name "R/inside.R" inner))
         (outer-file (expand-file-name "outside.R" outer)))
    (unwind-protect
        (progn
          (should
           (zerop (call-process "git" nil nil nil "-C" outer "init" "-q")))
          (make-directory child t)
          (with-temp-file (expand-file-name "analysis.Rproj" inner))
          (with-temp-file inner-file
            (insert "inside <- TRUE\n"))
          (with-temp-file outer-file
            (insert "outside <- TRUE\n"))
          (let* ((default-directory child)
                 (project (project-current nil))
                 (files (mapcar #'file-truename (project-files project))))
            (should project)
            (should
             (equal (p3-project-test--canonical-directory (project-root project))
                    (p3-project-test--canonical-directory inner)))
            (should (member (file-truename inner-file) files))
            (should-not (member (file-truename outer-file) files))))
      (delete-directory outer t))))

(ert-deftest p3-project-source-has-no-projectile-runtime-policy ()
  (let ((path (expand-file-name "lisp/p3-project.el" p3-project-test--root)))
    (with-temp-buffer
      (insert-file-contents path)
      (let ((contents (buffer-string)))
        (dolist (forbidden '("project-projectile"
                            "projectile-mode-hook"
                            "p3/project-keep-native-provider"))
          (should-not (string-match-p (regexp-quote forbidden) contents)))
        (should (string-match-p
                 (regexp-quote "\".projectile\"") contents))
        (should (string-match-p
                 (regexp-quote "\"*.Rproj\"") contents))))))

(ert-deftest p3-project-default-directory-is-buffer-local ()
  (with-temp-buffer
    (let ((original default-directory))
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () "/tmp/project-root/")))
        (p3/use-project-root-as-default-dir)
        (should (local-variable-p 'default-directory))
        (should (equal default-directory "/tmp/project-root/"))
        (should-not (equal original default-directory))))))

(ert-deftest p3-project-continuity-normalizes-equivalent-root-spellings ()
  (let ((root (make-temp-file "p3-project-continuity-root-" t)))
    (unwind-protect
        (let ((alternate (concat (file-name-as-directory root) "./")))
          (should
           (equal (p3/project-normalize-root root)
                  (p3/project-normalize-root alternate)))
          (should
           (equal (p3/project-normalize-root root)
                  (p3-project-test--canonical-directory root))))
      (delete-directory root t))))

(ert-deftest p3-project-continuity-creates-a-new-project-tab ()
  (let ((root (make-temp-file "p3-project-continuity-new-" t)))
    (unwind-protect
        (p3-project-test--with-clean-tabs
          (let* ((normalized (p3-project-test--canonical-directory root))
                 (before (length (tab-bar-tabs))))
            (should (equal (p3/project-switch-to-tab root) normalized))
            (should (= (length (tab-bar-tabs)) (1+ before)))
            (should (= (p3-project-test--matching-tab-count normalized) 1))
            (should
             (equal (p3-project-test--tab-root
                     (p3-project-test--current-tab))
                    normalized))
            (should
             (= (cl-count-if (lambda (tab)
                               (null (p3-project-test--tab-root tab)))
                             (tab-bar-tabs))
                1))))
      (delete-directory root t))))

(ert-deftest p3-project-continuity-reuses-renamed-tab-and-preserves-layout ()
  (let ((root (make-temp-file "p3-project-continuity-reuse-" t))
        (left (generate-new-buffer " *p3-continuity-left*"))
        (right (generate-new-buffer " *p3-continuity-right*")))
    (unwind-protect
        (p3-project-test--with-clean-tabs
          (let ((normalized (p3-project-test--canonical-directory root)))
            (p3/project-switch-to-tab root)
            (tab-rename "renamed-project-tab")
            (delete-other-windows)
            (switch-to-buffer left)
            (let ((right-window (split-window-right)))
              (set-window-buffer right-window right)
              (select-window right-window))
            (let ((expected-buffers
                   (sort (mapcar (lambda (window)
                                   (buffer-name (window-buffer window)))
                                 (window-list))
                         #'string<))
                  (expected-selected (buffer-name (window-buffer)))
                  (tab-count (length (tab-bar-tabs))))
              (tab-new)
              (p3/project-switch-to-tab root)
              (should (= (length (tab-bar-tabs)) (1+ tab-count)))
              (should (= (p3-project-test--matching-tab-count normalized) 1))
              (should
               (equal (alist-get 'name
                                 (cdr (p3-project-test--current-tab)))
                      "renamed-project-tab"))
              (should
               (equal
                (sort (mapcar (lambda (window)
                                (buffer-name (window-buffer window)))
                              (window-list))
                      #'string<)
                expected-buffers))
              (should (equal (buffer-name (window-buffer))
                             expected-selected)))))
      (when (buffer-live-p left) (kill-buffer left))
      (when (buffer-live-p right) (kill-buffer right))
      (delete-directory root t))))

(ert-deftest p3-project-continuity-reconciles-duplicate-tab-metadata ()
  (let ((root (make-temp-file "p3-project-continuity-duplicate-" t)))
    (unwind-protect
        (p3-project-test--with-clean-tabs
          (let ((normalized (p3-project-test--canonical-directory root)))
            (p3/project-switch-to-tab root)
            (tab-new)
            (p3-project-test--set-current-tab-root normalized)
            (let ((tab-count (length (tab-bar-tabs))))
              (should (= (p3-project-test--matching-tab-count normalized) 2))
              (p3/project-switch-to-tab root)
              (should (= (length (tab-bar-tabs)) tab-count))
              (should (= (p3-project-test--matching-tab-count normalized) 1))
              (should
               (equal (p3-project-test--tab-root
                       (p3-project-test--current-tab))
                      normalized)))))
      (delete-directory root t))))

(ert-deftest p3-project-continuity-resume-hands-root-to-project-consult ()
  (let ((root (make-temp-file "p3-project-continuity-resume-" t))
        switched-root
        consulted-root)
    (unwind-protect
        (let ((normalized (p3-project-test--canonical-directory root)))
          (cl-letf (((symbol-function 'project-current)
                     (lambda (&optional _maybe-prompt _directory)
                       'fake-project))
                    ((symbol-function 'project-root)
                     (lambda (_project) root))
                    ((symbol-function 'p3/project-switch-to-tab)
                     (lambda (selected-root)
                       (setq switched-root selected-root)
                       normalized))
                    ((symbol-function 'consult-project-buffer)
                     (lambda ()
                       (interactive)
                       (setq consulted-root project-current-directory-override))))
            (p3/project-resume)
            (should (equal switched-root normalized))
            (should (equal consulted-root normalized))))
      (delete-directory root t))))

(ert-deftest p3-project-continuity-resume-rejects-missing-root-before-tab-change ()
  (let ((missing (expand-file-name
                  "p3-project-continuity-missing"
                  temporary-file-directory))
        switched
        consulted)
    (when (file-exists-p missing)
      (delete-directory missing t))
    (cl-letf (((symbol-function 'project-current)
               (lambda (&optional _maybe-prompt _directory)
                 'fake-project))
              ((symbol-function 'project-root)
               (lambda (_project) missing))
              ((symbol-function 'p3/project-switch-to-tab)
               (lambda (_root) (setq switched t)))
              ((symbol-function 'consult-project-buffer)
               (lambda () (interactive) (setq consulted t))))
      (should-error (p3/project-resume) :type 'user-error)
      (should-not switched)
      (should-not consulted))))

(ert-deftest p3-project-continuity-config-wires-native-project-switch-to-resume ()
  (let ((project-switch-commands project-switch-commands)
        (old-c-c-p (lookup-key global-map (kbd "C-c p")))
        (old-s-p (lookup-key global-map (kbd "s-p"))))
    (unwind-protect
        (progn
          (load (expand-file-name "lisp/p3-config-project.el"
                                  p3-project-test--root)
                nil 'nomessage)
          (should (eq project-switch-commands 'p3/project-resume))
          (should (eq (lookup-key project-prefix-map (kbd "p"))
                      #'project-switch-project)))
      (setq project-switch-commands project-switch-commands)
      (define-key global-map (kbd "C-c p") old-c-c-p)
      (define-key global-map (kbd "s-p") old-s-p))))

(ert-deftest p3-project-continuity-config-enables-lightweight-persistence ()
  (let ((base (p3-project-test--contents "lisp/p3-config-base.el")))
    (should (string-match-p (regexp-quote "(recentf-mode 1)") base))
    (should (string-match-p (regexp-quote "(save-place-mode 1)") base))))

(ert-deftest p3-project-continuity-config-uses-tab-history-not-winner ()
  (let ((workspace
         (p3-project-test--contents "lisp/p3-config-workspace.el")))
    (should (string-match-p (regexp-quote "(tab-bar-mode 1)") workspace))
    (should (string-match-p (regexp-quote "(tab-bar-history-mode 1)") workspace))
    (should-not (string-match-p (regexp-quote "(winner-mode 1)") workspace))))

(ert-deftest p3-project-continuity-preserves-consult-recentf-recency-advice ()
  (let ((init (p3-project-test--contents "init.el")))
    (should
     (string-match-p (regexp-quote "p3/recentf-record-current-buffer") init))
    (should
     (string-match-p
      (regexp-quote
       "(advice-add #'consult-buffer :after #'p3/recentf-record-current-buffer)")
      init))))

(ert-deftest p3-project-continuity-does-not-enable-desktop-restoration ()
  (let ((sources
         (mapconcat #'p3-project-test--contents
                    '("init.el"
                      "lisp/p3-project.el"
                      "lisp/p3-config-project.el"
                      "lisp/p3-config-base.el"
                      "lisp/p3-config-workspace.el")
                    "\n")))
    (dolist (forbidden '("desktop-save-mode"
                         "desktop-read"
                         "desktop-save"
                         "desktop-restore"))
      (should-not (string-match-p (regexp-quote forbidden) sources)))))

(provide 'p3-project-test)

;;; p3-project-test.el ends here
