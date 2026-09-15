;;; p3-platform.el --- Platform-specific bootstrap helpers -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep operating-system discovery and environment mutation in one place.
;; Windows uses the MSYS2 environment bundled with Rtools for Unix command-line
;; tools and discovers the newest installed R when no machine-local override is
;; configured.  The literate config decides when each setup stage runs.

;;; Code:

(require 'seq)
(require 'subr-x)

(declare-function comint-strip-ctrl-m "comint" (string))

(defvar explicit-bash.exe-args)
(defvar explicit-shell-file-name)
(defvar inferior-R-program-name)
(defvar package-gnupghome-dir)
(defvar tramp-default-method)

(defgroup p3/platform nil
  "Platform-specific behavior for the personal Emacs configuration."
  :group 'environment)

(defvar p3/windows-rtools-override nil
  "Optional Rtools installation directory to use on Windows.
Set this in secrets.el when a machine should not use auto-detection.")

(defvar p3/windows-r-program-override nil
  "Optional absolute path to Rterm.exe on Windows.
Set this in secrets.el when a machine should not use auto-detection.")

(defvar p3/windows-rtools-selection-cache :uninitialized
  "Session cache `(OVERRIDE RESULT)' for selected Rtools, including nil.")

(defvar p3/windows-r-program-selection-cache :uninitialized
  "Session cache `(OVERRIDE RESULT)' for selected Windows R, including nil.")

(defvar rtools-path nil
  "Selected Rtools installation directory on Windows.")

(defvar linuxy-environment-path nil
  "Selected Rtools MSYS2 usr/bin directory on Windows.")

;; Compatibility name retained for older personal code.  On newer Rtools
;; releases this may point at the static-posix toolchain rather than a
;; directory literally named mingw64.
(defvar mingw64-path nil
  "Selected Rtools compiler/toolchain bin directory, when available.")

(defvar p3/windows-hunspell-program nil
  "Hunspell executable found in the selected Rtools installation.")

(defvar p3/windows-hunspell-dictionary-directory nil
  "Hunspell dictionary directory found in the selected Rtools installation.")

(defun p3/windows-p ()
  "Return non-nil when Emacs is running natively on Windows."
  (eq system-type 'windows-nt))

(defun p3/platform-bash-program ()
  "Return the Bash executable for the current supported platform."
  (let ((program
         (if (p3/windows-p)
             (and linuxy-environment-path
                  (let ((candidate
                         (expand-file-name "bash.exe"
                                           linuxy-environment-path)))
                    (and (file-regular-p candidate) candidate)))
           (executable-find "bash"))))
    (or program
        (user-error "Bash is unavailable for the current platform setup"))))

(defun p3/platform-configure-tramp ()
  "Configure the default TRAMP method for the current supported platform."
  (pcase system-type
    ('windows-nt (setq tramp-default-method "plink"))
    ('gnu/linux (setq tramp-default-method "ssh"))))

(defun p3/windows-normalize-gnupg-path (windows-path)
  "Normalize WINDOWS-PATH for the package GnuPG home workaround."
  (let* ((path (replace-regexp-in-string "\\\\" "/" windows-path))
         (path (replace-regexp-in-string
                "^\\([a-zA-Z]\\):" "/\\1" path)))
    (downcase path)))

(defun p3/windows-configure-gnupg ()
  "Configure the package GnuPG home path for native Windows Emacs."
  (when (p3/windows-p)
    (setq package-gnupghome-dir
          (p3/windows-normalize-gnupg-path
           (expand-file-name "elpa/gnupg" user-emacs-directory)))))

(defun p3/windows-rtools-version (directory)
  "Return the numeric version suffix from an rtoolsNN DIRECTORY."
  (let ((name (downcase
               (file-name-nondirectory (directory-file-name directory)))))
    (when (string-match "\\`rtools\\([0-9]+\\)\\'" name)
      (string-to-number (match-string 1 name)))))

(defun p3/windows-rtools-usable-p (directory)
  "Return non-nil when DIRECTORY contains the Rtools MSYS2 Bash."
  (and (file-directory-p directory)
       (file-regular-p (expand-file-name "usr/bin/bash.exe" directory))))

(defun p3/windows-latest-rtools ()
  "Return the newest usable C:/rtoolsNN installation."
  (when (and (p3/windows-p)
             (file-directory-p "C:/"))
    (car
     (sort
      (seq-filter
       #'p3/windows-rtools-usable-p
       (directory-files "C:/" t "\\`rtools[0-9]+\\'" t))
      (lambda (a b)
        (> (p3/windows-rtools-version a)
           (p3/windows-rtools-version b)))))))

(defun p3/windows-rtools-first-existing (root relatives directory-p)
  "Return the first existing path below ROOT from RELATIVES.
When DIRECTORY-P is non-nil, require a directory; otherwise require a file."
  (catch 'found
    (dolist (relative relatives)
      (let ((candidate (expand-file-name relative root)))
        (when (if directory-p
                  (file-directory-p candidate)
                (file-regular-p candidate))
          (throw 'found candidate))))))

(defun p3/windows-path-key (path)
  "Return PATH normalized for case-insensitive Windows comparisons."
  (when (stringp path)
    (downcase
     (directory-file-name
      (replace-regexp-in-string "\\\\" "/" path)))))

(defun p3/windows-path-within-p (path directory)
  "Return non-nil when absolute Windows PATH is DIRECTORY or lies below it."
  (when (and (stringp path)
             (or (file-name-absolute-p path)
                 (string-match-p "\\`[[:alpha:]]:[/\\\\]" path))
             (stringp directory))
    (let* ((path-key (p3/windows-path-key path))
           (directory-key (p3/windows-path-key directory))
           (prefix (concat directory-key "/")))
      (or (equal path-key directory-key)
          (string-prefix-p prefix path-key)))))

(defun p3/windows-path-remove (directory)
  "Remove DIRECTORY from `exec-path' and the child-process PATH."
  (when directory
    (let* ((target (p3/windows-path-key directory))
           (same-p (lambda (entry)
                     (equal (p3/windows-path-key entry) target)))
           (paths (split-string (or (getenv "PATH") "")
                                (regexp-quote path-separator) t)))
      (setq exec-path (seq-remove same-p exec-path))
      (setenv "PATH"
              (mapconcat #'identity
                         (seq-remove same-p paths)
                         path-separator)))))

(defun p3/windows-path-prepend (directory)
  "Prepend DIRECTORY to both `exec-path' and child-process PATH."
  (let* ((directory (file-name-as-directory (expand-file-name directory)))
         (path-directory (directory-file-name directory))
         (separator path-separator)
         (paths (split-string (or (getenv "PATH") "")
                              (regexp-quote separator) t)))
    (setq exec-path (cons directory (delete directory exec-path)))
    (unless (member path-directory paths)
      (setenv "PATH"
              (mapconcat #'identity
                         (cons path-directory paths)
                         separator)))))

(defun p3/windows-clear-rtools-configuration ()
  "Clear state previously derived from the selected Rtools installation."
  (let ((old-bin linuxy-environment-path))
    (when old-bin
      (p3/windows-path-remove old-bin)
      (when (p3/windows-path-within-p shell-file-name old-bin)
        (setq shell-file-name (or (getenv "COMSPEC") "cmdproxy.exe")))
      (when (and (boundp 'explicit-shell-file-name)
                 (p3/windows-path-within-p explicit-shell-file-name old-bin))
        (setq explicit-shell-file-name nil))
      (when (p3/windows-path-within-p (getenv "SHELL") old-bin)
        (setenv "SHELL" nil))
      (when (boundp 'explicit-bash.exe-args)
        (setq explicit-bash.exe-args nil))))
  (setq rtools-path nil
        linuxy-environment-path nil
        mingw64-path nil
        p3/windows-hunspell-program nil
        p3/windows-hunspell-dictionary-directory nil))

(defun p3/windows-select-rtools ()
  "Return the configured or newest usable Rtools installation.
Cache the result, including absence, for the current Emacs session.  Changing
the override invalidates the cached selection automatically."
  (let ((override (and p3/windows-rtools-override
                       (expand-file-name p3/windows-rtools-override))))
    (if (and (consp p3/windows-rtools-selection-cache)
             (equal (car p3/windows-rtools-selection-cache) override))
        (cadr p3/windows-rtools-selection-cache)
      (let ((result
             (cond
              ((and override (p3/windows-rtools-usable-p override)) override)
              (override
               (display-warning
                'p3/windows
                (format "Ignoring unusable Rtools override: %s" override)
                :warning)
               (p3/windows-latest-rtools))
              (t (p3/windows-latest-rtools)))))
        (setq p3/windows-rtools-selection-cache (list override result))
        result))))

(defun p3/windows-configure-rtools ()
  "Discover Rtools and expose its MSYS2 tools to Emacs on Windows."
  (when (p3/windows-p)
    (p3/windows-clear-rtools-configuration)
    (if-let ((selected (p3/windows-select-rtools)))
        (progn
          (setq rtools-path (directory-file-name selected)
                linuxy-environment-path
                (file-name-as-directory (expand-file-name "usr/bin" selected))
                mingw64-path
                (let ((toolchain
                       (p3/windows-rtools-first-existing
                        selected
                        '("x86_64-w64-mingw32.static.posix/bin"
                          "mingw64/bin"
                          "ucrt64/bin")
                        t)))
                  (and toolchain (file-name-as-directory toolchain)))
                p3/windows-hunspell-program
                (p3/windows-rtools-first-existing
                 selected
                 '("usr/bin/hunspell.exe"
                   "x86_64-w64-mingw32.static.posix/bin/hunspell.exe"
                   "mingw64/bin/hunspell.exe"
                   "ucrt64/bin/hunspell.exe")
                 nil)
                p3/windows-hunspell-dictionary-directory
                (p3/windows-rtools-first-existing
                 selected
                 '("usr/share/hunspell"
                   "x86_64-w64-mingw32.static.posix/share/hunspell"
                   "mingw64/share/hunspell"
                   "ucrt64/share/hunspell")
                 t))
          (p3/windows-path-prepend linuxy-environment-path)
          (message "Using Rtools/MSYS2 environment: %s" rtools-path))
      (display-warning
       'p3/windows
       "No usable C:/rtoolsNN installation with usr/bin/bash.exe found"
       :warning))))

(defun p3/windows-shell-mode-setup ()
  "Configure Comint for an Rtools/MSYS2 shell on Windows."
  (add-hook 'comint-output-filter-functions #'comint-strip-ctrl-m nil t)
  (when-let ((process (get-buffer-process (current-buffer))))
    (set-process-coding-system process 'utf-8-unix 'utf-8-unix)))

(defun p3/windows-configure-shell ()
  "Configure the regular Emacs shell from the selected Rtools environment."
  (when (p3/windows-p)
    (if (not linuxy-environment-path)
        (display-warning
         'p3/windows
         "Rtools/MSYS2 is unavailable; leaving the default Emacs shell unchanged"
         :warning)
      (let ((bash (expand-file-name "bash.exe" linuxy-environment-path))
            (zsh (expand-file-name "zsh.exe" linuxy-environment-path)))
        (setq shell-file-name (if (file-regular-p bash) bash "bash")
              explicit-shell-file-name
              (cond
               ((file-regular-p zsh) zsh)
               ((file-regular-p bash) bash)
               (t shell-file-name))
              explicit-bash.exe-args '("--login"))
        (setenv "SHELL" shell-file-name)
        (add-hook 'shell-mode-hook #'p3/windows-shell-mode-setup)))))

(defun p3/windows-r-version (directory)
  "Return the version string encoded by an R installation DIRECTORY."
  (let ((name (file-name-nondirectory (directory-file-name directory))))
    (when (string-match "\\`R-\\(.+\\)\\'" name)
      (match-string 1 name))))

(defun p3/windows-r-program-in-directory (directory)
  "Return Rterm.exe below DIRECTORY, or nil."
  (catch 'found
    (dolist (relative '("bin/Rterm.exe" "bin/x64/Rterm.exe"))
      (let ((candidate (expand-file-name relative directory)))
        (when (file-regular-p candidate)
          (throw 'found candidate))))))

(defun p3/windows-latest-r-program ()
  "Return Rterm.exe from the newest installed R on Windows."
  (let ((root "C:/Program Files/R"))
    (when (and (p3/windows-p)
               (file-directory-p root))
      (catch 'found
        (dolist
            (directory
             (sort
              (seq-filter
               (lambda (directory)
                 (and (file-directory-p directory)
                      (p3/windows-r-version directory)))
               (directory-files root t "\\`R-[0-9]" t))
              (lambda (a b)
                (version< (p3/windows-r-version b)
                          (p3/windows-r-version a)))))
          (when-let ((program (p3/windows-r-program-in-directory directory)))
            (throw 'found program)))))))

(defun p3/windows-select-r-program ()
  "Return the configured or newest installed Rterm.exe.
Cache the result, including absence, for the current Emacs session.  Changing
the override invalidates the cached selection automatically."
  (let ((override (and p3/windows-r-program-override
                       (expand-file-name p3/windows-r-program-override))))
    (if (and (consp p3/windows-r-program-selection-cache)
             (equal (car p3/windows-r-program-selection-cache) override))
        (cadr p3/windows-r-program-selection-cache)
      (let ((result
             (if (and override (file-regular-p override))
                 override
               (p3/windows-latest-r-program))))
        (setq p3/windows-r-program-selection-cache (list override result))
        result))))

(defun p3/r-program ()
  "Return the R executable shared by ESS and editor tooling.

On Windows, delegate to the existing override/discovery authority instead of
consulting PATH.  Elsewhere, honor the active `inferior-R-program-name' when it
resolves and otherwise use the R executable available on PATH."
  (if (p3/windows-p)
      (p3/windows-select-r-program)
    (let ((configured
           (and (boundp 'inferior-R-program-name)
                inferior-R-program-name)))
      (or
       (and (stringp configured)
            (if (file-name-absolute-p configured)
                (and (file-executable-p configured)
                     (expand-file-name configured))
              (executable-find configured)))
       (executable-find "R")))))

(defun p3/windows-configure-r-program ()
  "Configure ESS to use the selected Windows R executable."
  (when (p3/windows-p)
    (setq-default inferior-R-program-name nil)
    (if-let ((program (p3/r-program)))
        (setq-default inferior-R-program-name program)
      (display-warning
       'p3/windows
       "No Rterm.exe found under C:/Program Files/R"
       :warning))))

;;;###autoload
(defun p3/windows-refresh-tool-discovery ()
  "Clear cached Windows tool discovery and reapply platform configuration."
  (interactive)
  (setq p3/windows-rtools-selection-cache :uninitialized
        p3/windows-r-program-selection-cache :uninitialized)
  (when (p3/windows-p)
    (p3/windows-configure-rtools)
    (p3/windows-configure-r-program)
    (p3/windows-configure-shell))
  (message "Windows R/Rtools discovery refreshed"))

(provide 'p3-platform)

;;; p3-platform.el ends here
