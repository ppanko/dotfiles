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

(provide 'p3-project-test)

;;; p3-project-test.el ends here
