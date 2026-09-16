;;; p3-project-context-test.el --- Cross-layer project context tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'org)

(defconst p3-project-context-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-project-context-test--root))

(require 'p3-project)
(require 'p3-org-roam)
(require 'p3-terminal)

(defun p3-project-context-test--canonical (directory)
  "Return canonical DIRECTORY with a trailing separator."
  (file-name-as-directory (file-truename directory)))

(ert-deftest p3-project-context-resolver-precedes-filesystem-project ()
  (let ((semantic-root (make-temp-file "p3-semantic-project-" t))
        (physical-root (make-temp-file "p3-physical-project-" t)))
    (unwind-protect
        (let ((p3/project-context-functions
               (list (lambda () semantic-root))))
          (cl-letf (((symbol-function 'project-current)
                     (lambda (&optional _maybe-prompt _directory)
                       'physical-project))
                    ((symbol-function 'project-root)
                     (lambda (_project) physical-root)))
            (should
             (equal (p3/project-root)
                    (p3-project-context-test--canonical semantic-root)))))
      (delete-directory semantic-root t)
      (delete-directory physical-root t))))

(ert-deftest p3-org-roam-registers-associated-project-root-resolver ()
  (should (boundp 'p3/project-context-functions))
  (should (fboundp 'p3/org-roam-associated-project-root))
  (should (memq #'p3/org-roam-associated-project-root
                p3/project-context-functions)))

(ert-deftest p3-org-roam-associated-project-root-uses-file-property ()
  (let ((root (make-temp-file "p3-associated-project-" t)))
    (unwind-protect
        (with-temp-buffer
          (org-mode)
          (insert ":PROPERTIES:\n:P3_PROJECT: hub-a\n:END:\n#+title: note\n")
          (goto-char (point-min))
          (let ((p3/org-roam-project-associations
                 (list (cons (p3-project-context-test--canonical root)
                             "hub-a"))))
            (should (fboundp 'p3/org-roam-associated-project-root))
            (should
             (equal (p3/org-roam-associated-project-root)
                    (p3-project-context-test--canonical root)))))
      (delete-directory root t))))

(ert-deftest p3-org-roam-associated-project-root-is-point-sensitive ()
  (let ((file-root (make-temp-file "p3-file-project-" t))
        (heading-root (make-temp-file "p3-heading-project-" t)))
    (unwind-protect
        (with-temp-buffer
          (org-mode)
          (insert ":PROPERTIES:\n:P3_PROJECT: file-hub\n:END:\n"
                  "#+title: note\n\n"
                  "* Work\n"
                  ":PROPERTIES:\n:P3_PROJECT: heading-hub\n:END:\n"
                  "body\n")
          (let ((p3/org-roam-project-associations
                 (list (cons (p3-project-context-test--canonical file-root)
                             "file-hub")
                       (cons (p3-project-context-test--canonical heading-root)
                             "heading-hub"))))
            (should (fboundp 'p3/org-roam-associated-project-root))
            (goto-char (point-min))
            (should
             (equal (p3/org-roam-associated-project-root)
                    (p3-project-context-test--canonical file-root)))
            (search-forward "body")
            (should
             (equal (p3/org-roam-associated-project-root)
                    (p3-project-context-test--canonical heading-root)))))
      (delete-directory file-root t)
      (delete-directory heading-root t))))

(ert-deftest p3-project-shell-uses-associated-org-project-root ()
  (let ((associated-root (make-temp-file "p3-shell-associated-" t))
        (org-root (make-temp-file "p3-shell-org-root-" t)))
    (unwind-protect
        (with-temp-buffer
          (org-mode)
          (insert ":PROPERTIES:\n:P3_PROJECT: shell-hub\n:END:\n#+title: note\n")
          (goto-char (point-min))
          (setq default-directory (file-name-as-directory org-root))
          (let ((p3/org-roam-project-associations
                 (list (cons (p3-project-context-test--canonical associated-root)
                             "shell-hub"))))
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt _directory)
                         'org-project))
                      ((symbol-function 'project-root)
                       (lambda (_project) org-root)))
              (should
               (equal (p3/project-shell-root)
                      (p3-project-context-test--canonical associated-root))))))
      (delete-directory associated-root t)
      (delete-directory org-root t))))

(ert-deftest p3-project-compile-uses-shared-project-root ()
  (let ((semantic-root (make-temp-file "p3-compile-semantic-" t))
        (physical-root (make-temp-file "p3-compile-physical-" t))
        seen-root)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-root)
                   (lambda () semantic-root))
                  ((symbol-function 'project-current)
                   (lambda (&optional _maybe-prompt _directory)
                     'physical-project))
                  ((symbol-function 'project-root)
                   (lambda (_project) physical-root))
                  ((symbol-function 'p3/project--root-compile-command)
                   (lambda (_root _fallback) "check"))
                  ((symbol-function 'project-compile)
                   (lambda ()
                     (interactive)
                     (setq seen-root project-current-directory-override))))
          (p3/project-compile)
          (should
           (equal seen-root
                  (p3-project-context-test--canonical semantic-root))))
      (delete-directory semantic-root t)
      (delete-directory physical-root t))))

(provide 'p3-project-context-test)

;;; p3-project-context-test.el ends here
