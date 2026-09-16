;;; p3-org-present-test.el --- Tests for p3-org-present -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defconst p3-org-present-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-org-present-test--root))
(require 'p3-org-present)

(defvar display-line-numbers-mode)
(defvar hide-mode-line-mode)
(defvar org-inline-image-overlays)
(defvar visual-fill-column-center-text)
(defvar visual-fill-column-mode)
(defvar visual-fill-column-width)

(ert-deftest p3-org-present-start-rejects-non-org-buffer ()
  (with-temp-buffer
    (fundamental-mode)
    (should-error (p3/org-present-start) :type 'user-error)))

(ert-deftest p3-org-present-start-delegates-in-org-buffer ()
  (let (called)
    (cl-letf (((symbol-function 'derived-mode-p)
               (lambda (&rest _) t))
              ((symbol-function 'org-present)
               (lambda () (setq called t))))
      (p3/org-present-start)
      (should called))))

(ert-deftest p3-org-present-fullscreen-toggles-fullboth ()
  (let (fullscreen)
    (cl-letf (((symbol-function 'frame-parameter)
               (lambda (_frame parameter)
                 (and (eq parameter 'fullscreen) fullscreen)))
              ((symbol-function 'set-frame-parameter)
               (lambda (_frame parameter value)
                 (when (eq parameter 'fullscreen)
                   (setq fullscreen value)))))
      (p3/org-present-toggle-fullscreen)
      (should (eq fullscreen 'fullboth))
      (p3/org-present-toggle-fullscreen)
      (should-not fullscreen))))

(ert-deftest p3-org-present-navigation-delegates ()
  (let ((next 0)
        (prev 0))
    (cl-letf (((symbol-function 'org-present-next)
               (lambda () (setq next (1+ next))))
              ((symbol-function 'org-present-prev)
               (lambda () (setq prev (1+ prev)))))
      (p3/org-present-next)
      (p3/org-present-prev)
      (should (= next 1))
      (should (= prev 1)))))

(ert-deftest p3-org-present-enter-and-quit-restore-buffer-state ()
  (with-temp-buffer
    (setq-local header-line-format "old header"
                display-line-numbers-mode t
                org-inline-image-overlays nil
                visual-fill-column-mode nil
                visual-fill-column-width 72
                visual-fill-column-center-text nil
                hide-mode-line-mode t)
    (let ((frame 'presentation-frame)
          (tab-bar-lines 1)
          (tab-bar-lines-keep-state nil)
          big-called
          small-called
          images-displayed
          image-layouts-applied
          images-removed
          remap-adds
          remap-removes)
      (cl-letf (((symbol-function 'selected-frame)
                 (lambda () frame))
                ((symbol-function 'frame-parameter)
                 (lambda (candidate parameter)
                   (when (eq candidate frame)
                     (pcase parameter
                       ('tab-bar-lines tab-bar-lines)
                       ('tab-bar-lines-keep-state tab-bar-lines-keep-state)))))
                ((symbol-function 'set-frame-parameter)
                 (lambda (candidate parameter value)
                   (when (eq candidate frame)
                     (pcase parameter
                       ('tab-bar-lines (setq tab-bar-lines value))
                       ('tab-bar-lines-keep-state
                        (setq tab-bar-lines-keep-state value))))))
                ((symbol-function 'frame-live-p)
                 (lambda (candidate) (eq candidate frame)))
                ((symbol-function 'display-line-numbers-mode)
                 (lambda (arg)
                   (setq-local display-line-numbers-mode (> arg 0))))
                ((symbol-function 'org-present-big)
                 (lambda () (setq big-called t)))
                ((symbol-function 'org-present-small)
                 (lambda () (setq small-called t)))
                ((symbol-function 'org-display-inline-images)
                 (lambda (&rest _)
                   (setq images-displayed t
                         org-inline-image-overlays '(shown))))
                ((symbol-function 'p3/org-apply-image-layouts)
                 (lambda () (setq image-layouts-applied t)))
                ((symbol-function 'org-remove-inline-images)
                 (lambda ()
                   (setq images-removed t
                         org-inline-image-overlays nil)))
                ((symbol-function 'visual-fill-column-mode)
                 (lambda (arg)
                   (setq-local visual-fill-column-mode (> arg 0))))
                ((symbol-function 'hide-mode-line-mode)
                 (lambda (arg)
                   (setq-local hide-mode-line-mode (> arg 0))))
                ((symbol-function 'face-remap-add-relative)
                 (lambda (face &rest properties)
                   (let ((cookie (list face properties)))
                     (push cookie remap-adds)
                     cookie)))
                ((symbol-function 'face-remap-remove-relative)
                 (lambda (cookie)
                   (push cookie remap-removes))))
        (p3/org-present-hook)
        (should big-called)
        (should images-displayed)
        (should image-layouts-applied)
        (should (equal header-line-format " "))
        (should-not display-line-numbers-mode)
        (should visual-fill-column-mode)
        (should (= visual-fill-column-width 90))
        (should visual-fill-column-center-text)
        (should hide-mode-line-mode)
        (should (= tab-bar-lines 0))
        (should tab-bar-lines-keep-state)
        (should (= (length remap-adds) 3))
        (should (member '(org-level-1 (:height 1.5)) remap-adds))
        (should (member '(org-level-2 (:height 1.2)) remap-adds))
        (should (member '(org-level-3 (:height 1.1)) remap-adds))
        (should (equal (plist-get p3/org-present--state :header-line)
                       "old header"))
        (should (eq (plist-get p3/org-present--state :frame) frame))
        (should (= (plist-get p3/org-present--state :tab-bar-lines) 1))
        (should (plist-member p3/org-present--state
                              :tab-bar-lines-keep-state))
        (should-not (plist-get p3/org-present--state
                               :tab-bar-lines-keep-state))
        (should (plist-get p3/org-present--state :line-numbers))
        (should-not (plist-get p3/org-present--state :inline-images))
        (should-not (plist-get p3/org-present--state :visual-fill))
        (should (= (plist-get p3/org-present--state :visual-fill-width) 72))
        (should-not (plist-get p3/org-present--state :visual-fill-center))
        (should (plist-get p3/org-present--state :hide-mode-line))

        (p3/org-present-quit-hook)
        (should small-called)
        (should images-removed)
        (should (equal header-line-format "old header"))
        (should display-line-numbers-mode)
        (should-not visual-fill-column-mode)
        (should (= visual-fill-column-width 72))
        (should-not visual-fill-column-center-text)
        (should hide-mode-line-mode)
        (should (= tab-bar-lines 1))
        (should-not tab-bar-lines-keep-state)
        (should (= (length remap-removes) 3))
        (should-not p3/org-present--state)))))

(ert-deftest p3-org-present-rerenders-preexisting-images-after-restoring-editing-width ()
  (with-temp-buffer
    (setq-local header-line-format nil
                display-line-numbers-mode nil
                org-inline-image-overlays '(existing)
                visual-fill-column-mode t
                visual-fill-column-width 72
                visual-fill-column-center-text nil
                hide-mode-line-mode nil)
    (let ((frame 'presentation-frame)
          (tab-bar-lines 1)
          (tab-bar-lines-keep-state nil)
          refresh-widths)
      (cl-letf (((symbol-function 'selected-frame)
                 (lambda () frame))
                ((symbol-function 'frame-parameter)
                 (lambda (candidate parameter)
                   (when (eq candidate frame)
                     (pcase parameter
                       ('tab-bar-lines tab-bar-lines)
                       ('tab-bar-lines-keep-state tab-bar-lines-keep-state)))))
                ((symbol-function 'set-frame-parameter)
                 (lambda (candidate parameter value)
                   (when (eq candidate frame)
                     (pcase parameter
                       ('tab-bar-lines (setq tab-bar-lines value))
                       ('tab-bar-lines-keep-state
                        (setq tab-bar-lines-keep-state value))))))
                ((symbol-function 'frame-live-p)
                 (lambda (candidate) (eq candidate frame)))
                ((symbol-function 'display-line-numbers-mode) #'ignore)
                ((symbol-function 'org-present-big) #'ignore)
                ((symbol-function 'org-present-small) #'ignore)
                ((symbol-function 'p3/org--refresh-inline-images)
                 (lambda () (push visual-fill-column-width refresh-widths)))
                ((symbol-function 'visual-fill-column-mode)
                 (lambda (arg)
                   (setq-local visual-fill-column-mode (> arg 0))))
                ((symbol-function 'hide-mode-line-mode) #'ignore)
                ((symbol-function 'face-remap-add-relative)
                 (lambda (&rest _) 'cookie))
                ((symbol-function 'face-remap-remove-relative) #'ignore))
        (p3/org-present-hook)
        (p3/org-present-quit-hook)
        (should (equal (nreverse refresh-widths) '(90 72)))
        (should (= tab-bar-lines 1))
        (should-not tab-bar-lines-keep-state)))))

(provide 'p3-org-present-test)

;;; p3-org-present-test.el ends here
