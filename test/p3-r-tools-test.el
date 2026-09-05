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
      (should-not (file-exists-p (expand-file-name "_targets.R" root)))
      (should
       (string-match-p
        "Preprocess data"
        (p3-r-test--contents (expand-file-name "R/01_prepareData.R" root)))))))

(ert-deftest p3-r-new-targets-project-generates-pipeline ()
  (p3-r-test--with-temp-directory parent
    (let* ((root (expand-file-name "targets-demo" parent))
           (p3-r-target-workers 4))
      (p3-r-new-project root 'targets)
      (let ((targets (p3-r-test--contents (expand-file-name "_targets.R" root)))
            (utils (p3-r-test--contents (expand-file-name "R/utils.R" root))))
        (should (string-match-p "crew_controller_local(workers = 4)" targets))
        (should (string-match-p
                 "source(here::here(\"R\", \"utils.R\"))" targets))
        (should (string-match-p "installLoadPackages <- function" utils))
        (should-not (string-match-p "{{" targets))))))

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
  (dolist (key '("p" "h" "w" "c" "s" "a" "m" "d" "l" "v" "r" "f"))
    (should (commandp (keymap-lookup p3-r-command-map key)))))

(ert-deftest p3-r-tools-does-not-retain-projectile-helper-alias ()
  (should-not (fboundp 'p3/projectile-open-r-helper-functions-file)))

(provide 'p3-r-tools-test)

;;; p3-r-tools-test.el ends here
