;;; p3-startup-profile.el --- Lightweight startup timing -*- lexical-binding: t; -*-

;;; Commentary:

;; Record coarse startup phases without imposing wall-clock thresholds on CI.
;; Timing stops at `emacs-startup-hook'; the retained data can then be shown
;; with `p3/startup-profile-report'.

;;; Code:

(defvar p3/startup-profile-active t
  "Non-nil while startup phase timing is active.")

(defvar p3/startup-profile-phases nil
  "Recorded startup phases as (NAME SECONDS COUNT) entries.")

(defvar p3/startup-profile-total-seconds nil
  "Total startup duration in seconds after startup completes.")

(defun p3/startup-profile-record (name seconds)
  "Record SECONDS for startup phase NAME and return SECONDS.
Repeated phase names accumulate elapsed time and increment their call count."
  (when p3/startup-profile-active
    (if-let ((entry (assoc-string name p3/startup-profile-phases t)))
        (setf (nth 1 entry) (+ (nth 1 entry) seconds)
              (nth 2 entry) (1+ (nth 2 entry)))
      (setq p3/startup-profile-phases
            (append p3/startup-profile-phases
                    (list (list name seconds 1))))))
  seconds)

(defmacro p3/with-startup-profile-phase (name &rest body)
  "Evaluate BODY while recording elapsed time under startup phase NAME.
After startup timing is inactive, evaluate BODY without consulting the clock."
  (declare (indent 1) (debug t))
  `(if p3/startup-profile-active
       (let ((p3-startup-profile--started (float-time)))
         (prog1 (progn ,@body)
           (p3/startup-profile-record
            ,name
            (- (float-time) p3-startup-profile--started))))
     (progn ,@body)))

(defun p3/startup-profile-finish ()
  "Freeze total startup time and stop phase timing."
  (when p3/startup-profile-active
    (setq p3/startup-profile-total-seconds
          (float-time (time-subtract (current-time) before-init-time))
          p3/startup-profile-active nil)))

(defun p3/startup-profile-format ()
  "Return the retained startup profile as shareable plain text."
  (with-temp-buffer
    (insert "P3 startup profile\n"
            (format "Platform: %s\n" system-type)
            (format "Emacs: %s\n" emacs-version)
            (if p3/startup-profile-total-seconds
                (format "Total init: %.3f s\n"
                        p3/startup-profile-total-seconds)
              "Total init: startup still active\n")
            "\nPhases:\n")
    (dolist (entry p3/startup-profile-phases)
      (insert
       (format "%-32s %8.3f s%s\n"
               (nth 0 entry)
               (nth 1 entry)
               (if (> (nth 2 entry) 1)
                   (format "  (%d calls)" (nth 2 entry))
                 ""))))
    (buffer-string)))

;;;###autoload
(defun p3/startup-profile-report ()
  "Display the retained startup timing report."
  (interactive)
  (let ((buffer (get-buffer-create "*P3 Startup Profile*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (p3/startup-profile-format))
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buffer)))

(add-hook 'emacs-startup-hook #'p3/startup-profile-finish)

(provide 'p3-startup-profile)

;;; p3-startup-profile.el ends here
