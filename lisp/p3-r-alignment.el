;;; p3-r-alignment.el --- Scope-aware R assignment alignment -*- lexical-binding: t; -*-

;;; Commentary:
;; Align simple R assignments conservatively within contiguous syntactic
;; groups.  Automatic alignment is buffer-local to ESS R buffers and runs just
;; before save, so editing does not jump while operators are being typed.

;;; Code:

(defgroup p3-r-alignment nil
  "Automatic alignment for R assignments."
  :group 'editing)

(defcustom p3-r-align-on-save t
  "When non-nil, align R assignments immediately before saving.

Alignment is conservative: only simple named left-hand sides are considered,
and only contiguous lines using the same operator in the same syntactic scope
are aligned together."
  :type 'boolean
  :group 'p3-r-alignment)

(defvar ess-r-mode-hook)

(defconst p3-r--alignment-line-regexp
  "^[ \t]*\\(?:[[:alnum:]_.]+\\|`[^`\n]+`\\)\\([ \t]*\\)\\(<-\\|=\\)"
  "Regexp matching the leading assignment form on an R source line.")

(defun p3-r--alignment-assignment-operator-p (operator beginning end)
  "Return non-nil when OPERATOR at BEGINNING..END is an assignment operator."
  (let ((state (syntax-ppss beginning)))
    (and (not (nth 3 state))
         (not (nth 4 state))
         (cond
          ((equal operator "<-")
           (not (eq (char-before beginning) ?<)))
          ((equal operator "=")
           (not (memq (char-after end) '(?= ?>))))
          (t nil)))))

(defun p3-r--alignment-candidate-at-line ()
  "Return alignment metadata for the current line, or nil.

The returned plist records the operator, syntactic scope, whitespace bounds,
and display column immediately after the left-hand side."
  (let ((line-end (line-end-position)))
    (save-excursion
      (beginning-of-line)
      (when (re-search-forward p3-r--alignment-line-regexp line-end t)
        (let* ((space-beginning (match-beginning 1))
               (operator-beginning (match-beginning 2))
               (operator-end (match-end 2))
               (operator (match-string-no-properties 2))
               (state (syntax-ppss operator-beginning)))
          (when (p3-r--alignment-assignment-operator-p
                 operator operator-beginning operator-end)
            (goto-char space-beginning)
            (list :operator operator
                  :scope (cons (car state) (nth 1 state))
                  :space-beginning space-beginning
                  :operator-beginning operator-beginning
                  :lhs-column (current-column))))))))

(defun p3-r--alignment-groups ()
  "Return contiguous assignment groups in the accessible buffer.

A new group begins when a line has no eligible assignment, changes assignment
operator, or moves to another syntactic scope."
  (save-excursion
    (goto-char (point-min))
    (let (groups current-group current-key)
      (while (< (point) (point-max))
        (let* ((candidate (p3-r--alignment-candidate-at-line))
               (key (and candidate
                         (list (plist-get candidate :operator)
                               (plist-get candidate :scope)))))
          (if (and candidate (equal key current-key))
              (push candidate current-group)
            (when current-group
              (push (nreverse current-group) groups))
            (setq current-group (and candidate (list candidate))
                  current-key key)))
        (forward-line 1))
      (when current-group
        (push (nreverse current-group) groups))
      (nreverse groups))))

(defun p3-r--align-assignment-group (group)
  "Align assignment operators in GROUP.

Singleton groups are intentionally left unchanged."
  (when (cdr group)
    (let ((target-column
           (1+ (apply #'max
                      (mapcar (lambda (candidate)
                                (plist-get candidate :lhs-column))
                              group)))))
      ;; Work from the bottom up so whitespace edits cannot invalidate the
      ;; saved positions of candidates that have not yet been processed.
      (dolist (candidate (reverse group))
        (let ((space-beginning (plist-get candidate :space-beginning))
              (operator-beginning (plist-get candidate :operator-beginning)))
          (goto-char space-beginning)
          (delete-region space-beginning operator-beginning)
          (insert (make-string (max 1 (- target-column (current-column)))
                               ?\s)))))))

(defun p3-r-align-assignments ()
  "Align simple R assignments in independent syntactic groups.

Only whitespace immediately before `<-' or `=' is changed.  Blank lines,
comments, incompatible statements, operator changes, and syntax-scope changes
terminate an alignment group."
  (interactive)
  (save-match-data
    (save-excursion
      (save-restriction
        (widen)
        (let ((groups (p3-r--alignment-groups)))
          (atomic-change-group
            (dolist (group (reverse groups))
              (p3-r--align-assignment-group group))))))))

(defun p3-r-align-before-save ()
  "Align assignments before save when `p3-r-align-on-save' is non-nil."
  (when p3-r-align-on-save
    (p3-r-align-assignments)))

(defun p3-r-enable-alignment-on-save ()
  "Install automatic R assignment alignment in the current buffer."
  (add-hook 'before-save-hook #'p3-r-align-before-save nil t))

(defun p3-r-alignment-setup ()
  "Enable buffer-local on-save alignment for future ESS R buffers."
  (add-hook 'ess-r-mode-hook #'p3-r-enable-alignment-on-save))

(provide 'p3-r-alignment)

;;; p3-r-alignment.el ends here
