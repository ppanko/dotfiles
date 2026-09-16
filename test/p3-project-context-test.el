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
(require 'p3-ess)

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

(ert-deftest p3-org-roam-associated-project-root-prefers-newest-valid-mapping ()
  (let ((older-root (make-temp-file "p3-associated-older-" t))
        (newer-root (make-temp-file "p3-associated-newer-" t)))
    (unwind-protect
        (let ((p3/org-roam-project-associations
               (list (cons (p3-project-context-test--canonical newer-root)
                           "hub-a")
                     (cons "/definitely/missing/p3-root/" "hub-a")
                     (cons (p3-project-context-test--canonical older-root)
                           "hub-a"))))
          (should
           (equal (p3/org-roam-project-root-for-hub-id "hub-a")
                  (p3-project-context-test--canonical newer-root))))
      (delete-directory older-root t)
      (delete-directory newer-root t))))

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

(ert-deftest p3-ess-interactive-R-follows-point-sensitive-org-project-context ()
  (let ((file-root (make-temp-file "p3-R-file-project-" t))
        (heading-root (make-temp-file "p3-R-heading-project-" t))
        (org-root (make-temp-file "p3-R-org-root-" t)))
    (unwind-protect
        (with-temp-buffer
          (org-mode)
          (insert ":PROPERTIES:\n:P3_PROJECT: file-hub\n:END:\n"
                  "#+title: note\n\n"
                  "* Work\n"
                  ":PROPERTIES:\n:P3_PROJECT: heading-hub\n:END:\n"
                  "body\n")
          (setq default-directory (file-name-as-directory org-root))
          (let* ((file-canonical
                  (p3-project-context-test--canonical file-root))
                 (heading-canonical
                  (p3-project-context-test--canonical heading-root))
                 (p3/org-roam-project-associations
                  (list (cons file-canonical "file-hub")
                        (cons heading-canonical "heading-hub")))
                 (p3/ess-project-processes (make-hash-table :test #'equal))
                 displayed)
            (puthash file-canonical "R:file" p3/ess-project-processes)
            (puthash heading-canonical "R:heading" p3/ess-project-processes)
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt _directory)
                         'org-project))
                      ((symbol-function 'project-root)
                       (lambda (_project) org-root))
                      ((symbol-function 'p3/ess-process-live-p)
                       (lambda (_name) t))
                      ((symbol-function 'p3/ess-display-process)
                       (lambda (name)
                         (push (list name ess-local-process-name) displayed)))
                      ((symbol-function 'R)
                       (lambda (&optional _start-args)
                         (ert-fail "associated Org context started a new R"))))
              (goto-char (point-min))
              (p3/ess-project-aware-R #'R nil)
              (search-forward "body")
              (p3/ess-project-aware-R #'R nil)
              (should
               (equal (nreverse displayed)
                      '(("R:file" "R:file")
                        ("R:heading" "R:heading")))))))
      (delete-directory file-root t)
      (delete-directory heading-root t)
      (delete-directory org-root t))))

(ert-deftest p3-project-unavailable-semantic-context-blocks-filesystem-fallback ()
  (let ((physical-root (make-temp-file "p3-unavailable-physical-" t))
        filesystem-called)
    (unwind-protect
        (let ((p3/project-context-functions
               (list (lambda () :p3/project-context-unavailable))))
          (cl-letf (((symbol-function 'project-current)
                     (lambda (&optional _maybe-prompt _directory)
                       (setq filesystem-called t)
                       'physical-project))
                    ((symbol-function 'project-root)
                     (lambda (_project) physical-root)))
            (should-not (p3/project-root))
            (should-not filesystem-called)
            (should-error (p3/project-root t) :type 'user-error)))
      (delete-directory physical-root t))))

(ert-deftest p3-project-shell-rejects-stale-explicit-org-association ()
  (let ((org-root (make-temp-file "p3-stale-shell-org-root-" t)))
    (unwind-protect
        (with-temp-buffer
          (org-mode)
          (insert ":PROPERTIES:\n:P3_PROJECT: missing-hub\n:END:\n#+title: note\n")
          (goto-char (point-min))
          (setq default-directory (file-name-as-directory org-root))
          (let ((p3/org-roam-project-associations
                 (list (cons "/definitely/missing/p3-project/" "missing-hub"))))
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt _directory)
                         'org-project))
                      ((symbol-function 'project-root)
                       (lambda (_project) org-root)))
              (should-error (p3/project-shell-root) :type 'user-error))))
      (delete-directory org-root t))))

(ert-deftest p3-ess-interactive-R-rejects-stale-explicit-org-association ()
  (let ((org-root (make-temp-file "p3-stale-R-org-root-" t))
        started)
    (unwind-protect
        (with-temp-buffer
          (org-mode)
          (insert ":PROPERTIES:\n:P3_PROJECT: missing-hub\n:END:\n#+title: note\n")
          (goto-char (point-min))
          (setq default-directory (file-name-as-directory org-root))
          (let ((p3/org-roam-project-associations
                 (list (cons "/definitely/missing/p3-project/" "missing-hub"))))
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt _directory)
                         'org-project))
                      ((symbol-function 'project-root)
                       (lambda (_project) org-root)))
              (should-error
               (p3/ess-project-aware-R
                (lambda (&optional _start-args)
                  (setq started t))
                nil)
               :type 'user-error)
              (should-not started))))
      (delete-directory org-root t))))

(provide 'p3-project-context-test)

;;; p3-project-context-test.el ends here
