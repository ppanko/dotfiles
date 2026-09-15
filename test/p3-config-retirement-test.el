;;; p3-config-retirement-test.el --- Retired configuration regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-config-retirement-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-config-retirement-test--config ()
  "Return the authoritative literate configuration contents."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "config.org" p3-config-retirement-test--root))
    (buffer-string)))

(ert-deftest p3-config-workgroups2-remains-retired ()
  (let ((contents (p3-config-retirement-test--config)))
    (dolist (forbidden '("(use-package workgroups2"
                          "wg-prefix-key"
                          "wg-session-load-on-start"
                          "(workgroups-mode 1)"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(ert-deftest p3-startup-profile-module-exists ()
  "Phase 2A requires the startup profiler before implementation can pass."
  (should (require 'p3-startup-profile nil t)))

(ert-deftest p3-startup-profile-wrapper-records-elapsed-time-temporary ()
  (require 'p3-startup-profile)
  (let ((p3/startup-profile-active t)
        (p3/startup-profile-phases nil)
        (times '(10.0 10.25)))
    (cl-letf (((symbol-function 'float-time)
               (lambda (&optional _time)
                 (prog1 (car times) (setq times (cdr times))))))
      (should (eq (p3/with-startup-profile-phase "example" 'ok) 'ok)))
    (should (equal p3/startup-profile-phases '(("example" 0.25 1))))))

(ert-deftest p3-startup-profile-records-and-aggregates-temporary ()
  (require 'p3-startup-profile)
  (let ((p3/startup-profile-active t)
        (p3/startup-profile-phases nil))
    (p3/startup-profile-record "ensure" 0.125)
    (p3/startup-profile-record "other" 0.25)
    (p3/startup-profile-record "ensure" 0.375)
    (should (equal p3/startup-profile-phases
                   '(("ensure" 0.5 2) ("other" 0.25 1))))))

(ert-deftest p3-startup-profile-wrapper-skips-clock-after-startup-temporary ()
  (require 'p3-startup-profile)
  (let ((p3/startup-profile-active nil)
        called)
    (cl-letf (((symbol-function 'float-time)
               (lambda (&optional _time) (setq called t) 0.0)))
      (should (eq (p3/with-startup-profile-phase "inactive" 'ok) 'ok)))
    (should-not called)))

(ert-deftest p3-startup-profile-finish-freezes-total-temporary ()
  (require 'p3-startup-profile)
  (let ((p3/startup-profile-active t)
        (p3/startup-profile-total-seconds nil)
        (before-init-time (seconds-to-time 100.0)))
    (cl-letf (((symbol-function 'current-time)
               (lambda () (seconds-to-time 102.5))))
      (p3/startup-profile-finish))
    (should (= p3/startup-profile-total-seconds 2.5))
    (should-not p3/startup-profile-active)))

(ert-deftest p3-startup-profile-format-is-shareable-temporary ()
  (require 'p3-startup-profile)
  (let ((p3/startup-profile-total-seconds 1.5)
        (p3/startup-profile-phases
         '(("package-initialize" 0.2 1)
           ("use-package-ensure" 0.3 4))))
    (let ((text (p3/startup-profile-format)))
      (should (string-match-p (regexp-quote emacs-version) text))
      (should (string-match-p (regexp-quote (symbol-name system-type)) text))
      (should (string-match-p "Total init: 1\\.500 s" text))
      (should (string-match-p "use-package-ensure.*4 calls" text)))))

(provide 'p3-config-retirement-test)

;;; p3-config-retirement-test.el ends here
