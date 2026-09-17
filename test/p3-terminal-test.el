;;; p3-terminal-test.el --- Tests for p3-terminal -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'eshell)

(defconst p3-terminal-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-terminal-test--root))

(require 'p3-core)
(require 'p3-terminal)

(ert-deftest p3-terminal-buffer-name-is-stable-and-root-specific ()
  (let ((first (p3/project-shell-buffer-name "/tmp/project-a/"))
        (again (p3/project-shell-buffer-name "/tmp/project-a/"))
        (second (p3/project-shell-buffer-name "/tmp/project-b/")))
    (should (equal first again))
    (should-not (equal first second))
    (should
     (string-match-p
      "\\`\\*shell:project-a:[[:xdigit:]]\\{6\\}\\*\\'" first))))

(ert-deftest p3-terminal-root-prefers-project-root ()
  (let* ((project (file-name-as-directory
                   (make-temp-file "p3-terminal-project-" t)))
         (default-directory temporary-file-directory))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-root)
                   (lambda (&optional _error-on-unavailable) project)))
          (should (equal (p3/project-shell-root)
                         (p3/project-normalize-root project))))
      (delete-directory project t))))

(ert-deftest p3-terminal-root-falls-back-to-local-default-directory ()
  (let ((default-directory temporary-file-directory))
    (cl-letf (((symbol-function 'p3/project-root)
               (lambda (&optional _error-on-unavailable) nil)))
      (should (equal (p3/project-shell-root)
                     (p3/project-normalize-root default-directory))))))

(ert-deftest p3-terminal-root-delegates-to-shared-normalizer ()
  (let* ((raw (file-name-as-directory
               (expand-file-name "p3-project-alias" temporary-file-directory)))
         (canonical (file-name-as-directory
                     (expand-file-name "p3-project-canonical"
                                       temporary-file-directory)))
         seen)
    (cl-letf (((symbol-function 'p3/project-root)
               (lambda (&optional _error-on-unavailable) raw))
              ((symbol-function 'p3/project-normalize-root)
               (lambda (root)
                 (setq seen root)
                 canonical)))
      (should (equal (p3/project-shell-root) canonical))
      (should (equal seen raw)))))

(ert-deftest p3-terminal-root-rejects-remote-fallback ()
  (let ((default-directory "/ssh:host:/tmp/project/"))
    (cl-letf (((symbol-function 'p3/project-root)
               (lambda (&optional _error-on-unavailable) nil)))
      (should-error (p3/project-shell-root) :type 'user-error))))

(ert-deftest p3-terminal-project-shell-live-p-is-buffer-backed ()
  (let ((buffer (generate-new-buffer " *p3-eshell-live-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (eshell-mode)
          (setq-local p3/project-shell-root-value temporary-file-directory)
          (should (p3/project-shell-live-p buffer))
          (should-not (get-buffer-process buffer)))
      (kill-buffer buffer))))

(ert-deftest p3-terminal-project-shell-live-p-rejects-non-eshell-buffer ()
  (let ((buffer (generate-new-buffer " *p3-not-eshell*")))
    (unwind-protect
        (with-current-buffer buffer
          (setq-local p3/project-shell-root-value temporary-file-directory)
          (should-not (p3/project-shell-live-p buffer)))
      (kill-buffer buffer))))

(defun p3-terminal-test--fake-shell (name)
  "Return a managed Eshell buffer named NAME for lifecycle tests."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (eshell-mode))
    buffer))

(ert-deftest p3-terminal-primary-shell-is-reused-per-root ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory
               (expand-file-name "p3-project" temporary-file-directory)))
        created)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (let ((buffer (p3-terminal-test--fake-shell name)))
                       (push buffer created)
                       buffer))))
          (let ((first (p3/project-shell-buffer))
                (second (p3/project-shell-buffer)))
            (should (eq first second))
            (should (= (length created) 1))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            created))))

(ert-deftest p3-terminal-primary-shell-is-root-specific ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory
               (expand-file-name "p3-project-a" temporary-file-directory)))
        created)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (let ((buffer (p3-terminal-test--fake-shell name)))
                       (push buffer created)
                       buffer))))
          (let ((first (p3/project-shell-buffer)))
            (setq root (file-name-as-directory
                        (expand-file-name "p3-project-b"
                                          temporary-file-directory)))
            (let ((second (p3/project-shell-buffer)))
              (should-not (eq first second))
              (should (= (length created) 2)))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            created))))

