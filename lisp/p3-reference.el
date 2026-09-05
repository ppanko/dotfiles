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

(defun p3/reference--entry-string (citekey)
  "Return the exact bibliography entry text for CITEKEY, or nil."
  (let ((path (p3/reference--bibliography-path)))
    (when (file-exists-p path)
      (with-temp-buffer
        (insert-file-contents path)
        (bibtex-mode)
        (bibtex-set-dialect 'biblatex t)
        (when (p3/reference--goto-entry citekey)
          (let ((start (point)))
            (bibtex-end-of-entry)
            (buffer-substring-no-properties start (point))))))))

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

(defun p3/reference--parse-single-entry (bibtex)
  "Parse exactly one ordinary BIBTEX entry and return its alist."
  (p3/reference--validate-content bibtex)
  (let ((keys (p3/reference--entry-keys-from-content bibtex)))
    (unless (= (length keys) 1)
      (user-error "Expected exactly one bibliographic entry"))
    (with-temp-buffer
      (insert bibtex)
      (bibtex-mode)
      (bibtex-set-dialect 'biblatex t)
      (unless (p3/reference--goto-entry (car keys))
        (user-error "Could not parse bibliographic entry"))
      (bibtex-parse-entry t))))

(defun p3/reference--all-entry-alists ()
  "Return all ordinary entries from the canonical bibliography."
  (let ((path (p3/reference--bibliography-path)))
    (if (not (file-exists-p path))
        nil
      (with-temp-buffer
        (insert-file-contents path)
        (let ((content (buffer-string)))
          (mapcar #'p3/reference--entry-alist
                  (p3/reference--entry-keys-from-content content)))))))

(defun p3/reference-normalize-doi (doi)
  "Normalize DOI for duplicate comparison, returning nil when empty."
  (when (stringp doi)
    (let ((value (downcase (string-trim doi))))
      (setq value
            (replace-regexp-in-string
             "\\`https?://\\(?:dx\\.\\)?doi\\.org/" "" value t))
      (setq value (replace-regexp-in-string "\\`doi:[ \t]*" "" value t))
      (setq value (string-trim value))
      (unless (string-empty-p value) value))))

(defun p3/reference-normalize-url (url)
  "Normalize URL for conservative duplicate comparison."
  (when (stringp url)
    (let* ((value (string-trim url))
           (value (replace-regexp-in-string "#.*\\'" "" value)))
      (when (string-match
             "\\`\\([[:alpha:]][[:alnum:]+.-]*\\)://\\([^/]+\\)\\(.*\\)\\'"
             value)
        (setq value
              (concat (downcase (match-string 1 value))
                      "://"
                      (downcase (match-string 2 value))
                      (match-string 3 value))))
      (setq value (replace-regexp-in-string "/+\\'" "" value))
      (unless (string-empty-p value) value))))

(defun p3/reference--normalize-title (title)
  "Normalize TITLE for conservative possible-duplicate detection."
  (when (stringp title)
    (let ((value (downcase title)))
      (setq value (replace-regexp-in-string "[[:punct:]]+" " " value))
      (setq value (replace-regexp-in-string "[ \t\n\r]+" " " value))
      (setq value (string-trim value))
      (unless (string-empty-p value) value))))

(defun p3/reference--strong-duplicate-key (entry)
  "Return canonical citekey strongly matching ENTRY by DOI or URL."
  (let ((doi (p3/reference-normalize-doi (cdr (assoc "doi" entry))))
        (url (p3/reference-normalize-url (cdr (assoc "url" entry)))))
    (or
     (when doi
       (cl-loop for existing in (p3/reference--all-entry-alists)
                for existing-doi =
                (p3/reference-normalize-doi (cdr (assoc "doi" existing)))
                when (and existing-doi (equal doi existing-doi))
                return (cdr (assoc "=key=" existing))))
     (when url
       (cl-loop for existing in (p3/reference--all-entry-alists)
                for existing-url =
                (p3/reference-normalize-url (cdr (assoc "url" existing)))
                when (and existing-url (equal url existing-url))
                return (cdr (assoc "=key=" existing)))))))

(defun p3/reference--possible-title-duplicate-keys (entry)
  "Return canonical citekeys whose normalized title equals ENTRY's title."
  (let ((title (p3/reference--normalize-title (cdr (assoc "title" entry)))))
    (when title
      (cl-loop for existing in (p3/reference--all-entry-alists)
               for existing-title =
               (p3/reference--normalize-title (cdr (assoc "title" existing)))
               when (and existing-title (equal title existing-title))
               collect (cdr (assoc "=key=" existing))))))

(defun p3/reference-import-bibtex (bibtex)
  "Safely import one BIBTEX entry and return its canonical citekey."
  (let* ((incoming (p3/reference--parse-single-entry bibtex))
         (key (cdr (assoc "=key=" incoming)))
         (duplicate (p3/reference--strong-duplicate-key incoming)))
    (when (p3/reference-provisional-key-p key)
      (user-error "p3-inbox-* keys are reserved for URL-only captures"))
    (cond
     (duplicate duplicate)
     ((and (p3/reference--possible-title-duplicate-keys incoming)
           (not (y-or-n-p
                 "Possible title duplicate; add as a distinct reference? ")))
      (user-error "Reference import cancelled"))
     (t
      (p3/reference--transaction
       (lambda ()
         (goto-char (point-max))
         (unless (bolp) (insert "\n"))
         (insert bibtex)
         (unless (bolp) (insert "\n"))))
      key))))

(defun p3/reference--keyword-list (value)
  "Return normalized comma-separated keyword VALUE as a unique list."
  (delete-dups
   (seq-filter
    (lambda (item) (not (string-empty-p item)))
    (mapcar #'string-trim (split-string (or value "") "," t)))))

(defun p3/reference--set-keywords (citekey transform)
  "Apply TRANSFORM to CITEKEY's keyword list with an entry-local mutation."
  (p3/reference--transaction
   (lambda ()
     (unless (p3/reference--goto-entry citekey)
       (user-error "Unknown reference: %s" citekey))
     (let* ((entry (bibtex-parse-entry t))
            (current (p3/reference--keyword-list
                      (cdr (assoc "keywords" entry))))
            (updated (delete-dups (funcall transform current))))
       (bibtex-set-field "keywords" (string-join updated ", "))
       t))))

(defun p3/reference-add-keyword (citekey keyword)
  "Add KEYWORD to CITEKEY without duplicating it."
  (p3/reference--set-keywords
   citekey (lambda (keywords) (append keywords (list keyword)))))

(defun p3/reference-remove-keyword (citekey keyword)
  "Remove KEYWORD from CITEKEY."
  (p3/reference--set-keywords
   citekey (lambda (keywords) (delete keyword (copy-sequence keywords)))))

(defun p3/reference--propose-citekey (citekey)
  "Generate a permanent citekey proposal for provisional CITEKEY."
  (let ((entry (p3/reference--entry-string citekey)))
    (when entry
      (with-temp-buffer
        (insert entry)
        (bibtex-mode)
        (bibtex-set-dialect 'biblatex t)
        (goto-char (point-min))
        (condition-case nil
            (let ((proposal (bibtex-generate-autokey)))
              (when (stringp proposal)
                (string-trim proposal)))
          (error nil))))))

(defun p3/reference--rename-provisional-entry-head (old-key new-key)
  "Rename provisional OLD-KEY to NEW-KEY in its entry head only."
  (unless (p3/reference-provisional-key-p old-key)
    (user-error "Mature citekeys are immutable in v1"))
  (p3/reference--transaction
   (lambda ()
     (unless (p3/reference--goto-entry old-key)
       (user-error "Unknown reference: %s" old-key))
     (unless (re-search-forward p3/reference--entry-head-regexp nil t)
       (error "Could not locate entry head for %s" old-key))
     (unless (equal old-key (match-string-no-properties 2))
       (error "Entry-head mismatch for %s" old-key))
     (replace-match new-key t t nil 2)
     new-key)))

(defun p3/reference-finalize (citekey)
  "Finalize provisional CITEKEY or return mature CITEKEY unchanged."
  (if (not (p3/reference-provisional-key-p citekey))
      citekey
    (let ((proposal (p3/reference--propose-citekey citekey)))
      (unless (and proposal (not (string-empty-p proposal)))
        (user-error "Reference needs more metadata before finalization"))
      (let ((accepted (string-trim
                       (read-string "Permanent citekey: " proposal))))
        (when (or (string-empty-p accepted)
                  (p3/reference-provisional-key-p accepted)
                  (p3/reference--entry-alist accepted))
          (user-error "Permanent citekey is invalid or already used"))
        (p3/reference--rename-provisional-entry-head citekey accepted)
        accepted))))

(provide 'p3-reference)

;;; p3-reference.el ends here
