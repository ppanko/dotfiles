;;; p3-r-tidyverse-completion-test.el --- Tidyverse completion tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-r-tidyverse-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-r-tidyverse-test--root))
(require 'p3-r-tidyverse-completion nil t)

(defun p3-r-tidyverse-test--columns (source schemas)
  "Return columns at end of SOURCE using SCHEMAS for live symbols."
  (unless (fboundp 'p3/r-tidyverse-columns-at-point)
    (ert-fail "tidyverse completion provider is not implemented"))
  (with-temp-buffer
    (insert source)
    (goto-char (point-max))
    (cl-letf (((symbol-function 'p3/r-tidyverse--live-columns)
               (lambda (symbol)
                 (cdr (assoc symbol schemas)))))
      (p3/r-tidyverse-columns-at-point))))

(ert-deftest p3-r-tidyverse-completion-api-is-small-and-explicit ()
  (dolist (function '(p3/r-tidyverse-columns-at-point
                      p3/r-tidyverse-completion-at-point
                      p3/r-tidyverse-company-backend
                      p3/r-tidyverse-completion-buffer-setup
                      p3/r-tidyverse-completion-setup))
    (should (fboundp function))))

(ert-deftest p3-r-tidyverse-completes-native-pipe-live-symbol ()
  (should
   (equal
    (p3-r-tidyverse-test--columns
     "spacecraft |> mutate(label = country_"
     '(("spacecraft" . ("id" "country_code" "launch_date"))))
    '("id" "country_code" "launch_date"))))

(ert-deftest p3-r-tidyverse-completes-magrittr-pipe-live-symbol ()
  (should
   (equal
    (p3-r-tidyverse-test--columns
     "spacecraft %>% filter(country_"
     '(("spacecraft" . ("id" "country_code" "launch_date"))))
    '("id" "country_code" "launch_date"))))

(ert-deftest p3-r-tidyverse-completes-direct-call-after-data-argument ()
  (should
   (equal
    (p3-r-tidyverse-test--columns
     "mutate(spacecraft, label = country_"
     '(("spacecraft" . ("id" "country_code" "launch_date"))))
    '("id" "country_code" "launch_date"))))

(ert-deftest p3-r-tidyverse-does-not-complete-direct-data-argument ()
  (let ((queries 0))
    (unless (fboundp 'p3/r-tidyverse-columns-at-point)
      (ert-fail "tidyverse completion provider is not implemented"))
    (with-temp-buffer
      (insert "mutate(spacecraft")
      (goto-char (point-max))
      (cl-letf (((symbol-function 'p3/r-tidyverse--live-columns)
                 (lambda (_symbol)
                   (setq queries (1+ queries))
                   '("id"))))
        (should-not (p3/r-tidyverse-columns-at-point))
        (should (= queries 0))))))

(ert-deftest p3-r-tidyverse-recognizes-common-dplyr-data-contexts ()
  (dolist (verb '("mutate" "transmute" "filter" "select" "rename"
                  "relocate" "arrange" "group_by" "summarise" "summarize"
                  "distinct" "count" "add_count"))
    (should
     (equal
      (p3-r-tidyverse-test--columns
       (format "df |> %s(col" verb)
       '(("df" . ("col" "other"))))
      '("col" "other")))))

(ert-deftest p3-r-tidyverse-carries-safe-schema-transforms-through-pipe ()
  (should
   (equal
    (p3-r-tidyverse-test--columns
     (concat
      "spacecraft |> "
      "filter(country_code == \"US\") |> "
      "select(id, country_code) |> "
      "rename(country = country_code) |> "
      "mutate(label = paste0(country, id)) |> "
      "transmute(id, country, label) |> "
      "arrange(coun")
     '(("spacecraft" . ("id" "country_code" "launch_date"))))
    '("id" "country" "label"))))

(ert-deftest p3-r-tidyverse-parser-preserves-point ()
  (with-temp-buffer
    (insert "mutate(spacecraft, label = country_")
    (goto-char (point-max))
    (let ((origin (point)))
      (cl-letf (((symbol-function 'p3/r-tidyverse--live-columns)
                 (lambda (_symbol)
                   '("id" "country_code" "launch_date"))))
        (should (equal (p3/r-tidyverse-columns-at-point)
                       '("id" "country_code" "launch_date")))
        (should (= (point) origin))))))

(ert-deftest p3-r-tidyverse-refuses-arbitrary-pipeline-evaluation ()
  (let ((queries 0))
    (unless (fboundp 'p3/r-tidyverse-columns-at-point)
      (ert-fail "tidyverse completion provider is not implemented"))
    (with-temp-buffer
      (insert "download_data() |> expensive_transform() |> mutate(col")
      (goto-char (point-max))
      (cl-letf (((symbol-function 'p3/r-tidyverse--live-columns)
                 (lambda (_symbol)
                   (setq queries (1+ queries))
                   '("should_not_appear"))))
        (should-not (p3/r-tidyverse-columns-at-point))
        (should (= queries 0))))))

(ert-deftest p3-r-tidyverse-refuses-arbitrary-direct-data-expression ()
  (let ((queries 0))
    (unless (fboundp 'p3/r-tidyverse-columns-at-point)
      (ert-fail "tidyverse completion provider is not implemented"))
    (with-temp-buffer
      (insert "mutate(download_data(), col")
      (goto-char (point-max))
      (cl-letf (((symbol-function 'p3/r-tidyverse--live-columns)
                 (lambda (_symbol)
                   (setq queries (1+ queries))
                   '("should_not_appear"))))
        (should-not (p3/r-tidyverse-columns-at-point))
        (should (= queries 0))))))

(ert-deftest p3-r-tidyverse-schema-command-accepts-only-simple-symbols ()
  (unless (fboundp 'p3/r-tidyverse--schema-command)
    (ert-fail "tidyverse completion schema query is not implemented"))
  (let ((command (p3/r-tidyverse--schema-command "spacecraft")))
    (should (stringp command))
    (should (string-match-p "get0(\"spacecraft\"" command))
    (should (string-match-p "names" command))
    (should-not (string-match-p "eval" command)))
  (dolist (unsafe '("download_data()" "x$y" "pkg::df" "x[[1]]"))
    (should-not (p3/r-tidyverse--schema-command unsafe))))

(ert-deftest p3-r-tidyverse-live-columns-never-starts-r ()
  (unless (fboundp 'p3/r-tidyverse--live-columns)
    (ert-fail "tidyverse completion live schema lookup is not implemented"))
  (let ((starts 0)
        (queries 0))
    (cl-letf (((symbol-function 'p3/ess-project-process) (lambda () nil))
              ((symbol-function 'p3/ess-ensure-project-process)
               (lambda (&rest _)
                 (setq starts (1+ starts))))
              ((symbol-function 'ess-command)
               (lambda (&rest _)
                 (setq queries (1+ queries)))))
      (should-not (p3/r-tidyverse--live-columns "spacecraft"))
      (should (= starts 0))
      (should (= queries 0)))))

(ert-deftest p3-r-tidyverse-live-columns-skips-busy-process ()
  (unless (fboundp 'p3/r-tidyverse--live-columns)
    (ert-fail "tidyverse completion live schema lookup is not implemented"))
  (let ((queries 0))
    (cl-letf (((symbol-function 'p3/ess-project-process) (lambda () "R:project"))
              ((symbol-function 'get-process) (lambda (_name) 'fake-process))
              ((symbol-function 'process-live-p) (lambda (_proc) t))
              ((symbol-function 'process-get)
               (lambda (_proc property)
                 (eq property 'busy)))
              ((symbol-function 'ess-command)
               (lambda (&rest _)
                 (setq queries (1+ queries)))))
      (should-not (p3/r-tidyverse--live-columns "spacecraft"))
      (should (= queries 0)))))

(ert-deftest p3-r-tidyverse-live-columns-caches-until-new-user-evaluation ()
  (unless (fboundp 'p3/r-tidyverse--live-columns)
    (ert-fail "tidyverse completion live schema lookup is not implemented"))
  (let ((last-eval (seconds-to-time 10))
        (now (seconds-to-time 20))
        (queries 0))
    (with-temp-buffer
      (setq-local p3/r-tidyverse--schema-cache nil)
      (cl-letf (((symbol-function 'p3/ess-project-process) (lambda () "R:project"))
                ((symbol-function 'get-process) (lambda (_name) 'fake-process))
                ((symbol-function 'process-live-p) (lambda (_proc) t))
                ((symbol-function 'process-get)
                 (lambda (_proc property)
                   (pcase property
                     ('busy nil)
                     ('last-eval last-eval))))
                ((symbol-function 'current-time) (lambda () now))
                ((symbol-function 'ess-command)
                 (lambda (_command out-buffer &optional _sleep _no-prompt _wait proc &rest _)
                   (should (eq proc 'fake-process))
                   (setq queries (1+ queries))
                   (with-current-buffer out-buffer
                     (erase-buffer)
                     (insert "id\037country_code\n")))))
        (should (equal (p3/r-tidyverse--live-columns "spacecraft")
                       '("id" "country_code")))
        (should (equal (p3/r-tidyverse--live-columns "spacecraft")
                       '("id" "country_code")))
        (should (= queries 1))
        (setq last-eval (seconds-to-time 30)
              now (seconds-to-time 40))
        (should (equal (p3/r-tidyverse--live-columns "spacecraft")
                       '("id" "country_code")))
        (should (= queries 2))))))

(ert-deftest p3-r-tidyverse-live-columns-uses-bounded-synchronous-query ()
  (let (no-prompt-check timeout)
    (with-temp-buffer
      (cl-letf (((symbol-function 'p3/ess-project-process) (lambda () "R:project"))
                ((symbol-function 'get-process) (lambda (_name) 'fake-process))
                ((symbol-function 'process-live-p) (lambda (_proc) t))
                ((symbol-function 'process-get) (lambda (_proc _property) nil))
                ((symbol-function 'ess-command)
                 (lambda (_command out-buffer &optional _sleep no-prompt _wait proc
                                  _redisplay query-timeout)
                   (should (eq proc 'fake-process))
                   (setq no-prompt-check no-prompt
                         timeout query-timeout)
                   (with-current-buffer out-buffer
                     (insert "id\037country_code\n")))))
        (should (equal (p3/r-tidyverse--live-columns "spacecraft")
                       '("id" "country_code")))
        (should-not no-prompt-check)
        (should (numberp timeout))
        (should (> timeout 0))
        (should (<= timeout 0.1))))))

(ert-deftest p3-r-tidyverse-relocate-propagates-simple-renames ()
  (should
   (equal
    (p3-r-tidyverse-test--columns
     "df |> relocate(country = country_code) |> filter(coun"
     '(("df" . ("id" "country_code" "launch_date"))))
    '("id" "country" "launch_date"))))

(ert-deftest p3-r-tidyverse-group-by-computed-column-stops-propagation ()
  (should-not
   (p3-r-tidyverse-test--columns
    "df |> group_by(group = paste0(country, id)) |> filter(coun"
    '(("df" . ("id" "country" "launch_date"))))))

(ert-deftest p3-r-tidyverse-group-by-simple-column-preserves-safe-chain ()
  (should
   (equal
    (p3-r-tidyverse-test--columns
     "df |> group_by(country) |> filter(coun"
     '(("df" . ("id" "country" "launch_date"))))
    '("id" "country" "launch_date"))))

(ert-deftest p3-r-tidyverse-grouped-schema-stops-before-schema-changing-stage ()
  (should-not
   (p3-r-tidyverse-test--columns
    "df |> group_by(country) |> transmute(label = id) |> filter(lab"
    '(("df" . ("id" "country" "launch_date"))))))

(ert-deftest p3-r-tidyverse-mutate-null-removes-column ()
  (should
   (equal
    (p3-r-tidyverse-test--columns
     "df |> mutate(country = NULL) |> filter(laun"
     '(("df" . ("id" "country" "launch_date"))))
    '("id" "launch_date"))))

(ert-deftest p3-r-tidyverse-transmute-null-does-not-create-column ()
  (should
   (equal
    (p3-r-tidyverse-test--columns
     "df |> transmute(country = NULL, id) |> filter(i"
     '(("df" . ("id" "country" "launch_date"))))
    '("id"))))

(ert-deftest p3-r-tidyverse-capf-is-nonexclusive-and-column-first ()
  (unless (fboundp 'p3/r-tidyverse-completion-at-point)
    (ert-fail "tidyverse completion CAPF is not implemented"))
  (with-temp-buffer
    (insert "spacecraft |> filter(coun")
    (goto-char (point-max))
    (cl-letf (((symbol-function 'p3/r-tidyverse--live-columns)
               (lambda (_symbol)
                 '("id" "country_code" "launch_date"))))
      (let* ((capf (p3/r-tidyverse-completion-at-point))
             (beg (nth 0 capf))
             (end (nth 1 capf))
             (table (nth 2 capf)))
        (should (equal (buffer-substring-no-properties beg end) "coun"))
        (should (equal table '("id" "country_code" "launch_date")))
        (should (eq (plist-get (nthcdr 3 capf) :exclusive) 'no))))))

(ert-deftest p3-r-tidyverse-buffer-setup-merges-company-backend-ahead-of-generic-r ()
  (unless (fboundp 'p3/r-tidyverse-completion-buffer-setup)
    (ert-fail "tidyverse completion buffer setup is not implemented"))
  (with-temp-buffer
    (setq-local company-backends
                '((:separate
                   company-R-library company-R-args company-R-objects
                   company-dabbrev-code :with company-yasnippet)
                  company-capf))
    (setq-local completion-at-point-functions nil)
    (p3/r-tidyverse-completion-buffer-setup)
    (should
     (equal
      (car company-backends)
      '(:separate
        p3/r-tidyverse-company-backend
        company-R-library company-R-args company-R-objects
        company-dabbrev-code :with company-yasnippet)))
    (should (memq #'p3/r-tidyverse-completion-at-point
                  completion-at-point-functions))))

(provide 'p3-r-tidyverse-completion-test)

;;; p3-r-tidyverse-completion-test.el ends here
