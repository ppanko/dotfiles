;;; p3-tab-bar-appearance-test.el --- Project tab appearance tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'tab-bar)
(require 'p3-config-appearance-test)

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
  (should-not (memq 'tab-bar-format-add-tab tab-bar-format)))

(provide 'p3-tab-bar-appearance-test)

;;; p3-tab-bar-appearance-test.el ends here
