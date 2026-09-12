;;; p3-project-preview-window-test.el --- Consult preview layout regression -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'project)
(require 'tab-bar)
(require 'p3-config-loader)
(require 'p3-project)

(defconst p3-project-preview-window-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defmacro p3-project-preview-window-test--with-clean-tabs (&rest body)
  "Run BODY with one unclaimed tab, restoring frame state afterward."
  (declare (indent 0) (debug t))
  `(let ((saved-tabs (frame-parameter nil 'tabs))
         (saved-window-configuration (current-window-configuration)))
     (unwind-protect
         (progn
           (set-frame-parameter nil 'tabs nil)
           (tab-bar-tabs)
           (delete-other-windows)
           ,@body)
       (set-frame-parameter nil 'tabs saved-tabs)
       (set-window-configuration saved-window-configuration))))

(ert-deftest p3-project-consult-other-window-preview-restores-origin-layout ()
  (let* ((p3/config-lisp-directory
          (expand-file-name "lisp" p3-project-preview-window-test--root))
         (root-a (make-temp-file "p3-other-window-a-" t))
         (root-b (make-temp-file "p3-other-window-b-" t))
         (file-a (expand-file-name "inside-a.txt" root-a))
         (file-b (expand-file-name "inside-b.txt" root-b))
         buffer-a
         buffer-b)
    (unwind-protect
        (progn
          (with-temp-file file-a (insert "inside a\n"))
          (with-temp-file file-b (insert "inside b\n"))
          (setq buffer-a (find-file-noselect file-a)
                buffer-b (find-file-noselect file-b))
          (p3-project-preview-window-test--with-clean-tabs
            (p3/config-load-module 'p3-config-project)
            (cl-letf (((symbol-function 'project-current)
                       (lambda (&optional _maybe-prompt directory)
                         (cond
                          ((and directory
                                (file-in-directory-p directory root-a))
                           'project-a)
                          ((and directory
                                (file-in-directory-p directory root-b))
                           'project-b))))
                      ((symbol-function 'project-root)
                       (lambda (project)
                         (pcase project
                           ('project-a root-a)
                           ('project-b root-b)))))
              (p3/project-switch-to-tab root-a)
              (switch-to-buffer buffer-a)
              (should (= (length (window-list nil 'no-minibuf)) 1))
              (p3/project-with-buffer-preview-guard
               (lambda ()
                 (switch-to-buffer-other-window buffer-a 'norecord)
                 (switch-to-buffer buffer-b 'norecord)
                 (switch-to-buffer-other-window buffer-b)))
              (p3/project-switch-to-tab root-a)
              (should (= (length (window-list nil 'no-minibuf)) 1))
              (should (eq (window-buffer) buffer-a)))))
      (when (buffer-live-p buffer-a) (kill-buffer buffer-a))
      (when (buffer-live-p buffer-b) (kill-buffer buffer-b))
      (delete-directory root-a t)
      (delete-directory root-b t))))

(provide 'p3-project-preview-window-test)

;;; p3-project-preview-window-test.el ends here
