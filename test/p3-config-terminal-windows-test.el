;;; p3-config-terminal-windows-test.el --- Native Windows terminal config smoke -*- lexical-binding: t; -*-

(require 'ert)
(require 'subr-x)

(defconst p3-config-terminal-windows-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(setq user-emacs-directory
      (file-name-as-directory p3-config-terminal-windows-test--root))
(add-to-list 'load-path
             (expand-file-name "lisp" p3-config-terminal-windows-test--root))

(require 'p3-platform)

(defconst p3-config-terminal-windows-test--msys2-root
  (or (getenv "P3_TEST_MSYS2_ROOT")
      (error "P3_TEST_MSYS2_ROOT is not set"))
  "Git for Windows MSYS2 root supplied by CI.")

(setq linuxy-environment-path
      (file-name-as-directory
       (expand-file-name "usr/bin" p3-config-terminal-windows-test--msys2-root)))

(load-file
 (expand-file-name "lisp/p3-config-loader.el"
                   p3-config-terminal-windows-test--root))
(load-file
 (expand-file-name "lisp/p3-config-terminal.el"
                   p3-config-terminal-windows-test--root))

(ert-deftest p3-config-terminal-native-windows-composition-loads ()
  (should (eq system-type 'windows-nt))
  (should (featurep 'p3-config-terminal))
  (should (featurep 'p3-terminal))
  (should (eq (key-binding (kbd "C-x C-u")) #'shell))
  (should (string-suffix-p "bash.exe" shell-file-name t))
  (should (memq #'p3/windows-shell-mode-setup shell-mode-hook)))

(provide 'p3-config-terminal-windows-test)

;;; p3-config-terminal-windows-test.el ends here