(ert-deftest p3-terminal-equivalent-roots-reuse-one-primary-shell ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (raw-root "first-spelling")
        (canonical-root (file-name-as-directory
                         (expand-file-name "p3-canonical-project"
                                           temporary-file-directory)))
        created)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-root)
                   (lambda (&optional _error-on-unavailable) raw-root))
                  ((symbol-function 'file-remote-p) (lambda (_root) nil))
                  ((symbol-function 'p3/project-normalize-root)
                   (lambda (_root) canonical-root))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (let ((buffer (p3-terminal-test--fake-shell name)))
                       (push buffer created)
                       buffer))))
          (let ((first (p3/project-shell-buffer)))
            (setq raw-root "second-spelling")
            (let ((second (p3/project-shell-buffer)))
              (should (eq first second))
              (should (= (length created) 1)))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            created))))

(ert-deftest p3-terminal-extra-session-does-not-replace-primary ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory
               (expand-file-name "p3-project" temporary-file-directory)))
        created)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (let ((buffer (p3-terminal-test--fake-shell name)))
                       (push buffer created)
                       buffer))))
          (let ((primary (p3/project-shell-buffer))
                (extra (p3/project-shell-buffer t)))
            (should-not (eq primary extra))
            (should (eq primary (p3/project-shell-buffer)))
            (should (= (length created) 2))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            created))))

(ert-deftest p3-terminal-stale-primary-buffer-is-replaced ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory
               (expand-file-name "p3-project" temporary-file-directory)))
        created)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (let ((buffer (p3-terminal-test--fake-shell name)))
                       (push buffer created)
                       buffer))))
          (let ((first (p3/project-shell-buffer)))
            (kill-buffer first)
            (let ((replacement (p3/project-shell-buffer)))
              (should (buffer-live-p replacement))
              (should-not (eq first replacement)))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            created))))

(ert-deftest p3-terminal-idle-primary-does-not-require-process ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory
               (expand-file-name "p3-idle-project" temporary-file-directory))))
    (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
      (let ((buffer (p3-terminal-test--fake-shell
                     (p3/project-shell-buffer-name root))))
        (unwind-protect
            (progn
              (with-current-buffer buffer
                (setq-local p3/project-shell-root-value root))
              (puthash root buffer p3/project-shell-buffers)
              (should-not (get-buffer-process buffer))
              (should (p3/project-shell-live-p buffer))
              (should (eq buffer (p3/project-shell-buffer))))
          (kill-buffer buffer))))))

(ert-deftest p3-terminal-session-list-excludes-non-eshell-buffers ()
  (let ((buffer (generate-new-buffer " *p3-not-shell-list-test*")))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq-local p3/project-shell-root-value temporary-file-directory))
          (should-not (memq buffer (p3/project-shell-buffers))))
      (kill-buffer buffer))))

(ert-deftest p3-terminal-shell-starts-with-root-as-default-directory ()
  (let* ((root
          (file-name-as-directory
           (expand-file-name "p3-project" temporary-file-directory)))
         (p3/project-shell-buffers (make-hash-table :test #'equal))
         captured-directory
         created)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (setq captured-directory default-directory)
                     (let ((buffer (p3-terminal-test--fake-shell name)))
                       (push buffer created)
                       buffer))))
          (p3/project-shell-buffer)
          (should (equal captured-directory root)))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            created))))

(ert-deftest p3-terminal-command-map-exposes-session-workflow ()
  (dolist (binding '(("t" . p3/project-shell)
                     ("n" . p3/project-shell-new)
                     ("s" . p3/project-shell-switch)
                     ("o" . p3/project-shell-other-window)
                     ("r" . p3/project-shell-rename)
                     ("k" . p3/project-shell-kill)))
    (should (eq (keymap-lookup p3/project-shell-command-map (car binding))
                (cdr binding)))))

(load (expand-file-name "p3-terminal-integration-test.el"
                        (file-name-directory
                         (or load-file-name buffer-file-name))))
(load (expand-file-name "p3-terminal-rich-ux-test.el"
                        (file-name-directory
                         (or load-file-name buffer-file-name))))

(provide 'p3-terminal-test)

;;; p3-terminal-test.el ends here
