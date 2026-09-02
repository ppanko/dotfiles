;;; p3-project-windows-test.el --- Windows project/platform integration tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)
(require 'project)

(defconst p3-project-windows-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-project-windows-test--root))

(require 'p3-platform)
(require 'p3-project)

(ert-deftest p3-project-windows-msys2-tools-support-marker-project-files ()
  (unless (eq system-type 'windows-nt)
    (ert-skip "Native Windows-only project enumeration contract"))
  (let* ((msys2-root (getenv "P3_TEST_MSYS2_ROOT"))
         (usr-bin (and msys2-root (expand-file-name "usr/bin" msys2-root)))
         (bash (and usr-bin (expand-file-name "bash.exe" usr-bin)))
         (find (and usr-bin (expand-file-name "find.exe" usr-bin)))
         (root (make-temp-file "p3-project-windows-" t))
         (child (expand-file-name "R" root))
         (data-file (expand-file-name "R/example.R" root))
         (old-path (getenv "PATH"))
         (old-exec-path (copy-sequence exec-path))
         (p3/windows-rtools-override msys2-root)
         (find-program "find"))
    (unwind-protect
        (progn
          (should msys2-root)
          (should (file-readable-p bash))
          (should (file-readable-p find))
          (make-directory child t)
          (with-temp-file (expand-file-name ".projectile" root))
          (with-temp-file data-file
            (insert "x <- 1\n"))
          (p3/windows-configure-rtools)
          (let* ((default-directory child)
                 (project (project-current nil))
                 (files (project-files project)))
            (should project)
            (should
             (equal (file-name-as-directory
                     (file-truename (project-root project)))
                    (file-name-as-directory (file-truename root))))
            (should
             (seq-some
              (lambda (file)
                (string-equal (file-name-nondirectory file) "example.R"))
              files))))
      (setq exec-path old-exec-path)
      (setenv "PATH" old-path)
      (delete-directory root t))))

(provide 'p3-project-windows-test)

;;; p3-project-windows-test.el ends here
