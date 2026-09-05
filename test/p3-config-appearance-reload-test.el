;;; p3-config-appearance-reload-test.el --- Appearance reload tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defconst p3-config-appearance-reload-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(unless (featurep 'p3-config-appearance-test)
  (load-file
   (expand-file-name "test/p3-config-appearance-test.el"
                     p3-config-appearance-reload-test--root)))

(ert-deftest p3-appearance-reload-is-idempotent ()
  (p3-config-appearance-test--load-appearance)
  (p3-config-appearance-test--load-appearance)
  (should (= 1 (cl-count #'p3/appearance-refresh-buffer-context
                         find-file-hook :test #'eq)))
  (should (= 1 (cl-count #'p3/appearance-refresh-buffer-context
                         after-change-major-mode-hook :test #'eq)))
  (should (= 1 (cl-count #'p3/appearance-apply-frame-font
                         after-make-frame-functions :test #'eq)))
  (should-not (memq #'nerd-icons-dired-mode dired-mode-hook))
  (should (equal (default-value 'mode-line-format)
                 (p3/appearance--build-mode-line-format)))
  (let ((p3/appearance--icons-available t))
    (p3/appearance-sync-dired-icons)
    (p3/appearance-sync-dired-icons)
    (should (= 1 (cl-count #'nerd-icons-dired-mode
                           dired-mode-hook :test #'eq)))))

(provide 'p3-config-appearance-reload-test)

;;; p3-config-appearance-reload-test.el ends here
