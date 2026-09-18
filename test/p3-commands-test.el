;;; p3-commands-test.el --- Tests for generic personal commands -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'compile)
(require 'project)

(defconst p3-commands-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-commands-test--root))
(require 'p3-commands)
(require 'p3-config-loader)
(require 'p3-project)

(ert-deftest p3-commands-core-helpers-remain-commands ()
  (dolist (command '(p3/keybinding-atlas
                     p3/save-kill-other-buffers
                     p3/copy-current-path
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

(ert-deftest p3-commands-keybinding-atlas-documents-ergonomic-prefixes ()
  (let ((global (assoc "Global" p3/keybinding-sections))
        (r (assoc "R / ESS" p3/keybinding-sections))
        (roam (assoc "Org-roam" p3/keybinding-sections)))
    (should (equal (cdr (assoc "C-c R" (cdr global))) "reload config"))
    (should (equal (cdr (assoc "C-c y p" (cdr global))) "copy current path"))
    (should (equal (cdr (assoc "C-c r" (cdr r)))
                   "R project, templates, and tools"))
    (should (equal (cdr (assoc "C-c n p o" (cdr roam)))
                   "open associated project"))))

(ert-deftest p3-commands-copy-current-path-copies-file-buffer-path ()
  (let ((path (expand-file-name "example.R" temporary-file-directory))
        copied)
    (with-temp-buffer
      (setq buffer-file-name path)
      (cl-letf (((symbol-function 'kill-new)
                 (lambda (text &optional _replace) (setq copied text))))
        (should (equal (p3/copy-current-path) path))
        (should (equal copied path))))))

(ert-deftest p3-commands-copy-current-path-uses-dired-entry ()
  (let ((path (expand-file-name "example.R" temporary-file-directory))
        copied)
    (with-temp-buffer
      (setq major-mode 'dired-mode
            default-directory temporary-file-directory)
      (cl-letf (((symbol-function 'dired-get-file-for-visit) (lambda () path))
                ((symbol-function 'kill-new)
                 (lambda (text &optional _replace) (setq copied text))))
        (should (equal (p3/copy-current-path) path))
        (should (equal copied path))))))

(ert-deftest p3-commands-copy-current-path-rejects-pathless-buffer ()
  (with-temp-buffer
    (should-error (p3/copy-current-path) :type 'user-error)))

(ert-deftest p3-commands-yank-prefix-exposes-current-path ()
  (should (eq (keymap-lookup p3/yank-command-map "p")
              #'p3/copy-current-path)))

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

(ert-deftest p3-commands-project-compilation-wires-p3-project-policy ()
  (let ((p3/config-lisp-directory
         (expand-file-name "lisp" p3-commands-test--root))
        (saved project-compilation-buffer-name-function)
        (saved-c (lookup-key project-prefix-map (kbd "c"))))
    (unwind-protect
        (progn
          (p3/config-load-module 'p3-config-project)
          (should (eq project-compilation-buffer-name-function
                      #'p3/project-compilation-buffer-name))
          (should (eq (lookup-key project-prefix-map (kbd "c"))
                      #'p3/project-compile)))
      (setq project-compilation-buffer-name-function saved)
      (define-key project-prefix-map (kbd "c") saved-c))))

(ert-deftest p3-commands-project-compilation-buffer-names-do-not-collide ()
  (let* ((parent-a (make-temp-file "p3-project-check-a-" t))
         (parent-b (make-temp-file "p3-project-check-b-" t))
         (root-a (expand-file-name "api" parent-a))
         (root-b (expand-file-name "api" parent-b)))
    (unwind-protect
        (progn
          (make-directory root-a)
          (make-directory root-b)
          (let ((name-a (let ((default-directory root-a))
                          (p3/project-compilation-buffer-name "compilation")))
                (name-b (let ((default-directory root-b))
                          (p3/project-compilation-buffer-name "compilation"))))
            (should-not (equal name-a name-b))
            (should (string-match-p "api" name-a))
            (should (string-match-p "api" name-b))))
      (delete-directory parent-a t)
      (delete-directory parent-b t))))

(ert-deftest p3-commands-project-compile-uses-root-dir-locals-from-non-file-buffer ()
  (let* ((root (make-temp-file "p3-project-check-root-" t))
         (dir-locals (expand-file-name ".dir-locals.el" root))
         observed-directory
         observed-command)
    (unwind-protect
        (progn
          (with-temp-file dir-locals
            (insert "((nil . ((compile-command . \"make check\"))))\n"))
          (with-temp-buffer
            (setq default-directory temporary-file-directory)
            (let ((compilation-read-command t))
              (cl-letf (((symbol-function 'project-current)
                         (lambda (&optional _maybe-prompt _directory)
                           'fake-project))
                        ((symbol-function 'project-root)
                         (lambda (_project) root))
                        ((symbol-function 'compile)
                         (lambda (&optional _command _comint)
                           (interactive)
                           (setq observed-directory default-directory
                                 observed-command compile-command))))
                (p3/project-compile))))
          (should (file-equal-p observed-directory root))
          (should (equal observed-command "make check")))
      (delete-directory root t))))

(ert-deftest p3-commands-project-compile-ignores-buffer-local-fallback-command ()
  (let ((root (make-temp-file "p3-project-check-fallback-" t))
        (saved-default (default-value 'compile-command))
        observed-command)
    (unwind-protect
        (progn
          (setq-default compile-command "make -k ")
          (with-temp-buffer
            (setq default-directory root)
            (setq-local compile-command "g++ current.cpp")
            (let ((compilation-read-command t))
              (cl-letf (((symbol-function 'project-current)
                         (lambda (&optional _maybe-prompt _directory)
                           'fake-project))
                        ((symbol-function 'project-root)
                         (lambda (_project) root))
                        ((symbol-function 'compile)
                         (lambda (&optional _command _comint)
                           (interactive)
                           (setq observed-command compile-command))))
                (p3/project-compile))))
          (should (equal observed-command "make -k ")))
      (setq-default compile-command saved-default)
      (delete-directory root t))))

(ert-deftest p3-commands-project-compile-rejects-missing-project-without-prompting ()
  (let ((observed-maybe-prompt 'unset)
        (compile-called nil))
    (cl-letf (((symbol-function 'project-current)
               (lambda (&optional maybe-prompt _directory)
                 (setq observed-maybe-prompt maybe-prompt)
                 nil))
              ((symbol-function 'compile)
               (lambda (&rest _)
                 (setq compile-called t))))
      (should-error (p3/project-compile) :type 'user-error))
    (should-not observed-maybe-prompt)
    (should-not compile-called)))

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

(load (expand-file-name "p3-performance-regression-test.el"
                        (file-name-directory (or load-file-name buffer-file-name))))

(provide 'p3-commands-test)

;;; p3-commands-test.el ends here
