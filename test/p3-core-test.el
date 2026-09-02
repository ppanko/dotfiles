;;; p3-core-test.el --- Tests for p3-core -*- lexical-binding: t; -*-

(require 'ert)

(defconst p3-core-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-core-test--root))

(require 'p3-core)

(ert-deftest p3-core-config-commands-remain-commands ()
  (should (commandp #'p3/config-visit))
  (should (commandp #'p3/config-reload)))

(provide 'p3-core-test)

;;; p3-core-test.el ends here
