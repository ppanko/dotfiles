;;; p3-config-reference.el --- Reference management configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(defvar biblio-selection-mode-actions-alist)
(defvar citar-bibliography)
(defvar org-cite-activate-processor)
(defvar org-cite-follow-processor)
(defvar org-cite-global-bibliography)
(defvar org-cite-insert-processor)

(defcustom p3/reference-bibliography-file
  (expand-file-name "~/org/bib/main.bib")
  "Canonical personal BibLaTeX bibliography."
  :type 'file)

(defcustom p3/reference-pdf-directory
  (file-name-as-directory (expand-file-name "~/org/lib/"))
  "Root directory for citekey-organized reference PDFs."
  :type 'directory)

(p3/config-load-module 'p3-reference)

(setq bibtex-dialect 'biblatex
      bibtex-align-at-equal-sign t
      org-cite-global-bibliography (list p3/reference-bibliography-file)
      org-cite-insert-processor 'citar
      org-cite-follow-processor 'citar
      org-cite-activate-processor 'citar
      citar-bibliography (list p3/reference-bibliography-file))

(use-package citar
  :defer t
  :commands (citar-select-ref
             citar-insert-citation
             citar-get-value
             citar-open-entry))

(use-package biblio
  :defer t
  :commands biblio-lookup
  :config
  (add-to-list 'biblio-selection-mode-actions-alist
               '("Save/enrich in P3 library" . p3/reference-biblio-save)))

(use-package pdf-tools
  :defer t
  :commands pdf-view-mode)

(global-set-key (kbd "C-c b") p3/reference-command-map)

(provide 'p3-config-reference)

;;; p3-config-reference.el ends here
