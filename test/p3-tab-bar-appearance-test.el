;;; p3-tab-bar-appearance-test.el --- Supplemental appearance tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'tab-bar)
(require 'p3-config-appearance-test)

(defvar ess-local-process-name)
(defvar mode-line-process)
(defvar overwrite-mode)
(defvar vc-mode)

(ert-deftest p3-tab-bar-active-project-uses-shared-accent ()
  (p3-config-appearance-test--load-appearance)
  (should (boundp 'p3/appearance-accent-color))
  (should (equal p3/appearance-accent-color "#FFD700"))
  (should (equal (face-foreground 'line-number-current-line nil t)
                 p3/appearance-accent-color))
  (should (equal (face-foreground 'tab-bar-tab nil t)
                 p3/appearance-accent-color))
  (should (eq (face-attribute 'tab-bar-tab :weight nil t) 'semi-bold))
  (should-not (face-attribute 'tab-bar-tab :box nil nil)))

(ert-deftest p3-tab-bar-inactive-projects-recede-and-controls-stay-quiet ()
  (p3-config-appearance-test--load-appearance)
  (should (equal (face-foreground 'tab-bar-tab-inactive nil t)
                 (face-foreground 'shadow nil t)))
  (should (eq (face-attribute 'tab-bar-tab-inactive :weight nil t) 'normal))
  (should-not (face-attribute 'tab-bar-tab-inactive :box nil nil))
  (should (eq tab-bar-close-button-show 'selected))
  (should (memq 'tab-bar-format-tabs tab-bar-format))
  (should (memq 'tab-bar-format-add-tab tab-bar-format)))

(ert-deftest p3-modeline-r-busy-state-is-visible-without-probing-r ()
  (p3-config-appearance-test--load-appearance)
  (with-temp-buffer
    (setq-local ess-local-process-name "R")
    (let ((mode-line-process nil))
      (cl-letf (((symbol-function 'window-total-width)
                 (lambda (&optional _) 140))
                ((symbol-function 'get-process)
                 (lambda (name) (and (equal name "R") 'fake-r-process)))
                ((symbol-function 'process-live-p)
                 (lambda (process) (eq process 'fake-r-process)))
                ((symbol-function 'process-get)
                 (lambda (process property)
                   (and (eq process 'fake-r-process)
                        (eq property 'busy)))))
        (should (equal "R ↻"
                       (substring-no-properties
                        (p3/appearance--process-segment))))))))

(ert-deftest p3-modeline-r-idle-state-stays-quiet ()
  (p3-config-appearance-test--load-appearance)
  (with-temp-buffer
    (setq-local ess-local-process-name "R")
    (let ((mode-line-process nil))
      (cl-letf (((symbol-function 'window-total-width)
                 (lambda (&optional _) 140))
                ((symbol-function 'get-process)
                 (lambda (_) 'fake-r-process))
                ((symbol-function 'process-live-p)
                 (lambda (_) t))
                ((symbol-function 'process-get)
                 (lambda (&rest _) nil)))
        (should-not (p3/appearance--process-segment))))))

(ert-deftest p3-modeline-git-segment-preserves-vc-state ()
  (p3-config-appearance-test--load-appearance)
  (with-temp-buffer
    (let ((p3/appearance--icons-available nil))
      (dolist (case '((" Git-main" . "Git main")
                      (" Git:main" . "Git main ●")
                      (" Git@main" . "Git main +")
                      (" Git!main" . "Git main !")
                      (" Git?main" . "Git main ?")))
        (let ((vc-mode (car case)))
          (should (equal (cdr case)
                         (substring-no-properties
                          (p3/appearance--vc-segment)))))))))

(ert-deftest p3-modeline-flycheck-success-is-silent ()
  (p3-config-appearance-test--load-appearance)
  (let ((flycheck-current-errors nil))
    (cl-letf (((symbol-function 'flycheck-count-errors)
               (lambda (_) nil)))
      (should-not (p3/appearance--flycheck-finished-segment)))))

(ert-deftest p3-modeline-overwrite-state-is-visible ()
  (p3-config-appearance-test--load-appearance)
  (with-temp-buffer
    (let ((overwrite-mode t))
      (should (string-match-p "OVR"
                              (p3/appearance--buffer-state))))
    (let ((overwrite-mode 'overwrite-mode-binary))
      (should (string-match-p "BIN"
                              (p3/appearance--buffer-state))))))

(provide 'p3-tab-bar-appearance-test)

;;; p3-tab-bar-appearance-test.el ends here
