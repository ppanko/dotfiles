;;; p3-terminal-test.el --- Tests for p3-terminal -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-terminal-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-terminal-test--root))

(require 'p3-core)
(require 'p3-terminal)

(ert-deftest p3-terminal-buffer-name-is-stable-and-root-specific ()
  (let ((first (p3/vterm-buffer-name "/tmp/project-a/"))
        (again (p3/vterm-buffer-name "/tmp/project-a/"))
        (second (p3/vterm-buffer-name "/tmp/project-b/")))
    (should (equal first again))
    (should-not (equal first second))
    (should (string-match-p "\\`\\*vterm:project-a:[[:xdigit:]]\\{6\\}\\*\\'" first))))

(ert-deftest p3-terminal-root-prefers-project-root ()
  (let ((default-directory "/tmp/fallback/"))
    (cl-letf (((symbol-function 'p3/project-root)
               (lambda () "/tmp/project/")))
      (should (equal (p3/vterm-root) "/tmp/project/")))))

(ert-deftest p3-terminal-root-falls-back-to-default-directory ()
  (let ((default-directory "/tmp/fallback/"))
    (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
      (should (equal (p3/vterm-root) "/tmp/fallback/")))))

(ert-deftest p3-terminal-command-map-exposes-session-workflow ()
  (dolist (key '("t" "n" "s" "o" "f" "r" "c" "k"))
    (should (commandp (keymap-lookup p3/vterm-command-map key)))))

(provide 'p3-terminal-test)

;;; p3-terminal-test.el ends here
