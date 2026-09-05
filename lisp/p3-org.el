;;; p3-org.el --- Core Org workflow helpers -*- lexical-binding: t; -*-

(declare-function org-sort-entries
                  "org"
                  (&optional with-case sorting-type get-key-func compare-func
                             property interactive?))

(defun p3/org-sort-todos ()
  "Sort sibling entries by TODO state without changing outline hierarchy.
Run this on a parent heading to sort its children; DONE entries follow active
TODO states according to `org-todo-keywords'."
  (interactive)
  (org-sort-entries nil ?o))

(defun org-set-line-checkbox (arg)
  (interactive "p")
  (let ((n (or arg 1)))
    (when (region-active-p)
      (setq n (count-lines (region-beginning)
                           (region-end)))
      (goto-char (region-beginning)))
    (dotimes (_i n)
      (beginning-of-line)
      (insert "- [ ] ")
      (forward-line))
    (beginning-of-line)))

(provide 'p3-org)

;;; p3-org.el ends here
