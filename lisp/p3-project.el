;;; p3-project.el --- Shared project identity for the personal Emacs config -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'project)
(require 'tab-bar)

(declare-function consult-project-buffer "consult" ())
(defvar compile-command)

(unless (boundp 'project-vc-extra-root-markers)
  (error "P3 project support requires Emacs 29 or newer"))

(dolist (marker '(".projectile" "*.Rproj"))
  (add-to-list 'project-vc-extra-root-markers marker))

(defconst p3/project-general-tab-name "General"
  "Name of the shared workspace for local files outside projects.")

(defvar p3/project--buffer-preview-active nil
  "Non-nil while Consult is previewing buffer candidates.")

(defvar p3/project--buffer-preview-window-configuration nil
  "Window configuration saved before a guarded Consult buffer preview.")

(defvar p3/project--visit-root :unresolved
  "Dynamically scoped project root resolved by displayed file routing.
The value nil means routing already established that the visited file has no
local project; `:unresolved' means normal `project.el' discovery is required.")

(defun p3/project-root ()
  "Return the current built-in `project.el' root, if any.
During a routed displayed file visit, reuse the root already resolved for the
workspace decision instead of asking `project.el' to discover it again."
  (if (eq p3/project--visit-root :unresolved)
      (when-let ((project (project-current nil)))
        (project-root project))
    p3/project--visit-root))

(defun p3/project-normalize-root (root)
  "Return ROOT as the canonical local project workspace identity.
Return nil when ROOT does not name an existing directory."
  (when (and root (file-directory-p root))
    (file-name-as-directory
     (file-truename (expand-file-name root)))))

(defun p3/project-compilation-buffer-name (mode)
  "Return a stable, collision-resistant project buffer name for MODE."
  (let* ((root (or (p3/project-normalize-root default-directory)
                   (file-name-as-directory
                    (expand-file-name default-directory))))
         (name (file-name-nondirectory (directory-file-name root)))
         (suffix (substring (secure-hash 'sha1 root) 0 6)))
    (format "*%s-%s:%s*" name (downcase mode) suffix)))

(defun p3/project--root-compile-command (root fallback)
  "Return ROOT's directory-local `compile-command', or FALLBACK."
  (with-temp-buffer
    (setq default-directory root)
    (hack-dir-local-variables-non-file-buffer)
    (if (local-variable-p 'compile-command)
        compile-command
      fallback)))

(defun p3/project-compile ()
  "Run the current project's repository-level check from its root.

Resolve a project-level `compile-command' from directory-local variables even
when invoked from a non-file project buffer, then delegate execution, prompting,
error navigation, cancellation, and recompile behavior to `project-compile'."
  (interactive)
  (require 'compile)
  (let* ((project (project-current nil))
         (root (and project
                    (p3/project-normalize-root (project-root project)))))
    (unless root
      (user-error "Selected project root is unavailable"))
    (let ((project-current-directory-override root)
          (compile-command
           (p3/project--root-compile-command
            root (default-value 'compile-command))))
      (call-interactively #'project-compile))))

(defun p3/project--tab-root (tab)
  "Return the normalized project root recorded in TAB, if any."
  (alist-get 'p3-project-root (cdr tab)))

(defun p3/project--general-tab-p (tab)
  "Return non-nil when TAB is the shared General workspace."
  (alist-get 'p3-general-workspace (cdr tab)))

(defun p3/project--set-tab-root (tab root)
  "Record ROOT as TAB's runtime project identity."
  (setcdr tab
          (cons (cons 'p3-project-root root)
                (assq-delete-all
                 'p3-general-workspace
                 (assq-delete-all 'p3-project-root (cdr tab)))))
  tab)

(defun p3/project--set-general-tab (tab)
  "Record TAB as the shared General workspace."
  (setcdr tab
          (cons (cons 'p3-general-workspace t)
                (assq-delete-all
                 'p3-project-root
                 (assq-delete-all 'p3-general-workspace (cdr tab)))))
  tab)

(defun p3/project--clear-tab-root (tab)
  "Remove P3 project identity metadata from TAB."
  (setcdr tab (assq-delete-all 'p3-project-root (cdr tab)))
  tab)

(defun p3/project--matching-tab (root)
  "Return the canonical (INDEX . TAB) entry for ROOT in the selected frame.
If duplicate tabs claim ROOT, keep a current matching tab when possible,
otherwise keep the first match.  Other matching tabs remain intact but lose
only their P3 project metadata."
  (let ((tabs (tab-bar-tabs))
        (matches nil)
        (index 0))
    (dolist (tab tabs)
      (setq index (1+ index))
      (when (equal (p3/project--tab-root tab) root)
        (push (cons index tab) matches)))
    (setq matches (nreverse matches))
    (when matches
      (let ((canonical
             (or (cl-find-if (lambda (entry)
                               (eq (car (cdr entry)) 'current-tab))
                             matches)
                 (car matches))))
        (dolist (entry matches)
          (unless (eq entry canonical)
            (p3/project--clear-tab-root (cdr entry))))
        (tab-bar-tabs-set tabs)
        canonical))))

(defun p3/project--find-tab (predicate)
  "Return the first (INDEX . TAB) entry satisfying PREDICATE."
  (let ((index 0))
    (cl-loop for tab in (tab-bar-tabs)
             do (setq index (1+ index))
             when (funcall predicate tab)
             return (cons index tab))))

(defun p3/project-switch-to-tab (root)
  "Select or create the native project tab for ROOT in the selected frame.
Return ROOT's normalized identity.  Reusing a tab leaves its saved window
configuration untouched."
  (let ((normalized (p3/project-normalize-root root)))
    (unless normalized
      (user-error "Project root does not exist: %s" root))
    (if-let ((match (p3/project--matching-tab normalized)))
        (unless (eq (car (cdr match)) 'current-tab)
          (tab-bar-select-tab (car match)))
      (let ((tab-bar-new-tab-choice normalized))
        (tab-new))
      (let* ((tabs (tab-bar-tabs))
             (current (cl-find-if (lambda (tab)
                                    (eq (car tab) 'current-tab))
                                  tabs)))
        (p3/project--set-tab-root current normalized)
        (tab-bar-tabs-set tabs))
      (tab-rename
       (file-name-nondirectory (directory-file-name normalized))))
    normalized))

(defun p3/project-switch-to-general-tab ()
  "Select or establish the shared General workspace in the selected frame."
  (let ((match (p3/project--find-tab #'p3/project--general-tab-p)))
    (unless match
      (setq match
            (p3/project--find-tab
             (lambda (tab)
               (and (not (p3/project--tab-root tab))
                    (not (p3/project--general-tab-p tab))
                    (not (alist-get 'explicit-name (cdr tab))))))))
    (if match
        (unless (eq (car (cdr match)) 'current-tab)
          (tab-bar-select-tab (car match)))
      (tab-new))
    (let* ((tabs (tab-bar-tabs))
           (current (cl-find-if (lambda (tab)
                                  (eq (car tab) 'current-tab))
                                tabs)))
      (unless (p3/project--general-tab-p current)
        (p3/project--set-general-tab current)
        (tab-bar-tabs-set tabs)
        (tab-rename p3/project-general-tab-name)))
    p3/project-general-tab-name))

(defun p3/project-route-file (filename &rest _)
  "Route local FILENAME to its project tab or the shared General tab.
Return the normalized routed project root, or nil for General/remote files.
Extra arguments are ignored so callers may use this as the routing primitive."
  (when filename
    (let ((file (expand-file-name filename)))
      (unless (file-remote-p file)
        (if-let ((project
                  (project-current nil (file-name-directory file))))
            (p3/project-switch-to-tab (project-root project))
          (p3/project-switch-to-general-tab)
          nil)))))

(defun p3/project-with-file-routing (function filename &rest args)
  "Route FILENAME once, then call FUNCTION with the resolved file and ARGS.
Resolve relative filenames before workspace switching so routing cannot change
the target.  Local project identity remains dynamically available to downstream
hooks; remote visits retain normal `project.el' discovery semantics."
  (let* ((file (and filename (expand-file-name filename)))
         (remote (and file (file-remote-p file)))
         (routed-root (p3/project-route-file file))
         (p3/project--visit-root
          (if (or (null file) remote) :unresolved routed-root)))
    (apply function file args)))

(defun p3/project--restore-buffer-preview-window-configuration ()
  "Restore the workspace layout saved before Consult buffer preview."
  (when p3/project--buffer-preview-window-configuration
    (let ((configuration p3/project--buffer-preview-window-configuration))
      (setq p3/project--buffer-preview-window-configuration nil)
      (set-window-configuration configuration))))

(defun p3/project-with-buffer-preview-guard (function &rest args)
  "Run FUNCTION with ARGS while preserving the pre-preview window layout."
  (let ((p3/project--buffer-preview-active t)
        (p3/project--buffer-preview-window-configuration
         (current-window-configuration)))
    (apply function args)))

(defun p3/project-route-buffer (buffer-or-name &optional norecord &rest _)
  "Route a displayed BUFFER-OR-NAME to its project workspace.
Consult preview switches use NORECORD and stay in the current workspace.
Before an accepted switch, restore the pre-preview window configuration so
temporary preview windows and buffers do not leak into the origin workspace.
Non-file buffers stay in the current workspace."
  (if norecord
      ;; The guard normally snapshots before preview begins.  Capture lazily as
      ;; well so direct guarded calls retain the same invariant.
      (when (and p3/project--buffer-preview-active
                 (not p3/project--buffer-preview-window-configuration))
        (setq p3/project--buffer-preview-window-configuration
              (current-window-configuration)))
    (when p3/project--buffer-preview-active
      (p3/project--restore-buffer-preview-window-configuration))
    (when-let* ((buffer (and buffer-or-name (get-buffer buffer-or-name)))
                (file (buffer-local-value 'buffer-file-name buffer)))
      (p3/project-route-file file))))

(defun p3/project-resume ()
  "Resume the selected native project workspace and choose a project buffer."
  (interactive)
  (let* ((project (project-current t))
         (root (and project
                    (p3/project-normalize-root (project-root project)))))
    (unless root
      (user-error "Selected project root is unavailable"))
    (p3/project-switch-to-tab root)
    (let ((project-current-directory-override root))
      (call-interactively #'consult-project-buffer))))

(defun p3/use-project-root-as-default-dir ()
  "Use the current project root as the buffer's default directory."
  (when-let ((root (p3/project-root)))
    (setq-local default-directory root)))

(provide 'p3-project)

;;; p3-project.el ends here
