;;; p3-reference.el --- Portable reference workflow -*- lexical-binding: t; -*-

(require 'bibtex)
(require 'cl-lib)
(require 'subr-x)

(defvar p3/reference-bibliography-file nil)
(defvar p3/reference-pdf-directory nil)

(defconst p3/reference-provisional-prefix "p3-inbox-")
(defvar p3/reference--provisional-sequence 0)

(defconst p3/reference--entry-head-regexp
  "^[ \t]*@\\([[:alpha:]][[:alnum:]_-]*\\)[ \t\n]*[{(][ \t\n]*\\([^, \t\n]+\\)[ \t\n]*,")

(defun p3/reference-provisional-key-p (citekey)
  "Return non-nil when CITEKEY uses the reserved provisional prefix."
  (and (stringp citekey)
       (string-prefix-p p3/reference-provisional-prefix citekey)))

(defun p3/reference--new-provisional-key ()
  "Return a distinct provisional citekey for this Emacs session."
  (setq p3/reference--provisional-sequence
        (1+ p3/reference--provisional-sequence))
  (format "%s%s-%03d"
          p3/reference-provisional-prefix
          (format-time-string "%Y%m%d-%H%M%S")
          p3/reference--provisional-sequence))

(defun p3/reference--bibliography-path ()
  "Return the configured bibliography path or signal a user error."
  (unless (and (stringp p3/reference-bibliography-file)
               (not (string-empty-p p3/reference-bibliography-file)))
    (user-error "Reference bibliography is not configured"))
  (expand-file-name p3/reference-bibliography-file))

(defun p3/reference--ordinary-entry-type-p (type)
  "Return non-nil when TYPE names an ordinary bibliographic entry."
  (not (member (downcase type) '("string" "preamble" "comment"))))

(defun p3/reference--goto-entry (citekey)
  "Move point to the entry headed by CITEKEY and return non-nil if found."
  (goto-char (point-min))
  (let ((regexp
         (format
          "^[ \t]*@[[:alpha:]][[:alnum:]_-]*[ \t\n]*[{(][ \t\n]*%s[ \t\n]*,"
          (regexp-quote citekey))))
    (when (re-search-forward regexp nil t)
      (goto-char (match-beginning 0))
      t)))

(defun p3/reference--entry-alist (citekey)
  "Return the canonical bibliography entry for CITEKEY as an alist."
  (let ((path (p3/reference--bibliography-path)))
    (when (file-exists-p path)
      (with-temp-buffer
        (insert-file-contents path)
        (bibtex-mode)
        (bibtex-set-dialect 'biblatex t)
        (when (p3/reference--goto-entry citekey)
          (bibtex-parse-entry t))))))

(defun p3/reference--entry-keys-from-content (content)
  "Return ordinary-entry citekeys parsed from BibLaTeX CONTENT."
  (with-temp-buffer
    (insert content)
    (bibtex-mode)
    (bibtex-set-dialect 'biblatex t)
    (goto-char (point-min))
    (let (keys)
      (while (re-search-forward p3/reference--entry-head-regexp nil t)
        (let ((type (match-string-no-properties 1))
              (key (match-string-no-properties 2))
              (start (match-beginning 0)))
          (when (p3/reference--ordinary-entry-type-p type)
            (save-excursion
              (goto-char start)
              (condition-case err
                  (progn
                    (bibtex-parse-entry t)
                    (bibtex-end-of-entry))
                (error
                 (signal (car err) (cdr err)))))
            (push key keys))))
      (nreverse keys))))

(defun p3/reference--validate-content (content)
  "Validate BibLaTeX CONTENT sufficiently for safe local mutation."
  (let ((keys (p3/reference--entry-keys-from-content content))
        (seen (make-hash-table :test #'equal)))
    (dolist (key keys)
      (when (gethash key seen)
        (error "Duplicate citekey: %s" key))
      (puthash key t seen))
    ;; Reject an apparent ordinary entry header that the parser walk could not
    ;; consume because its closing delimiter is missing.
    (with-temp-buffer
      (insert content)
      (bibtex-mode)
      (bibtex-set-dialect 'biblatex t)
      (goto-char (point-min))
      (while (re-search-forward p3/reference--entry-head-regexp nil t)
        (let ((type (match-string-no-properties 1))
              (start (match-beginning 0)))
          (when (p3/reference--ordinary-entry-type-p type)
            (goto-char start)
            (condition-case err
                (bibtex-end-of-entry)
              (error (signal (car err) (cdr err))))))))
    t))

(defun p3/reference--transaction (edit-fn)
  "Run EDIT-FN against a temporary bibliography buffer and commit if valid."
  (let* ((target (p3/reference--bibliography-path))
         (directory (file-name-directory target))
         (original (if (file-exists-p target)
                       (with-temp-buffer
                         (insert-file-contents target)
                         (buffer-string))
                     ""))
         result candidate temp)
    (make-directory directory t)
    (with-temp-buffer
      (insert original)
      (bibtex-mode)
      (bibtex-set-dialect 'biblatex t)
      (setq result (funcall edit-fn)
            candidate (buffer-string)))
    (p3/reference--validate-content candidate)
    (setq temp
          (make-temp-file
           (expand-file-name ".p3-references-" directory)
           nil ".bib" candidate))
    (unwind-protect
        (progn
          (when (file-exists-p target)
            (set-file-modes temp (file-modes target)))
          (rename-file temp target t)
          (setq temp nil))
      (when (and temp (file-exists-p temp))
        (delete-file temp)))
    result))

(provide 'p3-reference)

;;; p3-reference.el ends here
