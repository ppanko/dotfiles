;;; p3-r-portability-test.el --- R portability regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'p3-r-tools)

(defconst p3-r-portability-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(load (expand-file-name "test/p3-r-alignment-test.el"
                        p3-r-portability-test--root))

(defun p3-r-portability-test--template (name)
  "Return generated R template NAME as text."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name (concat "templates/r/" name)
                       p3-r-portability-test--root))
    (buffer-string)))

(ert-deftest p3-r-default-target-packages-stay-cran-portable ()
  (should-not (member "tidypolars" p3-r-target-runtime-packages)))

(ert-deftest p3-r-bootstrap-has-no-optional-polars-repository-policy ()
  (let ((bootstrap (p3-r-portability-test--template "bootstrap.R.tmpl")))
    (should-not (string-match-p "r-multiverse" bootstrap))
    (should-not (string-match-p "NOT_CRAN" bootstrap))
    (should (string-match-p "https://cloud.r-project.org" bootstrap))))

(ert-deftest p3-r-fresh-bootstrap-cleans-provisional-lockfile-on-failure ()
  (let* ((bootstrap (p3-r-portability-test--template "bootstrap.R.tmpl"))
         (activate
          (string-match
           (regexp-quote "file.path(\"renv\", \"activate.R\")")
           bootstrap))
         (cleanup (string-match
                   (regexp-quote "unlink(\"renv.lock\")") bootstrap))
         (install (string-match "renv::install" bootstrap)))
    (should activate)
    (should cleanup)
    (should install)
    (should (< activate cleanup))
    (should (< cleanup install))
    (should (string-match-p "error[[:space:]]*=[[:space:]]*function" bootstrap))))

(ert-deftest p3-r-generated-project-has-one-package-declaration-owner ()
  (let ((packages (p3-r-portability-test--template "targets-packages.R.tmpl"))
        (utils (p3-r-portability-test--template "targets-utils.R.tmpl"))
        (targets (p3-r-portability-test--template "targets.R.tmpl"))
        (bootstrap (p3-r-portability-test--template "bootstrap.R.tmpl")))
    (should (string-match-p
             (regexp-quote "targetPackages <- {{target-packages}}") packages))
    (should (string-match-p "pipelinePackages <-" packages))
    (should (string-match-p "bootstrapPackages <-" packages))
    (should-not (string-match-p "targetPackages <-" utils))
    (should-not (string-match-p "{{target-packages}}" targets))
    (should-not (string-match-p "{{target-packages}}" bootstrap))
    (should (string-match-p
             (regexp-quote "source(here::here(\"R\", \"packages.R\"))")
             targets))
    (should (string-match-p
             (regexp-quote "source(here::here(\"R\", \"utils.R\"))")
             targets))
    (should (string-match-p
             (regexp-quote "source(file.path(\"R\", \"packages.R\"))")
             bootstrap))
    (should-not (string-match-p
                 (regexp-quote "source(file.path(\"R\", \"utils.R\"))")
                 bootstrap))))

(ert-deftest p3-r-bootstrap-snapshot-records-declared-repository ()
  (let ((bootstrap (p3-r-portability-test--template "bootstrap.R.tmpl")))
    (should (string-match-p
             (regexp-quote
              "renv::snapshot(repos = projectRepos, prompt = FALSE)")
             bootstrap))))

(ert-deftest p3-r-generated-gitignore-excludes-targets-store ()
  (let ((gitignore (p3-r-portability-test--template "gitignore.tmpl")))
    (should (string-match-p "^_targets/$" gitignore))))

(provide 'p3-r-portability-test)

;;; p3-r-portability-test.el ends here
