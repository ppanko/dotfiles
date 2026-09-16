;;; p3-org-image.el --- Org image insertion and layout helpers -*- lexical-binding: t; -*-

(require 'image)
(require 'subr-x)

(defvar org-download-heading-lvl)
(defvar org-download-image-dir)
(defvar org-download-screenshot-method)
(defvar org-inline-image-overlays)

(declare-function org-display-inline-images "org" (&rest args))
(declare-function org-download-screenshot "org-download" (&optional basename))
(declare-function org-redisplay-inline-images "org" ())
(declare-function org-version "org" (&optional here full message))

(defconst p3/org--standalone-image-link-regexp
  "^[ \t]*\\[\\[\\(?:file:\\)?\\([^]\n]+\\)\\]\\][ \t]*$"
  "Regexp matching a standalone Org image-style file link.")

(defun p3/org--save-windows-clipboard-image (filename)
  "Save the Windows clipboard image as PNG at FILENAME using PowerShell."
  (let ((powershell (or (executable-find "powershell.exe")
                        (executable-find "powershell"))))
    (unless powershell
      (user-error "PowerShell is required to paste clipboard images on Windows"))
    (let* ((escaped
            (replace-regexp-in-string
             "'" "''" (expand-file-name filename) t t))
           (script
            (format
             (concat
              "Add-Type -AssemblyName System.Windows.Forms; "
              "Add-Type -AssemblyName System.Drawing; "
              "$image = [System.Windows.Forms.Clipboard]::GetImage(); "
              "if ($null -eq $image) { exit 2 }; "
              "$image.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png); "
              "$image.Dispose()")
             escaped))
           (status
            (call-process powershell nil nil nil
                          "-NoProfile" "-STA" "-NonInteractive"
                          "-Command" script)))
      (unless (and (integerp status) (zerop status))
        (user-error "Clipboard does not contain a readable image")))))

(defun p3/org--clipboard-image-method ()
  "Return the platform clipboard-image method for `org-download-screenshot'."
  (pcase system-type
    ('windows-nt #'p3/org--save-windows-clipboard-image)
    ('gnu/linux
     (cond
      ((and (string= (or (getenv "XDG_SESSION_TYPE") "") "wayland")
            (executable-find "wl-paste"))
       "wl-paste -t image/png > %s")
      ((executable-find "xclip")
       "xclip -selection clipboard -t image/png -o > %s")
      ((executable-find "wl-paste")
       "wl-paste -t image/png > %s")
      (t
       (user-error
        "Clipboard image paste requires xclip or wl-paste on Linux"))))
    (_
     (user-error "Clipboard image paste is unsupported on this platform"))))

(defun p3/org-insert-image ()
  "Save the clipboard image beside the current Org file and insert its link.
Images are stored under an `images' directory next to the current document."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Image insertion requires an Org buffer"))
  (unless buffer-file-name
    (user-error "Save this Org buffer before inserting an image"))
  (unless (fboundp 'org-download-screenshot)
    (user-error "org-download is unavailable"))
  (let ((default-directory
         (file-name-as-directory (file-name-directory buffer-file-name)))
        (org-download-image-dir "images")
        (org-download-heading-lvl nil)
        (org-download-screenshot-method (p3/org--clipboard-image-method)))
    (org-download-screenshot)))

(defun p3/org--image-line-beginning ()
  "Return the beginning of the standalone image link at point.
Signal a `user-error' when the current line is not a standalone image link."
  (save-excursion
    (beginning-of-line)
    (let ((case-fold-search t))
      (unless (looking-at p3/org--standalone-image-link-regexp)
        (user-error "Place point on a standalone Org image link"))
      (let ((path (match-string-no-properties 1)))
        (unless (string-match-p (image-file-name-regexp) path)
          (user-error "The link at point is not a recognized image")))
      (point))))

(defun p3/org--affiliated-attr-org-line (image-line)
  "Return the position of an ATTR_ORG line affiliated with IMAGE-LINE.
Only contiguous Org keyword lines immediately above the image are considered."
  (save-excursion
    (goto-char image-line)
    (let ((case-fold-search t)
          found
          continue)
      (setq continue (> (line-beginning-position) (point-min)))
      (while continue
        (forward-line -1)
        (cond
         ((looking-at "^[ \t]*#\\+[[:alnum:]_]+:")
          (when (looking-at "^[ \t]*#\\+ATTR_ORG:")
            (setq found (line-beginning-position)))
          (setq continue (> (line-beginning-position) (point-min))))
         (t
          (setq continue nil))))
      found)))

(defun p3/org--set-attr-value (line key value)
  "Set attribute KEY to VALUE in Org attribute LINE and return the new line."
  (let ((case-fold-search t)
        (regexp
         (format "\\(:%s\\)[ \t]+\\([^ \t\n]+\\)"
                 (regexp-quote key))))
    (if (string-match regexp line)
        (replace-match value t t line 2)
      (concat line " :" key " " value))))

(defun p3/org--image-align-at (position)
  "Return the ATTR_ORG alignment associated with image at POSITION."
  (save-excursion
    (goto-char position)
    (let ((attr-line (p3/org--affiliated-attr-org-line
                      (line-beginning-position)))
          (case-fold-search t))
      (when attr-line
        (goto-char attr-line)
        (when (re-search-forward
               ":align[ \t]+\\([^ \t\n]+\\)"
               (line-end-position) t)
          (downcase (match-string-no-properties 1)))))))

(defun p3/org--legacy-image-before-string (align image)
  "Return an Org 9.6 alignment prefix for ALIGN and IMAGE."
  (pcase align
    ("center"
     (propertize
      " " 'face 'default
      'display `(space :align-to (- center (0.5 . ,image)))))
    ("right"
     (propertize
      " " 'face 'default
      'display `(space :align-to (- right ,image))))
    (_ nil)))

(defun p3/org-apply-image-layouts ()
  "Apply native image layout metadata on Org versions before 9.7.
Org 9.7 and newer handle `:align' themselves.  Older Org versions already
understand percentage `:width' values, so only alignment needs emulation."
  (when (and (fboundp 'org-version)
             (version< (org-version) "9.7")
             (boundp 'org-inline-image-overlays))
    (dolist (overlay org-inline-image-overlays)
      (when (and (overlayp overlay)
                 (overlay-buffer overlay))
        (let ((image (overlay-get overlay 'display)))
          (when image
            (overlay-put
             overlay 'before-string
             (p3/org--legacy-image-before-string
              (p3/org--image-align-at (overlay-start overlay))
              image))))))))

(defun p3/org--refresh-inline-images ()
  "Refresh displayed Org inline images when they are already visible."
  (when (and (boundp 'org-inline-image-overlays)
             org-inline-image-overlays)
    (if (fboundp 'org-redisplay-inline-images)
        (org-redisplay-inline-images)
      (org-display-inline-images t t))
    (p3/org-apply-image-layouts)))

(defun p3/org--set-image-layout (align width)
  "Set standalone image at point to ALIGN and WIDTH using native Org metadata."
  (unless (derived-mode-p 'org-mode)
    (user-error "Image layout requires an Org buffer"))
  (let* ((image-line (p3/org--image-line-beginning))
         (attr-line (p3/org--affiliated-attr-org-line image-line)))
    (save-excursion
      (if attr-line
          (progn
            (goto-char attr-line)
            (let* ((begin (line-beginning-position))
                   (end (line-end-position))
                   (line (buffer-substring-no-properties begin end))
                   (line (p3/org--set-attr-value line "align" align))
                   (line (p3/org--set-attr-value line "width" width)))
              (delete-region begin end)
              (insert line)))
        (goto-char image-line)
        (insert (format "#+ATTR_ORG: :align %s :width %s\n" align width))))
    (p3/org--refresh-inline-images)))

(defun p3/org-image-layout-center ()
  "Center the image at point at a comfortable presentation width."
  (interactive)
  (p3/org--set-image-layout "center" "70%"))

(defun p3/org-image-layout-full ()
  "Center the image at point at the presentation text width."
  (interactive)
  (p3/org--set-image-layout "center" "100%"))

(defun p3/org-image-layout-left ()
  "Place the image at point on the left at 40 percent text width."
  (interactive)
  (p3/org--set-image-layout "left" "40%"))

(defun p3/org-image-layout-right ()
  "Place the image at point on the right at 40 percent text width."
  (interactive)
  (p3/org--set-image-layout "right" "40%"))

(defvar p3/org-image-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "i") #'p3/org-insert-image)
    (define-key map (kbd "c") #'p3/org-image-layout-center)
    (define-key map (kbd "f") #'p3/org-image-layout-full)
    (define-key map (kbd "l") #'p3/org-image-layout-left)
    (define-key map (kbd "r") #'p3/org-image-layout-right)
    map)
  "Prefix map for Org image insertion and presentation layout commands.")

(provide 'p3-org-image)

;;; p3-org-image.el ends here
