;;; p3-project-routing-test.el --- Tests for file workspace routing -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'project)
(require 'seq)
(require 'tab-bar)
(require 'p3-project)

(defun p3-project-routing-test--current-tab ()
  "Return the current Tab Bar tab alist."
  (seq-find (lambda (tab) (eq (car tab) 'current-tab))
            (tab-bar-tabs)))

(defun p3-project-routing-test--general-tab-p (tab)
  "Return non-nil when TAB is the General workspace."
  (alist-get 'p3-general-workspace (cdr tab)))

(defmacro p3-project-routing-test--with-clean-tabs (&rest body)
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

(ert-deftest p3-project-routing-general-claims-current-unassigned-tab ()
  (p3-project-routing-test--with-clean-tabs
    (let ((before (length (tab-bar-tabs))))
      (p3/project-switch-to-general-tab)
      (should (= (length (tab-bar-tabs)) before))
      (should (p3-project-routing-test--general-tab-p
               (p3-project-routing-test--current-tab)))
      (should (equal (alist-get 'name
                                (cdr (p3-project-routing-test--current-tab)))
                     "General")))))

(ert-deftest p3-project-routing-general-reuses-existing-tab-from-project ()
  (let ((root (make-temp-file "p3-project-routing-project-" t)))
    (unwind-protect
        (p3-project-routing-test--with-clean-tabs
          (p3/project-switch-to-general-tab)
          (p3/project-switch-to-tab root)
          (let ((tab-count (length (tab-bar-tabs))))
            (p3/project-switch-to-general-tab)
            (should (= (length (tab-bar-tabs)) tab-count))
            (should (p3-project-routing-test--general-tab-p
                     (p3-project-routing-test--current-tab)))))
      (delete-directory root t))))

(ert-deftest p3-project-routing-project-file-selects-project-workspace ()
  (let* ((root (make-temp-file "p3-project-routing-root-" t))
         (file (expand-file-name "inside.txt" root)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "inside\n"))
          (p3-project-routing-test--with-clean-tabs
            (with-temp-buffer
              (setq buffer-file-name file)
              (cl-letf (((symbol-function 'project-current)
                         (lambda (&optional _maybe-prompt directory)
                           (when (equal directory (file-name-directory file))
                             'fake-project)))
                        ((symbol-function 'project-root)
                         (lambda (_project) root)))
                (p3/project-route-current-file)
                (should
                 (equal (alist-get 'p3-project-root
                                   (cdr (p3-project-routing-test--current-tab)))
                        (p3/project-normalize-root root)))))))
      (delete-directory root t))))

(ert-deftest p3-project-routing-nonproject-file-selects-general-workspace ()
  (let* ((root (make-temp-file "p3-project-routing-general-" t))
         (file (expand-file-name "loose.txt" root)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "loose\n"))
          (p3-project-routing-test--with-clean-tabs
            (with-temp-buffer
              (setq buffer-file-name file)
              (cl-letf (((symbol-function 'project-current)
                         (lambda (&optional _maybe-prompt _directory) nil)))
                (p3/project-route-current-file)
                (should (p3-project-routing-test--general-tab-p
                         (p3-project-routing-test--current-tab)))))))
      (delete-directory root t))))

(ert-deftest p3-project-routing-ignores-nonfile-and-remote-buffers ()
  (p3-project-routing-test--with-clean-tabs
    (let ((before (tab-bar-tabs)))
      (with-temp-buffer
        (setq buffer-file-name nil)
        (p3/project-route-current-file))
      (should (equal (tab-bar-tabs) before)))
    (let ((before (tab-bar-tabs)))
      (with-temp-buffer
        (setq buffer-file-name "/ssh:example:/tmp/file.txt")
        (p3/project-route-current-file))
      (should (equal (tab-bar-tabs) before)))))

(ert-deftest p3-project-routing-config-wires-find-file-hook ()
  (let ((find-file-hook find-file-hook))
    (load "p3-config-project" nil 'nomessage)
    (should (memq #'p3/project-route-current-file find-file-hook))))

(provide 'p3-project-routing-test)

;;; p3-project-routing-test.el ends here
