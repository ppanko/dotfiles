;;; p3-project-test.el --- Tests for p3-project -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'project)

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

(ert-deftest p3-project-root-delegates-to-project-el ()
  (cl-letf (((symbol-function 'project-current)
             (lambda (&optional _maybe-prompt _directory) 'fake-project))
            ((symbol-function 'project-root)
             (lambda (_project) "/tmp/native-project/")))
    (should (equal (p3/project-root) "/tmp/native-project/"))))

(ert-deftest p3-project-projectile-mode-hook-restores-native-provider ()
  (skip-unless (executable-find "git"))
  (let ((root (make-temp-file "p3-project-provider-" t)))
    (unwind-protect
        (progn
          (should
           (zerop (call-process "git" nil nil nil "-C" root "init" "-q")))
          (let ((project-find-functions '(project-projectile project-try-vc))
                (default-directory root))
            (cl-letf (((symbol-function 'project-projectile)
                       (lambda (_directory)
                         (ert-fail
                          "Projectile must not provide P3 project identity"))))
              (run-hooks 'projectile-mode-hook)
              (should-not (memq #'project-projectile project-find-functions))
              (should (memq #'project-try-vc project-find-functions))
              (let ((project (project-current nil)))
                (should project)
                (should
                 (equal (p3-project-test--canonical-directory
                         (project-root project))
                        (p3-project-test--canonical-directory root)))))))
      (delete-directory root t))))

(ert-deftest p3-project-marker-only-project-is-detected-from-descendant ()
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

(ert-deftest p3-project-inner-marker-wins-over-outer-git-root ()
  (skip-unless (executable-find "git"))
  (let* ((outer (make-temp-file "p3-project-outer-" t))
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

(ert-deftest p3-project-default-directory-is-buffer-local ()
  (with-temp-buffer
    (let ((original default-directory))
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () "/tmp/project-root/")))
        (p3/use-project-root-as-default-dir)
        (should (local-variable-p 'default-directory))
        (should (equal default-directory "/tmp/project-root/"))
        (should-not (equal original default-directory))))))

(provide 'p3-project-test)

;;; p3-project-test.el ends here
