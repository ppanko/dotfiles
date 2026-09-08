;;; p3-config-retirement-test.el --- Retired configuration regressions -*- lexical-binding: t; -*-

(require 'ert)

(defconst p3-config-retirement-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-config-retirement-test--config ()
  "Return the authoritative literate configuration contents."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "config.org" p3-config-retirement-test--root))
    (buffer-string)))

(ert-deftest p3-config-workgroups2-remains-retired ()
  (let ((contents (p3-config-retirement-test--config)))
    (dolist (forbidden '("(use-package workgroups2"
                          "wg-prefix-key"
                          "wg-session-load-on-start"
                          "(workgroups-mode 1)"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(provide 'p3-config-retirement-test)

;;; p3-config-retirement-test.el ends here
