;;; p3-config-project-test.el --- Native project config boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'project)
(require 'p3-config-loader)

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

(provide 'p3-config-project-test)

;;; p3-config-project-test.el ends here
