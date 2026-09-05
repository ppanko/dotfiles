;;; p3-reference.el --- Portable reference workflow -*- lexical-binding: t; -*-

(require 'bibtex)
(require 'cl-lib)
(require 'subr-x)

(defvar org-roam-directory)
(defvar p3/reference-bibliography-file nil)
(defvar p3/reference-pdf-directory nil)

(declare-function biblio-cleanup-doi "biblio-doi" (&rest args))
(declare-function biblio-crossref-lookup "biblio-crossref" (&rest args))
(declare-function biblio-doi-forward-bibtex "biblio-doi" (&rest args))
(declare-function biblio-format-bibtex "biblio-core" (&rest args))
(declare-function citar-get-value "citar" (&rest args))
(declare-function citar-insert-citation "citar" (&rest args))
(declare-function citar-open-entry "citar" (&rest args))
(declare-function citar-select-ref "citar" (&rest args))
(declare-function org-current-level "org" ())
(declare-function org-end-of-subtree "org" (&optional invisible-ok to-heading))
(declare-function org-id-new "org-id" (&optional prefix))
(declare-function org-roam-node-at-point "org-roam-node" (&rest args))
(declare-function org-roam-node-file "org-roam-node" (&rest args))
(declare-function org-roam-node-from-ref "org-roam-node" (&rest args))
(declare-function org-roam-node-read "org-roam-node" (&rest args))
(declare-function org-roam-node-tags "org-roam-node" (&rest args))
(declare-function org-roam-node-visit "org-roam-node" (&rest args))
(declare-function pdf-view-mode "pdf-view" (&optional arg))

(defconst p3/reference-provisional-prefix "p3-inbox-")
(defvar p3/reference--provisional-sequence 0)
(defvar-local p3/reference--biblio-target-key nil)

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

(defun p3/reference--set-field (name value)
  "Set NAME to VALUE in the current BibTeX entry without rebuilding it."
  (save-excursion
    (bibtex-beginning-of-entry)
    (let ((bounds (bibtex-search-forward-field (regexp-quote name) t)))
      (if bounds
          (progn
            (goto-char (bibtex-start-of-text-in-field bounds))
            (delete-region (point) (bibtex-end-of-text-in-field bounds))
            (insert (bibtex-field-left-delimiter)
                    value
                    (bibtex-field-right-delimiter)))
        (bibtex-make-field (list name nil value) t nil))))
  value)

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
       (p3/reference--set-field "keywords" (string-join updated ", "))
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

(defun p3/reference--doi-in-string (string)
  "Return a normalized DOI recognized directly in STRING, or nil."
  (when (stringp string)
    (let ((case-fold-search t))
      (when (string-match
             "\\(10\\.[0-9][0-9][0-9][0-9]+/[[:alnum:]._()/:;-]+\\)"
             string)
        (p3/reference-normalize-doi (match-string 1 string))))))

(defun p3/reference--input-kind (input)
  "Classify INPUT as BibTeX, DOI, URL, or bibliographic search text."
  (let ((value (string-trim (or input ""))))
    (cond
     ((string-match-p "\\`@[[:alpha:]][[:alnum:]_-]*[[:space:]]*[{(]" value)
      'bibtex)
     ((p3/reference--doi-in-string value) 'doi)
     ((string-match-p "\\`https?://" value) 'url)
     (t 'search))))

(defun p3/reference--capture-url (url)
  "Save URL immediately as a provisional offline reference."
  (let ((key (p3/reference--new-provisional-key)))
    (p3/reference--transaction
     (lambda ()
       (goto-char (point-max))
       (unless (bolp) (insert "\n"))
       (insert (format
                "@online{%s,\n  url = {%s},\n  urldate = {%s},\n  keywords = {status/inbox}\n}\n"
                key url (format-time-string "%Y-%m-%d")))))
    key))

(defun p3/reference--lookup-doi (input &optional target-key)
  "Look up DOI from INPUT and import it, or merge into TARGET-KEY."
  (unless (require 'biblio-doi nil t)
    (user-error "Biblio DOI support is unavailable"))
  (let ((doi (or (p3/reference--doi-in-string input)
                 (p3/reference-normalize-doi input))))
    (unless doi
      (user-error "No DOI found"))
    (biblio-doi-forward-bibtex
     (biblio-cleanup-doi doi)
     (lambda (raw)
       (let ((bibtex (biblio-format-bibtex raw nil)))
         (if target-key
             (p3/reference-merge-bibtex target-key bibtex)
           (p3/reference-import-bibtex bibtex)))))))

(defun p3/reference--lookup-title (query &optional target-key)
  "Open a Crossref search for QUERY and optionally target TARGET-KEY."
  (unless (require 'biblio-crossref nil t)
    (user-error "Biblio Crossref support is unavailable"))
  (let ((buffer (biblio-crossref-lookup query)))
    (when (and target-key (buffer-live-p buffer))
      (with-current-buffer buffer
        (setq-local p3/reference--biblio-target-key target-key)))
    buffer))

(defun p3/reference-add (&optional input)
  "Capture or look up a reference from INPUT."
  (interactive)
  (let ((value (or input
                   (read-string "Reference (DOI, URL, BibTeX, or search): "))))
    (pcase (p3/reference--input-kind value)
      ('bibtex (p3/reference-import-bibtex value))
      ('doi (p3/reference--lookup-doi value))
      ('url (p3/reference--capture-url value))
      ('search (p3/reference--lookup-title value)))))

(defun p3/reference-merge-bibtex (target-key bibtex)
  "Merge BIBTEX metadata into TARGET-KEY without changing its identity."
  (unless (p3/reference--entry-alist target-key)
    (user-error "Unknown reference: %s" target-key))
  (let* ((remote (p3/reference--parse-single-entry bibtex))
         (duplicate (p3/reference--strong-duplicate-key remote)))
    (when (and duplicate (not (equal duplicate target-key)))
      (user-error "Retrieved metadata already belongs to %s" duplicate))
    (p3/reference--transaction
     (lambda ()
       (unless (p3/reference--goto-entry target-key)
         (user-error "Unknown reference: %s" target-key))
       (let ((current (bibtex-parse-entry t)))
         (dolist (field remote)
           (let ((name (car field))
                 (value (cdr field)))
             (unless (or (member name '("=key=" "=type="))
                         (not (stringp value))
                         (string-empty-p (string-trim value)))
               (let ((existing (cdr (assoc name current))))
                 (cond
                  ((or (null existing) (string-empty-p (string-trim existing)))
                   (p3/reference--set-field name value))
                  ((equal existing value) nil)
                  ((y-or-n-p
                    (format "Replace %s for %s? " name target-key))
                   (p3/reference--set-field name value))))))))
       target-key))))

(defun p3/reference-biblio-save (metadata)
  "Save selected Biblio METADATA to the P3 library or enrichment target."
  (let ((target p3/reference--biblio-target-key)
        (backend (alist-get 'backend metadata)))
    (unless backend
      (user-error "Biblio result has no backend"))
    (funcall
     backend 'forward-bibtex metadata
     (lambda (raw)
       (let ((bibtex (biblio-format-bibtex raw nil)))
         (if target
             (p3/reference-merge-bibtex target bibtex)
           (p3/reference-import-bibtex bibtex)))))))

(defun p3/reference-enrich (&optional citekey)
  "Enrich CITEKEY from DOI or an explicit Crossref result selection."
  (interactive)
  (let* ((key (or citekey
                  (if (fboundp 'p3/reference--select-key)
                      (p3/reference--select-key)
                    (user-error "Reference selection is unavailable"))))
         (entry (p3/reference--entry-alist key)))
    (unless entry
      (user-error "Unknown reference: %s" key))
    (let ((doi (cdr (assoc "doi" entry)))
          (title (cdr (assoc "title" entry)))
          (url (cdr (assoc "url" entry))))
      (cond
       ((and doi (not (string-empty-p (string-trim doi))))
        (p3/reference--lookup-doi doi key))
       ((and title (not (string-empty-p (string-trim title))))
        (p3/reference--lookup-title title key))
       ((and url (not (string-empty-p (string-trim url))))
        (p3/reference--lookup-title url key))
       (t
        (user-error "Reference needs a DOI, title, or URL for enrichment"))))))

(cl-defun p3/reference--select-key (&optional (allowed-keys nil allowed-p))
  "Select one reference key, optionally limited to ALLOWED-KEYS."
  (unless (require 'citar nil t)
    (user-error "Citar is unavailable"))
  (when (and allowed-p (null allowed-keys))
    (user-error "No references are available in this scope"))
  (if allowed-p
      (let ((allowed (copy-sequence allowed-keys)))
        (citar-select-ref :filter (lambda (key) (member key allowed))))
    (citar-select-ref)))

(defun p3/reference-open-url (citekey)
  "Open CITEKEY's URL, falling back to its DOI URL."
  (unless (require 'citar nil t)
    (user-error "Citar is unavailable"))
  (let ((url (citar-get-value "url" citekey))
        (doi (citar-get-value "doi" citekey)))
    (cond
     ((and url (not (string-empty-p (string-trim url))))
      (browse-url url))
     ((p3/reference-normalize-doi doi)
      (browse-url (concat "https://doi.org/" (p3/reference-normalize-doi doi))))
     (t
      (user-error "Reference has no URL or DOI: %s" citekey)))))

(defun p3/reference-edit-entry (citekey)
  "Open CITEKEY in its canonical bibliography."
  (unless (require 'citar nil t)
    (user-error "Citar is unavailable"))
  (citar-open-entry citekey))

(defun p3/reference-insert-citation (&optional citekey)
  "Insert a native citation for CITEKEY, finalizing provisional keys first."
  (interactive)
  (unless (require 'citar nil t)
    (user-error "Citar is unavailable"))
  (let* ((key (or citekey (p3/reference--select-key)))
         (mature (if (p3/reference-provisional-key-p key)
                     (p3/reference-finalize key)
                   key)))
    (citar-insert-citation (list mature))))

(defun p3/reference--action-alist ()
  "Return the common actions offered for a selected reference."
  '(("Insert citation" . p3/reference-insert-citation)
    ("Open URL" . p3/reference-open-url)
    ("Edit bibliography entry" . p3/reference-edit-entry)
    ("Open/create literature note" . p3/reference-note)
    ("Open PDF" . p3/reference-open-pdf)
    ("Classify / project association" . p3/reference-classify)))

(defun p3/reference-find (&optional allowed-keys)
  "Find a reference, optionally restricted to ALLOWED-KEYS, then act on it."
  (interactive)
  (let ((key (if allowed-keys
                 (p3/reference--select-key allowed-keys)
               (p3/reference--select-key))))
    (when key
      (let* ((actions (p3/reference--action-alist))
             (label (completing-read "Reference action: " actions nil t))
             (fn (cdr (assoc label actions))))
        (funcall fn key)))))

(defun p3/reference--display-title (citekey)
  "Return a human-readable title for CITEKEY without making Citar authoritative."
  (or (when (require 'citar nil t)
        (citar-get-value "title" citekey))
      (condition-case nil
          (cdr (assoc "title" (p3/reference--entry-alist citekey)))
        (error nil))
      citekey))

(defun p3/reference-note (&optional citekey)
  "Open or create the one Org-roam literature note for CITEKEY."
  (interactive)
  (unless (require 'org-roam nil t)
    (user-error "Org-roam is unavailable"))
  (require 'org-id)
  (let* ((selected (or citekey (p3/reference--select-key)))
         (key (if (p3/reference-provisional-key-p selected)
                  (p3/reference-finalize selected)
                selected))
         (ref (concat "@" key))
         (node (org-roam-node-from-ref ref)))
    (cond
     (node
      (org-roam-node-visit node))
     (t
      (let* ((directory (file-name-as-directory
                         (expand-file-name org-roam-directory)))
             (path (expand-file-name (concat key ".org") directory)))
        (if (file-exists-p path)
            (find-file path)
          (make-directory directory t)
          (with-temp-file path
            (insert ":PROPERTIES:\n")
            (insert (format ":ID: %s\n" (org-id-new)))
            (insert (format ":ROAM_REFS: @%s\n" key))
            (insert ":END:\n")
            (insert (format "#+title: %s\n" (p3/reference--display-title key)))
            (insert "#+filetags: :literature:\n\n"))
          (find-file path)))))))

(defun p3/reference--project-node-p (node)
  "Return non-nil when NODE carries the Org-roam project tag."
  (member "project" (org-roam-node-tags node)))

(defun p3/reference--current-project-node ()
  "Return the current Org-roam project node, or nil."
  (when (and (derived-mode-p 'org-mode)
             (require 'org-roam nil t))
    (let ((node (org-roam-node-at-point)))
      (and node (p3/reference--project-node-p node) node))))

(defun p3/reference--select-project-node ()
  "Prompt for one Org-roam project node."
  (unless (require 'org-roam nil t)
    (user-error "Org-roam is unavailable"))
  (org-roam-node-read nil #'p3/reference--project-node-p nil t))

(defun p3/reference--project-file (node)
  "Return the file backing project NODE."
  (unless (require 'org-roam nil t)
    (user-error "Org-roam is unavailable"))
  (org-roam-node-file node))

(defun p3/reference--project-reference-bounds ()
  "Return body bounds of the level-one References subtree in current Org buffer."
  (require 'org)
  (save-excursion
    (goto-char (point-min))
    (let (bounds)
      (while (and (not bounds)
                  (re-search-forward "^\\* References[ \t]*$" nil t))
        (when (= (or (org-current-level) 0) 1)
          (let ((start (line-beginning-position 2))
                (end (save-excursion
                       (org-end-of-subtree t t)
                       (point))))
            (setq bounds (cons start end)))))
      bounds)))

(defun p3/reference-project-citekeys (&optional node)
  "Return explicit reference-registry citekeys for project NODE."
  (let* ((project (or node (p3/reference--current-project-node)
                      (p3/reference--select-project-node))))
    (unless (p3/reference--project-node-p project)
      (user-error "Selected Org-roam node is not a project"))
    (let ((file (p3/reference--project-file project)))
      (with-temp-buffer
        (insert-file-contents file)
        (org-mode)
        (let ((bounds (p3/reference--project-reference-bounds))
              keys)
          (when bounds
            (goto-char (car bounds))
            (while (re-search-forward
                    "^[ \t]*\\[cite:@\\([^] ;,]+\\)\\][ \t]*$"
                    (cdr bounds) t)
              (push (match-string-no-properties 1) keys)))
          (nreverse (delete-dups keys)))))))

(defun p3/reference--associate-mature-key (citekey node)
  "Associate mature CITEKEY with project NODE."
  (when (p3/reference-provisional-key-p citekey)
    (user-error "Project associations require a mature citekey"))
  (unless (p3/reference--project-node-p node)
    (user-error "Selected Org-roam node is not a project"))
  (let ((file (p3/reference--project-file node)))
    (with-temp-buffer
      (insert-file-contents file)
      (org-mode)
      (let ((bounds (p3/reference--project-reference-bounds)))
        (if bounds
            (unless (member citekey
                            (let (keys)
                              (save-excursion
                                (goto-char (car bounds))
                                (while (re-search-forward
                                        "^[ \t]*\\[cite:@\\([^] ;,]+\\)\\][ \t]*$"
                                        (cdr bounds) t)
                                  (push (match-string-no-properties 1) keys)))
                              keys))
              (goto-char (cdr bounds))
              (unless (bolp) (insert "\n"))
              (insert (format "[cite:@%s]\n" citekey)))
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert (format "\n* References\n\n[cite:@%s]\n" citekey))))
      (write-region (point-min) (point-max) file nil 'silent)))
  citekey)

(defun p3/reference-associate-project (citekey &optional node)
  "Associate CITEKEY with project NODE, finalizing it first if needed."
  (interactive (list (p3/reference--select-key)))
  (let* ((project (or node (p3/reference--current-project-node)
                      (p3/reference--select-project-node)))
         (mature (if (p3/reference-provisional-key-p citekey)
                     (p3/reference-finalize citekey)
                   citekey)))
    (p3/reference--associate-mature-key mature project)))

(defun p3/reference-remove-project-association (citekey &optional node)
  "Remove CITEKEY from project NODE's canonical References registry only."
  (interactive (list (p3/reference--select-key)))
  (let ((project (or node (p3/reference--current-project-node)
                     (p3/reference--select-project-node))))
    (unless (p3/reference--project-node-p project)
      (user-error "Selected Org-roam node is not a project"))
    (let ((file (p3/reference--project-file project)))
      (with-temp-buffer
        (insert-file-contents file)
        (org-mode)
        (let ((bounds (p3/reference--project-reference-bounds))
              (regexp (format "^[ \t]*\\[cite:@%s\\][ \t]*\\n?"
                              (regexp-quote citekey))))
          (when bounds
            (goto-char (car bounds))
            (when (re-search-forward regexp (cdr bounds) t)
              (replace-match ""))))
        (write-region (point-min) (point-max) file nil 'silent))))
  citekey)

(defun p3/reference-project-references (&optional node)
  "Browse the canonical references associated with project NODE."
  (interactive)
  (let ((keys (p3/reference-project-citekeys node)))
    (unless keys
      (user-error "Project has no associated references"))
    (p3/reference-find keys)))

(defun p3/reference-classify (&optional citekey)
  "Classify CITEKEY globally or associate it with a project."
  (interactive)
  (let* ((key (or citekey (p3/reference--select-key)))
         (actions '("Add topic/status keyword"
                    "Remove topic/status keyword"
                    "Associate with project"
                    "Remove project association"))
         (action (completing-read "Reference classification: " actions nil t)))
    (pcase action
      ("Add topic/status keyword"
       (p3/reference-add-keyword key (read-string "Keyword: ")))
      ("Remove topic/status keyword"
       (let* ((entry (p3/reference--entry-alist key))
              (keywords (p3/reference--keyword-list
                         (cdr (assoc "keywords" entry))))
              (keyword (completing-read "Remove keyword: " keywords nil t)))
         (p3/reference-remove-keyword key keyword)))
      ("Associate with project"
       (p3/reference-associate-project key))
      ("Remove project association"
       (p3/reference-remove-project-association key)))))

(defun p3/reference-pdf-path (citekey)
  "Return deterministic main PDF path for mature CITEKEY."
  (when (p3/reference-provisional-key-p citekey)
    (user-error "Finalize the reference before assigning a PDF path"))
  (unless (and (stringp p3/reference-pdf-directory)
               (not (string-empty-p p3/reference-pdf-directory)))
    (user-error "Reference PDF directory is not configured"))
  (expand-file-name
   "main.pdf"
   (expand-file-name citekey
                     (file-name-as-directory
                      (expand-file-name p3/reference-pdf-directory)))))

(defun p3/reference-attach-pdf (source &optional citekey)
  "Copy SOURCE to CITEKEY's deterministic main PDF path."
  (interactive (list (read-file-name "PDF file: ") nil))
  (let* ((selected (or citekey (p3/reference--select-key)))
         (key (if (p3/reference-provisional-key-p selected)
                  (p3/reference-finalize selected)
                selected))
         (target (p3/reference-pdf-path key)))
    (unless (file-readable-p source)
      (user-error "PDF source is not readable: %s" source))
    (make-directory (file-name-directory target) t)
    (when (and (file-exists-p target)
               (not (y-or-n-p (format "Replace existing %s? " target))))
      (user-error "PDF attachment cancelled"))
    (copy-file source target t)
    target))

(defun p3/reference-open-pdf (&optional citekey)
  "Open CITEKEY's deterministic main PDF, using pdf-tools when usable."
  (interactive)
  (let* ((selected (or citekey (p3/reference--select-key)))
         (key (if (p3/reference-provisional-key-p selected)
                  (p3/reference-finalize selected)
                selected))
         (path (p3/reference-pdf-path key)))
    (unless (file-exists-p path)
      (user-error "No local PDF for %s" key))
    (find-file path)
    (if (and (require 'pdf-tools nil t) (fboundp 'pdf-view-mode))
        (condition-case err
            (pdf-view-mode)
          (error
           (message "pdf-tools unavailable (%s); using default PDF viewer"
                    (error-message-string err))))
      (message "pdf-tools unavailable; using default PDF viewer"))
    path))

(defvar p3/reference-command-map nil)
(setq p3/reference-command-map
      (let ((map (make-sparse-keymap)))
        (define-key map (kbd "a") #'p3/reference-add)
        (define-key map (kbd "f") #'p3/reference-find)
        (define-key map (kbd "i") #'p3/reference-insert-citation)
        (define-key map (kbd "n") #'p3/reference-note)
        (define-key map (kbd "p") #'p3/reference-open-pdf)
        (define-key map (kbd "t") #'p3/reference-classify)
        (define-key map (kbd "r") #'p3/reference-project-references)
        map))

(provide 'p3-reference)

;;; p3-reference.el ends here
