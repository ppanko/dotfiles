;;; p3-git-test.el --- Tests for personal Git process helpers -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

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

(provide 'p3-git-test)

;;; p3-git-test.el ends here
