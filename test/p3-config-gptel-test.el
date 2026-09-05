;;; p3-config-gptel-test.el --- GPTel config boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)
(require 'p3-config-loader)

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

(ert-deftest p3-config-gptel-owner-reloads-command-map-source ()
  "Reloading the GPTel owner must rebuild command-map definitions from source."
  (let* ((directory (make-temp-file "p3-gptel-owner-reload-" t))
         (p3/config-lisp-directory directory)
         (owner (expand-file-name "p3-config-gptel.el" directory))
         (behavior (expand-file-name "p3-gptel.el" directory))
         (old-map (and (boundp 'p3/gptel-command-map) p3/gptel-command-map))
         (old-binding (key-binding (kbd "C-c g"))))
    (unwind-protect
        (progn
          (copy-file (p3-config-gptel-test--path "lisp/p3-config-gptel.el") owner)
          (copy-file (p3-config-gptel-test--path "lisp/p3-gptel.el") behavior)
          (provide 'gptel)
          (p3/config-load-module 'p3-config-gptel)
          (with-temp-buffer
            (insert-file-contents behavior)
            (goto-char (point-min))
            (should
             (search-forward
              "(define-key map (kbd \"l\") #'p3/gptel-send-current-line)"
              nil t))
            (replace-match
             "(define-key map (kbd \"x\") #'p3/gptel-send-current-line)"
             t t)
            (write-region (point-min) (point-max) behavior nil 'silent))
          (p3/config-load-module 'p3-config-gptel)
          (should
           (eq (keymap-lookup p3/gptel-command-map "x")
               #'p3/gptel-send-current-line)))
      (if old-map
          (setq p3/gptel-command-map old-map)
        (makunbound 'p3/gptel-command-map))
      (define-key global-map (kbd "C-c g") old-binding)
      (delete-directory directory t))))

(provide 'p3-config-gptel-test)

;;; p3-config-gptel-test.el ends here
