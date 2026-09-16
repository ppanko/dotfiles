;;; p3-terminal-test.el --- Tests for p3-terminal -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

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

(ert-deftest p3-terminal-project-shell-live-p-requires-live-process ()
  (let ((buffer (generate-new-buffer " *p3-shell-live-test*"))
        (live t))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq-local p3/project-shell-root-value temporary-file-directory))
          (cl-letf (((symbol-function 'get-buffer-process)
                     (lambda (candidate)
                       (and (eq candidate buffer) 'fake-process)))
                    ((symbol-function 'process-live-p)
                     (lambda (process)
                       (and (eq process 'fake-process) live))))
            (should (p3/project-shell-live-p buffer))
            (setq live nil)
            (should-not (p3/project-shell-live-p buffer))))
      (kill-buffer buffer))))

(ert-deftest p3-terminal-primary-shell-is-reused-per-root ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory
               (expand-file-name "p3-project" temporary-file-directory)))
        (created nil))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root))
                  ((symbol-function 'p3/project-shell-live-p)
                   (lambda (buffer) (buffer-live-p buffer)))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (let ((buffer (get-buffer-create name)))
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
                     (let ((buffer (get-buffer-create name)))
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
                  ((symbol-function 'p3/project-shell-live-p)
                   (lambda (buffer) (buffer-live-p buffer)))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (let ((buffer (get-buffer-create name)))
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
                  ((symbol-function 'p3/project-shell-live-p)
                   (lambda (buffer) (buffer-live-p buffer)))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (let ((buffer (get-buffer-create name)))
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
                     (let ((buffer (get-buffer-create name)))
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

(ert-deftest p3-terminal-dead-process-primary-is-restarted ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory
               (expand-file-name "p3-project" temporary-file-directory)))
        (alive t)
        (starts 0)
        created)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root))
                  ((symbol-function 'p3/project-shell-live-p)
                   (lambda (buffer)
                     (and (buffer-live-p buffer) alive)))
                  ((symbol-function 'p3/project-shell--start)
                   (lambda (name _root)
                     (cl-incf starts)
                     (setq alive t)
                     (let ((buffer (get-buffer-create name)))
                       (cl-pushnew buffer created)
                       buffer))))
          (let ((first (p3/project-shell-buffer)))
            (setq alive nil)
            (let ((replacement (p3/project-shell-buffer)))
              (should (= starts 2))
              (should (eq replacement (gethash root p3/project-shell-buffers)))
              (should (buffer-live-p replacement))
              (should (eq first replacement)))))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            created))))

(ert-deftest p3-terminal-session-list-excludes-dead-process-buffers ()
  (let ((buffer (generate-new-buffer " *p3-dead-shell-list-test*")))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (setq-local p3/project-shell-root-value temporary-file-directory))
          (cl-letf (((symbol-function 'p3/project-shell-live-p)
                     (lambda (_candidate) nil)))
            (should-not (memq buffer (p3/project-shell-buffers)))))
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
                     (let ((buffer (get-buffer-create name)))
                       (push buffer created)
                       buffer))))
          (p3/project-shell-buffer)
          (should (equal captured-directory root)))
      (mapc (lambda (buffer)
              (when (buffer-live-p buffer)
                (kill-buffer buffer)))
            created))))

(ert-deftest p3-terminal-windows-start-preserves-project-directory ()
  (let* ((root
          (file-name-as-directory
           (expand-file-name "p3-windows-project" temporary-file-directory)))
         (name "*p3-windows-project-shell-test*")
         (old-chere (getenv "CHERE_INVOKING"))
         captured-directory
         captured-chere)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/windows-p) (lambda () t))
                  ((symbol-function 'p3/platform-bash-program)
                   (lambda () "C:/rtools/usr/bin/bash.exe"))
                  ((symbol-function 'shell)
                   (lambda (buffer-name)
                     (setq captured-directory default-directory
                           captured-chere (getenv "CHERE_INVOKING"))
                     (get-buffer-create buffer-name))))
          (p3/project-shell--start name root)
          (should (equal captured-directory root))
          (should (equal captured-chere "1"))
          (should (equal (getenv "CHERE_INVOKING") old-chere)))
      (when-let ((buffer (get-buffer name)))
        (kill-buffer buffer)))))

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
