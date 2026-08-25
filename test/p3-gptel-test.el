;;; p3-gptel-test.el --- Tests for p3-gptel -*- lexical-binding: t; -*-

(require 'ert)

(defconst p3-gptel-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-gptel-test--root))

(require 'p3-gptel)

(ert-deftest p3-gptel-sensitive-buffer-detects-secret-like-files ()
  (dolist (file '("/tmp/.env"
                  "/tmp/secrets.el"
                  "/tmp/credentials.json"))
    (with-temp-buffer
      (setq buffer-file-name file)
      (should (p3/gptel-sensitive-buffer-p)))))

(ert-deftest p3-gptel-sensitive-buffer-allows-ordinary-code ()
  (with-temp-buffer
    (setq buffer-file-name "/tmp/analysis.py")
    (should-not (p3/gptel-sensitive-buffer-p))))

(ert-deftest p3-gptel-task-code-uses-current-line-for-send-line ()
  (with-temp-buffer
    (insert "first\nsecond\n")
    (goto-char (point-min))
    (forward-line 1)
    (should (equal (p3/gptel-task-code "Send Line") "second\n"))))

(ert-deftest p3-gptel-abort-stream-restores-replaced-text ()
  (with-temp-buffer
    (insert "before OLD after")
    (let* ((start (copy-marker 8 nil))
           (end (copy-marker 11 t))
           (context (list :task "Refactor"
                          :insert-type 'replace
                          :target-buffer (current-buffer)
                          :original "OLD"
                          :start-marker start
                          :end-marker end
                          :started nil)))
      (p3/gptel-stream-begin "NEW" context)
      (should (equal (buffer-string) "before NEW after"))
      (p3/gptel-abort-stream context)
      (should (equal (buffer-string) "before OLD after")))))

(ert-deftest p3-gptel-command-map-exposes-task-workflow ()
  (dolist (key '("l" "r" "d" "t" "c" "w"))
    (should (commandp (keymap-lookup p3/gptel-command-map key)))))

(provide 'p3-gptel-test)

;;; p3-gptel-test.el ends here
