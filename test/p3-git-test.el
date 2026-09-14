;;; p3-git-test.el --- Tests for personal Git process helpers -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'use-package)

(defconst p3-git-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-git-test--root))
(require 'p3-git)

(ert-deftest p3-git-run-returns-output-on-success ()
  (cl-letf (((symbol-function 'p3/git-call)
             (lambda (_directory &rest _arguments)
               '(0 . "ok\n"))))
    (should (equal (p3/git-run "/tmp" "status") "ok\n"))))

(ert-deftest p3-git-run-signals-user-error-on-failure ()
  (cl-letf (((symbol-function 'p3/git-call)
             (lambda (_directory &rest _arguments)
               '(1 . "bad\n"))))
    (should-error (p3/git-run "/tmp" "status") :type 'user-error)))

(ert-deftest p3-git-commit-and-push-repository-commits-staged-changes ()
  (let (calls)
    (cl-letf (((symbol-function 'p3/git-run)
               (lambda (directory &rest arguments)
                 (push (cons directory arguments) calls)
                 ""))
              ((symbol-function 'p3/git-call)
               (lambda (directory &rest arguments)
                 (push (cons directory arguments) calls)
                 '(1 . ""))))
      (p3/git-commit-and-push-repository "/repo" '("-A") "sync"))
    (should
     (equal
      (nreverse calls)
      '(("/repo" "add" "-A")
        ("/repo" "diff" "--cached" "--quiet" "--exit-code")
        ("/repo" "commit" "-m" "sync")
        ("/repo" "push" "--set-upstream" "origin" "HEAD"))))))

(ert-deftest p3-git-commit-and-push-repository-skips-empty-commit ()
  (let (calls)
    (cl-letf (((symbol-function 'p3/git-run)
               (lambda (directory &rest arguments)
                 (push (cons directory arguments) calls)
                 ""))
              ((symbol-function 'p3/git-call)
               (lambda (directory &rest arguments)
                 (push (cons directory arguments) calls)
                 '(0 . ""))))
      (p3/git-commit-and-push-repository "/repo" '("-u") "sync"))
    (should
     (equal
      (nreverse calls)
      '(("/repo" "add" "-u")
        ("/repo" "diff" "--cached" "--quiet" "--exit-code")
        ("/repo" "push" "--set-upstream" "origin" "HEAD"))))))

(ert-deftest p3-git-config-sync-preserves-repository-staging-modes ()
  (let ((user-emacs-directory "/tmp/p3-emacs/")
        calls)
    (cl-letf (((symbol-function 'file-exists-p)
               (lambda (_path) t))
              ((symbol-function 'file-directory-p)
               (lambda (_path) t))
              ((symbol-function 'p3/check-git-installed)
               (lambda () t))
              ((symbol-function 'p3/git-commit-and-push-repository)
               (lambda (directory add-arguments commit-message)
                 (push (list directory add-arguments commit-message) calls))))
      (p3/git-commit-and-push-emacs-config "sync"))
    (setq calls (nreverse calls))
    (should (= (length calls) 2))
    (should (equal (mapcar #'cadr calls) '(("-A") ("-u"))))
    (should (equal (mapcar #'caddr calls) '("sync" "sync")))))

(ert-deftest p3-git-close-magit-buffers-kills-only-magit-buffers ()
  (let ((magit-a (get-buffer-create "*magit-test*"))
        (magit-b (get-buffer-create "magit-test"))
        (other (get-buffer-create "*p3-not-magit*")))
    (unwind-protect
        (progn
          (close-magit-buffers)
          (should-not (buffer-live-p magit-a))
          (should-not (buffer-live-p magit-b))
          (should (buffer-live-p other)))
      (when (buffer-live-p other)
        (kill-buffer other)))))

(ert-deftest p3-git-config-keeps-magit-usable-without-forge ()
  (let* ((path (expand-file-name "lisp/p3-config-git.el" p3-git-test--root))
         (p3/config-lisp-directory
          (expand-file-name "lisp" p3-git-test--root))
         (global-map (copy-keymap global-map))
         (features (cons 'magit
                         (delq 'forge
                               (delq 'p3-config-git
                                     (copy-sequence features)))))
         (after-load-alist (copy-tree after-load-alist))
         (use-package-always-ensure nil)
         (original-require (symbol-function 'require)))
    (cl-letf (((symbol-function 'require)
               (lambda (feature &rest arguments)
                 (if (eq feature 'forge)
                     (signal 'file-missing
                             '("Cannot open load file" "forge"))
                   (apply original-require feature arguments)))))
      (load path nil t))
    (should (featurep 'p3-config-git))
    (should (keymapp p3/magit-command-map))
    (should (eq (lookup-key global-map (kbd "C-c m"))
                p3/magit-command-map))
    (should (fboundp 'p3/git-run))
    (should-not (featurep 'forge))))

(provide 'p3-git-test)

;;; p3-git-test.el ends here
