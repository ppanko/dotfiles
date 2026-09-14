;;; p3-r-tools-test.el --- Tests for p3-r-tools -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-r-test--config-directory
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path
             (expand-file-name "lisp" p3-r-test--config-directory))

(require 'p3-r-tools)

(setq p3-r-template-directory
      (expand-file-name "templates/r" p3-r-test--config-directory))

(load (expand-file-name "test/p3-r-portability-test.el"
                        p3-r-test--config-directory))

(defmacro p3-r-test--with-temp-directory (binding &rest body)
  "Bind BINDING to a temporary directory while evaluating BODY."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,binding (make-temp-file "p3-r-tools-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,binding t))))

(defun p3-r-test--contents (path)
  "Return the contents of PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(ert-deftest p3-r-render-template-replaces-placeholders ()
  (let ((rendered
         (p3-r-render-template
          "script.R.tmpl"
          '((title . "Example")
            (author . "Ada Lovelace")
            (date . "01/01/2000")))))
    (should (string-match-p "title:  'Example'" rendered))
    (should (string-match-p "author: 'Ada Lovelace'" rendered))
    (should-not (string-match-p "{{" rendered))))

(ert-deftest p3-r-render-template-rejects-missing-values ()
  (should-error
   (p3-r-render-template "script.R.tmpl" '((title . "Incomplete")))
   :type 'user-error))

(ert-deftest p3-r-insertion-commands-use-shared-templates ()
  (let ((p3-r-author "Grace Hopper"))
    (with-temp-buffer
      (p3-r-insert-script-header "Model fit")
      (should (string-match-p "title:  'Model fit'" (buffer-string)))
      (should (string-match-p "author: 'Grace Hopper'" (buffer-string)))
      (should-not (string-match-p "{{" (buffer-string))))
    (with-temp-buffer
      (p3-r-insert-word-report-header)
      (should (string-match-p "officedown::rdocx_document" (buffer-string)))
      (should (string-match-p "author: 'Grace Hopper'" (buffer-string))))
    (with-temp-buffer
      (p3-r-insert-chunk "diagnostics")
      (should (equal (buffer-string)
                     "```{r diagnostics}\n\n```\n")))))

(ert-deftest p3-r-new-analysis-project-generates-expected-files ()
  (p3-r-test--with-temp-directory parent
    (let ((root (expand-file-name "analysis-demo" parent)))
      (p3-r-new-project root 'analysis)
      (should (file-exists-p (expand-file-name "analysis-demo.Rproj" root)))
      (should-not (file-exists-p (expand-file-name ".projectile" root)))
      (should (file-exists-p (expand-file-name "R/01_prepareData.R" root)))
      (should (file-exists-p (expand-file-name "R/utils.R" root)))
      (should-not (file-exists-p (expand-file-name "R/packages.R" root)))
      (should-not (file-exists-p (expand-file-name "_targets.R" root)))
      (should-not (file-exists-p (expand-file-name "bootstrap.R" root)))
      (should
       (string-match-p
        "Preprocess data"
        (p3-r-test--contents (expand-file-name "R/01_prepareData.R" root)))))))

(ert-deftest p3-r-new-targets-project-generates-portable-pipeline ()
  (p3-r-test--with-temp-directory parent
    (let* ((root (expand-file-name "targets-demo" parent))
           (p3-r-target-workers 4))
      (p3-r-new-project root 'targets)
      (let ((targets (p3-r-test--contents (expand-file-name "_targets.R" root)))
            (packages (p3-r-test--contents (expand-file-name "R/packages.R" root)))
            (utils (p3-r-test--contents (expand-file-name "R/utils.R" root)))
            (bootstrap (p3-r-test--contents (expand-file-name "bootstrap.R" root))))
        (should (string-match-p "library(targets)" targets))
        (should (string-match-p "library(tarchetypes)" targets))
        (should (string-match-p "crew::crew_controller_local(workers = 4)" targets))
        (should (string-match-p
                 "source(here::here(\"R\", \"packages.R\"))" targets))
        (should (string-match-p
                 "source(here::here(\"R\", \"utils.R\"))" targets))
        (should (string-match-p "here::here(\"R\")" utils))
        (should (string-match-p "pipelinePackages <-" packages))
        (should (string-match-p "targetPackages <-" packages))
        (should (string-match-p "bootstrapPackages <-" packages))
        (should-not (string-match-p "targetPackages <-" utils))
        (should (string-match-p "packages[[:space:]]*=[[:space:]]*targetPackages" targets))
        (should (string-match-p
                 (regexp-quote
                  "c(targets_01_prepareData, targets_02_computeResults)")
                 targets))
        (should-not (string-match-p "exists(\"targets_01_prepareData\"" targets))
        (should-not (string-match-p "exists(\"targets_02_computeResults\"" targets))
        (should (string-match-p
                 (regexp-quote "targets::tar_renv(extras = character())")
                 targets))
        (dolist (pipeline-only '("here" "pkgload" "devtools" "crew.cluster"))
          (should-not
           (string-match-p (regexp-quote (format "\"%s\"" pipeline-only))
                           targets)))
        (should-not (string-match-p "installLoadPackages" utils))
        (should-not (string-match-p "renv::" targets))
        (should-not (string-match-p "renv::" packages))
        (should-not (string-match-p "renv::" utils))
        (should-not (string-match-p "install.packages" targets))
        (should-not (string-match-p "install.packages" packages))
        (should-not (string-match-p "install.packages" utils))
        (should (string-match-p "install.packages.*renv" bootstrap))
        (should-not (string-match-p
                     (regexp-quote "https://community.r-multiverse.org") bootstrap))
        (should (string-match-p
                 (regexp-quote "https://cloud.r-project.org") bootstrap))
        (should-not (string-match-p "NOT_CRAN" bootstrap))
        (should (string-match-p "renv::init(" bootstrap))
        (should (string-match-p "renv::install" bootstrap))
        (should (string-match-p
                 (regexp-quote "source(file.path(\"R\", \"packages.R\"))")
                 bootstrap))
        (should-not (string-match-p
                     (regexp-quote "source(file.path(\"R\", \"utils.R\"))")
                     bootstrap))
        (should-not (string-match-p "targetPackages <-" bootstrap))
        (should (string-match-p "discoveryScript <- tempfile" bootstrap))
        (should (string-match-p
                 (regexp-quote "script = discoveryScript") bootstrap))
        (let ((tar-renv
               (string-match
                (regexp-quote "targets::tar_renv(") bootstrap))
              (snapshot
               (string-match
                (regexp-quote
                 "renv::snapshot(repos = projectRepos, prompt = FALSE)")
                bootstrap)))
          (should tar-renv)
          (should snapshot)
          (should (< tar-renv snapshot)))
        (should-not (string-match-p
                     (regexp-quote "targets::tar_renv()") bootstrap))
        (let ((load (string-match "renv::load(project = getwd())" bootstrap))
              (restore (string-match
                        "renv::restore(project = getwd(), prompt = FALSE)"
                        bootstrap)))
          (should load)
          (should restore)
          (should (< load restore)))
        (should-not (string-match-p "snapshot(type = .*all" bootstrap))
        (should (string-match-p "\"targets\"" packages))
        (should (string-match-p "\"here\"" packages))
        (should (string-match-p "\"dplyr\"" packages))
        (should-not (string-match-p "\"tidypolars\"" targets))
        (should-not (string-match-p "\"tidypolars\"" packages))
        (should-not (string-match-p "\"tidypolars\"" bootstrap))
        (should-not (string-match-p "{{" targets))
        (should-not (string-match-p "{{" packages))
        (should-not (string-match-p "{{" utils))
        (should-not (string-match-p "{{" bootstrap))))))

(ert-deftest p3-r-bootstrap-project-runs-portable-project-bootstrap-asynchronously ()
  (p3-r-test--with-temp-directory root
    (with-temp-file (expand-file-name "bootstrap.R" root)
      (insert "message('bootstrap')\n"))
    (let (called-command called-directory process-root displayed)
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () (file-name-as-directory root)))
                ((symbol-function 'p3/r-program)
                 (lambda () "/opt/R/bin/R"))
                ((symbol-function 'make-process)
                 (lambda (&rest plist)
                   (setq called-command (plist-get plist :command)
                         called-directory default-directory)
                   'fake-process))
                ((symbol-function 'process-put)
                 (lambda (_process key value)
                   (when (eq key 'p3-r-root)
                     (setq process-root value))))
                ((symbol-function 'display-buffer)
                 (lambda (buffer &rest _)
                   (setq displayed buffer))))
        (let ((p3-r--project-process nil))
          (should (eq (p3-r-bootstrap-project) 'fake-process)))
        (should (equal called-directory (file-name-as-directory root)))
        (should (equal (car called-command) "/opt/R/bin/R"))
        (should (member "--vanilla" called-command))
        (should (equal (car (last called-command))
                       "source(\"bootstrap.R\", chdir = TRUE)"))
        (should (equal process-root (file-name-as-directory root)))
        (should (bufferp displayed))))))

(ert-deftest p3-r-bootstrap-project-restores-older-lockfile-asynchronously ()
  (p3-r-test--with-temp-directory root
    (with-temp-file (expand-file-name "renv.lock" root)
      (insert "{}\n"))
    (let (called-command)
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () (file-name-as-directory root)))
                ((symbol-function 'p3/r-program)
                 (lambda () "/opt/R/bin/R"))
                ((symbol-function 'make-process)
                 (lambda (&rest plist)
                   (setq called-command (plist-get plist :command))
                   'fake-process))
                ((symbol-function 'process-put) (lambda (&rest _) nil))
                ((symbol-function 'display-buffer) (lambda (&rest _) nil)))
        (let ((p3-r--project-process nil))
          (p3-r-bootstrap-project))
        (should
         (equal (car (last called-command))
                (concat "renv::load(project = getwd()); "
                        "renv::restore(project = getwd(), prompt = FALSE)")))))))

(ert-deftest p3-r-bootstrap-project-rejects-overlapping-setup ()
  (cl-letf (((symbol-function 'process-live-p) (lambda (_process) t)))
    (let ((p3-r--project-process 'existing-process))
      (should-error
       (p3-r--run-project-r "/tmp/project" "1 + 1" t)
       :type 'user-error))))

(ert-deftest p3-r-bootstrap-project-does-not-initialize-plain-analysis-profile ()
  (p3-r-test--with-temp-directory root
    (let (called)
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () (file-name-as-directory root)))
                ((symbol-function 'p3/r-program)
                 (lambda () "/opt/R/bin/R"))
                ((symbol-function 'make-process)
                 (lambda (&rest _)
                   (setq called t)
                   'fake-process)))
        (let ((p3-r--project-process nil))
          (should-error (p3-r-bootstrap-project) :type 'user-error))
        (should-not called)))))

(ert-deftest p3-r-ess-config-does-not-force-rmarkdown-crlf ()
  (let ((contents
         (p3-r-test--contents
          (expand-file-name "lisp/p3-config-ess.el"
                            p3-r-test--config-directory))))
    (should-not (string-match-p "utf-8-dos" contents))))

(ert-deftest p3-r-generated-files-parse-with-r ()
  (skip-unless (executable-find "Rscript"))
  (p3-r-test--with-temp-directory parent
    (let ((root (expand-file-name "parse-demo" parent)))
      (p3-r-new-project root 'targets)
      (dolist (file (directory-files-recursively root "\\.R\\'"))
        (with-temp-buffer
          (let ((status
                 (call-process
                  "Rscript" nil (current-buffer) nil
                  "-e" (format "parse(file=%S)" file))))
            (unless (zerop status)
              (ert-fail
               (format "R failed to parse %s:\n%s" file (buffer-string))))))))))

(ert-deftest p3-r-fresh-target-list-remains-strict-with-r ()
  (skip-unless (executable-find "Rscript"))
  (p3-r-test--with-temp-directory parent
    (let* ((root (expand-file-name "fresh-demo" parent))
           (targets-file (expand-file-name "_targets.R" root)))
      (p3-r-new-project root 'targets)
      (with-temp-buffer
        (let ((status
               (call-process
                "Rscript" nil (current-buffer) nil
                "-e"
                (format
                 (concat
                  "exprs <- parse(file=%S); "
                  "eval(exprs[[length(exprs)]], "
                  "envir = new.env(parent = baseenv()))")
                 targets-file))))
          (should-not (zerop status)))))))

(ert-deftest p3-r-new-project-refuses-to-overwrite ()
  (p3-r-test--with-temp-directory parent
    (let* ((root (expand-file-name "safe-demo" parent))
           (script (expand-file-name "R/01_prepareData.R" root)))
      (p3-r-new-project root 'analysis)
      (with-temp-file script
        (insert "user content\n"))
      (should-error (p3-r-new-project root 'analysis) :type 'user-error)
      (should (equal (p3-r-test--contents script) "user content\n"))
      (p3-r-new-project root 'analysis t)
      (should-not (equal (p3-r-test--contents script) "user content\n")))))

(ert-deftest p3-r-load-view-data-frame-uses-shared-ess-runner ()
  (let (sent-code)
    (cl-letf (((symbol-function 'p3-r--read-template)
               (lambda (name)
                 (should (equal name "view-df.R"))
                 "view_df <- function(x) x"))
              ((symbol-function 'p3-r-ess-run)
               (lambda (code)
                 (setq sent-code code)))
              ((symbol-function 'ess-get-process)
               (lambda (&optional _name) 'fake-process)))
      (p3-r-load-view-data-frame)
      (should (equal sent-code "view_df <- function(x) x")))))

(ert-deftest p3-r-open-helper-file-uses-shared-project-root ()
  (p3-r-test--with-temp-directory root
    (let* ((helper (expand-file-name "R/utils.R" root))
           opened)
      (make-directory (file-name-directory helper) t)
      (with-temp-file helper)
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () (file-name-as-directory root)))
                ((symbol-function 'find-file)
                 (lambda (path) (setq opened path))))
        (p3-r-open-helper-file)
        (should (equal opened helper))))))

(ert-deftest p3-r-command-map-exposes-workflow ()
  (dolist (key '("p" "b" "h" "w" "c" "s" "a" "m" "d" "l" "v" "r" "f"))
    (should (commandp (keymap-lookup p3-r-command-map key)))))

(ert-deftest p3-r-tools-does-not-retain-projectile-helper-alias ()
  (should-not (fboundp 'p3/projectile-open-r-helper-functions-file)))

(provide 'p3-r-tools-test)

;;; p3-r-tools-test.el ends here
