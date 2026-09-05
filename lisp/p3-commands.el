;;; p3-commands.el --- Generic personal interactive commands -*- lexical-binding: t; -*-

(require 'subr-x)
(declare-function dired-get-marked-files "dired" (&optional localp arg filter distinguish-one-marked error))
(declare-function w32-shell-execute "w32fns" (operation document &optional parameters show-flag))

(defconst p3/keybinding-sections
  '(("Global"
     ("C-s / C-r" . "search forward/backward")
     ("M-x" . "run a command")
     ("C-x b" . "switch buffer")
     ("C-c e" . "visit config")
     ("C-c r" . "reload config")
     ("C-c ?" . "open this atlas")
     ("C-h B" . "show context-sensitive bindings")
     ("M-o" . "select window"))
    ("Project"
     ("C-c p / C-x p" . "native project commands")
     ("s-p" . "native project commands"))
    ("R / ESS"
     ("C-c R" . "R project, templates, and tools")
     ("C-c i" . "evaluate library section")
     ("C-c v" . "view data frame")
     ("C-c m" . "run targets make")
     ("C-c d" . "debug targets make")
     ("C-c l" . "load targets object")
     ("S-RET" . "evaluate and step"))
    ("Org"
     ("C-c s" . "insert source block")
     ("C-c C-o" . "open link at point")
     ("C-c E" . "export Org file")
     ("C-c C-x C-o" . "sort TODO entries")
     ("C-c P" . "start presentation"))
    ("References"
     ("C-c b a" . "add reference")
     ("C-c b f" . "find reference")
     ("C-c b i" . "insert citation")
     ("C-c b n" . "literature note")
     ("C-c b p" . "open reference PDF")
     ("C-c b t" . "classify / associate")
     ("C-c b r" . "project references"))
    ("Presentation"
     ("SPC / right" . "next slide")
     ("DEL / left" . "previous slide")
     ("n / p" . "next/previous slide")
     ("f" . "toggle fullscreen")
     ("q" . "quit presentation"))
    ("Python"
     ("S-RET" . "send statement")
     ("C-c C-c" . "send region/paragraph")
     ("C-c C-z" . "show Python shell")
     ("C-c l r" . "rename symbol")
     ("C-c l a" . "code actions")
     ("C-c l f" . "format buffer"))
    ("GPTel"
     ("C-c g l" . "send current line")
     ("C-c g r" . "refactor region")
     ("C-c g d" . "generate documentation")
     ("C-c g t" . "write tests")
     ("C-c g c" . "translate code")
     ("C-c g w" . "write code"))
    ("Magit"
     ("C-c m g" . "status")
     ("C-c m s" . "stage files")
     ("C-c m c" . "commit")
     ("C-c m f" . "pull")
     ("C-c m P" . "push")
     ("C-c m d" . "diff")
     ("C-c m l" . "log")
     ("C-c m b" . "blame"))
    ("Org-roam"
     ("C-c n l" . "toggle roam buffer")
     ("C-c n f" . "find node")
     ("C-c n g" . "graph")
     ("C-c n i" . "insert node")
     ("C-c n c" . "capture node")
     ("C-c n d" . "daily note"))
    ("Terminal"
     ("C-c T" . "terminal commands")
     ("C-x C-u" . "open shell")
     ("C-S-c" . "copy from vterm")))
  "Sections shown by `p3/keybinding-atlas'.")

(defun p3/keybinding-atlas ()
  "Display the personal keybinding guide, organized by workflow."
  (interactive)
  (with-help-window "*P3 Keybinding Atlas*"
    (princ "P3 KEYBINDING ATLAS\n")
    (princ "=====================\n\n")
    (princ "These are the workflow bindings worth remembering.\n")
    (princ "For every binding active in the current buffer, use C-h b.\n")
    (princ "For prefix hints, press the prefix and wait for which-key.\n")
    (dolist (section p3/keybinding-sections)
      (princ (format "\n%s\n%s\n"
                     (car section)
                     (make-string (length (car section)) ?-)))
      (dolist (binding (cdr section))
        (princ (format "  %-16s %s\n"
                       (car binding) (cdr binding)))))))

