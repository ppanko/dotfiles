;;; p3-org-present.el --- Org presentation behavior -*- lexical-binding: t; -*-

(require 'face-remap)

(defvar display-line-numbers-mode)
(defvar hide-mode-line-mode)
(defvar org-inline-image-overlays)
(defvar visual-fill-column-center-text)
(defvar visual-fill-column-mode)
(defvar visual-fill-column-width)

(declare-function display-line-numbers-mode "display-line-numbers" (&optional arg))
(declare-function hide-mode-line-mode "hide-mode-line" (&optional arg))
(declare-function org-display-inline-images "org" (&rest args))
(declare-function org-present "org-present" ())
(declare-function org-present-big "org-present" ())
(declare-function org-present-next "org-present" ())
(declare-function org-present-prev "org-present" ())
(declare-function org-present-small "org-present" ())
(declare-function org-remove-inline-images "org" ())
(declare-function visual-fill-column-mode "visual-fill-column" (&optional arg))

(defvar-local p3/org-present--state nil
  "Saved buffer state while `org-present' is active.")

(defun p3/org-present-start ()
  "Start a presentation in the current Org buffer."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Presentation mode requires an Org buffer"))
  (org-present))

(defun p3/org-present-toggle-fullscreen ()
  "Toggle fullscreen for the current presentation frame."
  (interactive)
  (set-frame-parameter
   nil 'fullscreen
   (unless (frame-parameter nil 'fullscreen) 'fullboth)))

(defun p3/org-present-hook ()
  "Prepare the current Org buffer for presentation mode."
  (setq-local p3/org-present--state
              (list :header-line header-line-format
                    :line-numbers (bound-and-true-p display-line-numbers-mode)
                    :inline-images (and (boundp 'org-inline-image-overlays)
                                        org-inline-image-overlays)
                    :visual-fill (bound-and-true-p visual-fill-column-mode)
                    :visual-fill-width visual-fill-column-width
                    :visual-fill-center visual-fill-column-center-text
                    :hide-mode-line (bound-and-true-p hide-mode-line-mode)
                    :face-remap-cookies nil))
  (setq-local header-line-format " ")
  (display-line-numbers-mode -1)
  (org-present-big)
  (unless (and (boundp 'org-inline-image-overlays)
               org-inline-image-overlays)
    (org-display-inline-images))
  (setq-local visual-fill-column-width 90
              visual-fill-column-center-text t)
  (visual-fill-column-mode 1)
  (hide-mode-line-mode +1)
  (setf (plist-get p3/org-present--state :face-remap-cookies)
        (list (face-remap-add-relative 'org-level-1 :height 1.5)
              (face-remap-add-relative 'org-level-2 :height 1.2)
              (face-remap-add-relative 'org-level-3 :height 1.1))))

(defun p3/org-present-quit-hook ()
  "Restore the buffer state saved by `p3/org-present-hook'."
  (let ((state p3/org-present--state))
    (org-present-small)
    (when state
      (setq-local header-line-format (plist-get state :header-line))
      (if (plist-get state :line-numbers)
          (display-line-numbers-mode +1)
        (display-line-numbers-mode -1))
      (unless (plist-get state :inline-images)
        (org-remove-inline-images))
      (setq-local visual-fill-column-width
                  (plist-get state :visual-fill-width)
                  visual-fill-column-center-text
                  (plist-get state :visual-fill-center))
      (if (plist-get state :visual-fill)
          (visual-fill-column-mode +1)
        (visual-fill-column-mode -1))
      (if (plist-get state :hide-mode-line)
          (hide-mode-line-mode +1)
        (hide-mode-line-mode -1))
      (dolist (cookie (plist-get state :face-remap-cookies))
        (face-remap-remove-relative cookie)))
    (setq-local p3/org-present--state nil)))

(defun p3/org-present-prev ()
  "Move to the previous presentation slide."
  (interactive)
  (org-present-prev))

(defun p3/org-present-next ()
  "Move to the next presentation slide."
  (interactive)
  (org-present-next))

(provide 'p3-org-present)

;;; p3-org-present.el ends here
