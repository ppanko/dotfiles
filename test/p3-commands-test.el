;;; p3-commands-test.el --- Tests for generic personal commands -*- lexical-binding: t; -*-

(require 'ert)
(require 'project)

(defconst p3-commands-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-commands-test--root))
(require 'p3-commands)
(require 'p3-config-loader)

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

(ert-deftest p3-commands-keybinding-atlas-documents-project-check-workflow ()
  (let ((section (assoc "Project" p3/keybinding-sections)))
    (should section)
    (should (equal (cdr (assoc "C-c p c / C-x p c" (cdr section)))
                   "run project check"))
    (should (equal (cdr (assoc "g (compilation)" (cdr section)))
                   "rerun project check"))
    (should (equal (cdr (assoc "M-g n / M-g p" (cdr section)))
                   "next/previous compilation error"))))

(ert-deftest p3-commands-project-compilation-uses-native-project-buffer-names ()
  (let ((p3/config-lisp-directory
         (expand-file-name "lisp" p3-commands-test--root))
        (saved project-compilation-buffer-name-function))
    (unwind-protect
        (progn
          (p3/config-load-module 'p3-config-project)
          (should (eq project-compilation-buffer-name-function
                      #'project-prefixed-buffer-name)))
      (setq project-compilation-buffer-name-function saved))))

(ert-deftest p3-commands-atlas-surfaces-ess-tracebug-map ()
  (let ((section (assoc "R / ESS" p3/keybinding-sections)))
    (should section)
    (should (equal (cdr (assoc "C-c C-t" (cdr section)))
                   "ESS Tracebug/debug commands"))))

(ert-deftest p3-commands-atlas-surfaces-shared-language-intelligence ()
  (let ((section (assoc "Language intelligence" p3/keybinding-sections)))
    (should section)
    (dolist (binding '(("M-." . "go to definition")
                       ("M-?" . "find references")
                       ("C-c l r" . "rename symbol")
                       ("C-c l a" . "code actions")))
      (should (equal (cdr (assoc (car binding) (cdr section)))
                     (cdr binding))))))

(ert-deftest p3-commands-atlas-describes-reference-prefix ()
  (let ((section (assoc "References" p3/keybinding-sections)))
    (should
     (equal
      (cdr section)
      '(("C-c b a" . "add reference")
        ("C-c b f" . "find reference")
        ("C-c b i" . "insert citation")
        ("C-c b n" . "literature note")
        ("C-c b p" . "open reference PDF")
        ("C-c b t" . "classify / associate")
        ("C-c b r" . "project references"))))))

(ert-deftest p3-commands-org-atlas-no-longer-owns-reference-prefix ()
  (let ((section (assoc "Org" p3/keybinding-sections)))
    (should-not (assoc "C-c b" (cdr section)))))

(provide 'p3-commands-test)

;;; p3-commands-test.el ends here
