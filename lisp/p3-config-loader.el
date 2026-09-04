;;; p3-config-loader.el --- Build and load the literate config cache -*- lexical-binding: t; -*-

(declare-function org-mode "org" ())
(declare-function org-babel-next-src-block "ob-core" (&optional arg))
(declare-function org-babel-get-src-block-info "ob-core" (&optional light datum))
(declare-function org-babel-tangle-file "ob-tangle" (file &optional target-file lang-re))

(defconst p3/config-source
  (expand-file-name "config.org" user-emacs-directory)
  "Authoritative literate Emacs configuration.")

(defconst p3/config-generated
  (expand-file-name "config.el" user-emacs-directory)
  "Ignored generated cache for `p3/config-source'.")

(defconst p3/config--fingerprint-prefix
  ";; p3-config-source-sha256: "
  "Prefix used to record the source digest in the generated cache.")

(defun p3/config--source-digest ()
  "Return the SHA-256 digest of the exact bytes in `p3/config-source'."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally p3/config-source)
    (secure-hash 'sha256 (current-buffer))))

(defun p3/config--generated-digest ()
  "Return the recorded source digest from `p3/config-generated', or nil."
  (when (file-readable-p p3/config-generated)
    (with-temp-buffer
      (insert-file-contents p3/config-generated nil 0 160)
      (goto-char (point-min))
      (when (looking-at
             (concat (regexp-quote p3/config--fingerprint-prefix)
                     "\\([0-9a-f]\\{64\\}\\)$"))
        (match-string-no-properties 1)))))

(defun p3/config-cache-stale-p ()
  "Return non-nil unless the generated cache matches the current source."
  (let ((recorded (p3/config--generated-digest)))
    (or (null recorded)
        (not (equal recorded (p3/config--source-digest))))))

(defun p3/config--validate-tangle-contract ()
  "Reject source blocks whose tangle setting could escape staging."
  (with-temp-buffer
    (insert-file-contents p3/config-source)
    (setq buffer-file-name p3/config-source)
    (org-mode)
    (goto-char (point-min))
    (let ((done nil))
      (while (not done)
        (condition-case err
            (progn
              (org-babel-next-src-block 1)
              (let* ((info (org-babel-get-src-block-info 'light))
                     (params (nth 2 info))
                     (tangle (cdr (assq :tangle params))))
                (unless (or (null tangle)
                            (equal (format "%s" tangle) "no"))
                  (user-error "Unsupported :tangle setting %S in %s"
                              tangle p3/config-source))))
          (user-error
           (if (string-match-p
                "\\`No \\(?:further \\)?code blocks\\'"
                (error-message-string err))
               (setq done t)
             (signal (car err) (cdr err)))))))))

(defun p3/config--assert-single-tangle-output (outputs staged)
  "Require OUTPUTS to contain only STAGED."
  (unless (and (= (length outputs) 1)
               (file-equal-p (car outputs) staged))
    (error "Config tangle produced unexpected outputs: %S" outputs)))

(defun p3/config--insert-fingerprint (path digest)
  "Insert DIGEST as the generated-cache fingerprint at the start of PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (goto-char (point-min))
    (insert p3/config--fingerprint-prefix digest "\n")
    (write-region (point-min) (point-max) path nil 'silent)))

(defun p3/config--assert-readable-elisp (path)
  "Signal an error unless PATH contains syntactically readable Emacs Lisp."
  (with-temp-buffer
    (insert-file-contents path)
    (emacs-lisp-mode)
    (check-parens)
    (goto-char (point-min))
    (condition-case nil
        (while t
          (read (current-buffer)))
      (end-of-file t))))

(defun p3/config-build ()
  "Rebuild and validate the generated cache from `p3/config-source'."
  (interactive)
  (let* ((source-digest (p3/config--source-digest))
         (directory (file-name-directory p3/config-generated))
         (staged (make-temp-file
                  (expand-file-name ".p3-config-stage-" directory)
                  nil ".el")))
    (unwind-protect
        (progn
          (require 'org)
          (require 'ob-tangle)
          (p3/config--validate-tangle-contract)
          (let ((outputs
                 (org-babel-tangle-file
                  p3/config-source staged "emacs-lisp")))
            (p3/config--assert-single-tangle-output outputs staged))
          (unless (equal source-digest (p3/config--source-digest))
            (error "%s changed while the config cache was being built"
                   p3/config-source))
          (p3/config--insert-fingerprint staged source-digest)
          (p3/config--assert-readable-elisp staged)
          (rename-file staged p3/config-generated t)
          (when (called-interactively-p 'interactive)
            (message "Built %s" p3/config-generated))
          p3/config-generated)
      (when (file-exists-p staged)
        (delete-file staged)))))

(defun p3/config-load-generated ()
  "Load exactly the generated Emacs Lisp cache."
  (load-file p3/config-generated))

(defun p3/config-load ()
  "Load the config cache, rebuilding first when it is stale."
  (when (p3/config-cache-stale-p)
    (p3/config-build))
  (p3/config-load-generated))

(provide 'p3-config-loader)

;;; p3-config-loader.el ends here
