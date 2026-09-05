;;; p3-commands-test.el --- Tests for generic personal commands -*- lexical-binding: t; -*-

(require 'ert)

(defconst p3-commands-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-commands-test--root))
(require 'p3-commands)

(ert-deftest p3-commands-core-helpers-remain-commands ()
  (dolist (command '(p3/keybinding-atlas
                     p3/save-kill-other-buffers
                     p3/sudo-edit
                     p3/region-suffix
                     p3/newline-after-comma-or-space
                     p3/force-quotes
                     p3/byte-compile-init-dir
                     move-line
                     move-line-up
                     move-line-down
                     p3/open-in-external-app
                     check-curl-version
                     p3/get-local-buffer-mode
                     p3/is-current-buffer-mode-inferior-ess-r-mode))
    (should (commandp command)))
  (if (eq system-type 'windows-nt)
      (should (commandp 'p3/windows-shell))
    (should-not (fboundp 'p3/windows-shell))))

(ert-deftest p3-commands-move-line-down-preserves-column ()
  (with-temp-buffer
    (insert "aa\nbb\ncc\n")
    (goto-char (point-min))
    (forward-char 1)
    (move-line-down 1)
    (should (equal (buffer-string) "bb\naa\ncc\n"))
    (should (= (current-column) 1))))

(ert-deftest p3-commands-keybinding-atlas-keeps-global-section ()
  (should (equal (caar p3/keybinding-sections) "Global")))

(ert-deftest p3-commands-keybinding-atlas-documents-native-project-prefix ()
  (let ((section (assoc "Project" p3/keybinding-sections)))
    (should section)
    (should (equal (cdr (assoc "C-c p / C-x p" (cdr section)))
                   "native project commands"))
    (should (equal (cdr (assoc "s-p" (cdr section)))
                   "native project commands"))))

(provide 'p3-commands-test)

;;; p3-commands-test.el ends here