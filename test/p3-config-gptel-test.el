;;; p3-config-gptel-test.el --- GPTel config boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)

(defconst p3-config-gptel-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-gptel-test--path (relative)
  "Return RELATIVE under the repository root."
  (expand-file-name relative p3-config-gptel-test--root))

(defun p3-config-gptel-test--contents (relative)
  "Return contents of repository file RELATIVE."
  (with-temp-buffer
    (insert-file-contents (p3-config-gptel-test--path relative))
    (buffer-string)))

(defun p3-config-gptel-test--forms ()
  "Read all top-level forms from the GPTel config module."
  (with-temp-buffer
    (insert-file-contents
     (p3-config-gptel-test--path "lisp/p3-config-gptel.el"))
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(ert-deftest p3-config-gptel-preserves-package-configuration ()
  (let ((forms (p3-config-gptel-test--forms)))
    (should
     (member
      '(use-package gptel
         :config
         (setq gptel-model 'gpt-4o-mini
               gptel-api-key (or (getenv "OPENAI_API_KEY")
                                 #'gptel-api-key-from-auth-source)))
      forms))))

(ert-deftest p3-config-gptel-preserves-after-gptel-activation-timing ()
  (let ((forms (p3-config-gptel-test--forms)))
    (should
     (member
      '(with-eval-after-load 'gptel
         (p3/config-load-module 'p3-gptel)
         (p3/gptel-setup))
      forms))))

(ert-deftest p3-config-gptel-config-org-delegates-gptel-boundary ()
  (let ((contents (p3-config-gptel-test--contents "config.org")))
    (should (= 1
               (let ((start 0)
                     (count 0)
                     (needle (regexp-quote
                              "(p3/config-load-module 'p3-config-gptel)")))
                 (while (string-match needle contents start)
                   (setq count (1+ count)
                         start (match-end 0)))
                 count)))
    (dolist (forbidden '("(use-package gptel"
                          "(use-package p3-gptel"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(provide 'p3-config-gptel-test)

;;; p3-config-gptel-test.el ends here