(defun p3/save-kill-other-buffers ()
  "Save and kill all other buffers."
  (interactive)
  (save-some-buffers)
  (mapc 'kill-buffer (buffer-list)))

(defun p3/sudo-edit (&optional arg)
  "Edit currently visited file as root.

With a prefix ARG prompt for a file to visit.
Will also prompt for a file to visit if current
buffer is not visiting a file."
  (interactive "p")
  (if (or arg (not buffer-file-name))
      (find-file (concat "/sudo:root@localhost:"
                         (read-file-name "Find file(as root): ")))
    (find-alternate-file (concat "/sudo:root@localhost:" buffer-file-name))))

(defun p3/region-suffix (r1 r2)
  (interactive "r")
  (perform-replace " *$"
                   (read-string "Enter suffix:")
                   nil 'regexp nil nil nil r1 r2 nil nil))

(defun p3/newline-after-comma-or-space ()
  (interactive)
  (perform-replace "\\(?1:[^,][[:punct:]]?+\\)\\(,\\|[[:space:]]+\\)" "\\1
" nil t nil nil nil (region-beginning) (region-end)))

(defun p3/force-quotes ()
  (interactive)
  (perform-replace "\\(?1:\\([[:punct:]]\|[[:space:]]\\)\\)+\\(?2:[A-z]?+\_?+\\.?+[0-9]?+[A-z]?+\\)\\(?3:\\([[:punct:]]\|[[:space:]]\\)\\)+" "\\1\"\\2\"\\3" nil t nil nil nil (region-beginning) (region-end)))

(defun p3/byte-compile-init-dir ()
  "Byte-compile all your dotfiles."
  (interactive)
  (byte-recompile-directory user-emacs-directory 0))

(when (eq system-type 'windows-nt)
  (defun p3/windows-shell ()
    "Open a new Windows cmd.exe window."
    (interactive)
    (let ((proc (start-process "cmd" nil "cmd.exe" "/C" "start" "cmd.exe")))
      (set-process-query-on-exit-flag proc nil))))

(defun move-line (n)
  "Move the current line up or down by N lines."
  (interactive "p")
  (let ((column (current-column))
        (start (line-beginning-position))
        (end (line-beginning-position 2)))
    (let ((line-text (delete-and-extract-region start end)))
      (forward-line n)
      (insert line-text)
      ;; Restore point to its original column in the moved line.
      (forward-line -1)
      (move-to-column column))))

(defun move-line-up (n)
  "Move the current line up by N lines."
  (interactive "p")
  (move-line (if (null n) -1 (- n))))

(defun move-line-down (n)
  "Move the current line down by N lines."
  (interactive "p")
  (move-line (if (null n) 1 n)))

(defun p3/open-in-external-app (&optional file)
  "Open the current file or dired marked files in external app.

The app is chosen from your OS's preference."
  (interactive)
  (let (doIt
        (myFileList
         (cond
          ((string-equal major-mode "dired-mode") (dired-get-marked-files))
          ((not file) (list (buffer-file-name)))
          (file (list file)))))
    (setq doIt (if (<= (length myFileList) 5)
                   t
                 (y-or-n-p "Open more than 5 files? ")))
    (when doIt
      (cond
       ((string-equal system-type "windows-nt")
        (mapc (lambda (fPath)
                (w32-shell-execute
                 "open" (replace-regexp-in-string "/" "\\" fPath t t)))
              myFileList))
       ((string-equal system-type "darwin")
        (mapc (lambda (fPath)
                (shell-command (format "open \"%s\"" fPath)))
              myFileList))
       ((string-equal system-type "gnu/linux")
        (mapc (lambda (fPath)
                (let ((process-connection-type nil))
                  (start-process "" nil "xdg-open" fPath)))
              myFileList))))))

(defun check-curl-version ()
  "Check the version of curl being used by Emacs."
  (interactive)
  (let ((curl-version (shell-command-to-string "curl --version")))
    (if (string-match "^curl \\([0-9.]+\\)" curl-version)
        (message "Curl version: %s" (match-string 1 curl-version))
      (message "Could not determine curl version"))))

(defun p3/get-local-buffer-mode ()
  (interactive)
  (buffer-local-value 'major-mode (get-buffer (frame-parameter nil 'name))))

(defun p3/is-current-buffer-mode-inferior-ess-r-mode ()
  (interactive)
  (eq 'inferior-ess-r-mode (p3/get-local-buffer-mode)))

(provide 'p3-commands)

;;; p3-commands.el ends here
