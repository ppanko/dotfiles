;;; p3-screen-record.el --- Cross-platform screen recording -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep screen recording deliberately small: one Emacs process/state layer and
;; narrow platform/session-specific command construction.  Audio capture,
;; recorder-device management, and post-processing are intentionally out of
;; scope.

;;; Code:

(require 'subr-x)

(defgroup p3/screen-record nil
  "Full-screen video recording from Emacs."
  :group 'external)

(defcustom p3/screen-record-directory
  (file-name-as-directory (expand-file-name "~/Videos/recordings/"))
  "Directory where screen recordings are written."
  :type 'directory
  :group 'p3/screen-record)

(defvar p3/screen-record--process nil
  "Current screen-recording process, or nil.")

(defvar p3/screen-record--backend nil
  "Backend symbol for the current recording, or nil.")

(defvar p3/screen-record--output-path nil
  "Output path for the current recording, or nil.")

(defun p3/screen-record-active-p ()
  "Return non-nil when a screen-recording process is live."
  (and p3/screen-record--process
       (process-live-p p3/screen-record--process)))

(defun p3/screen-record--wayland-p ()
  "Return non-nil when the current GNU/Linux session appears to use Wayland."
  (or (equal (downcase (or (getenv "XDG_SESSION_TYPE") "")) "wayland")
      (let ((display (getenv "WAYLAND_DISPLAY")))
        (and display (not (string-empty-p display))))))

(defun p3/screen-record--ffmpeg-command (input-format input output)
  "Return an FFmpeg command for INPUT-FORMAT, INPUT, and OUTPUT."
  (list "ffmpeg" "-n"
        "-f" input-format
        "-framerate" "30"
        "-i" input
        "-c:v" "libx264"
        "-preset" "veryfast"
        "-pix_fmt" "yuv420p"
        output))

(defun p3/screen-record--wayland-outputs (program)
  "Return Wayland output names reported by wf-recorder PROGRAM.
Signal `user-error' when output discovery itself fails."
  (with-temp-buffer
    (let* ((status (process-file program nil t nil "-L"))
           (detail (string-trim (buffer-string))))
      (unless (and (integerp status) (zerop status))
        (user-error "Cannot enumerate Wayland outputs with wf-recorder%s"
                    (if (string-empty-p detail)
                        ""
                      (format ": %s" detail))))
      (goto-char (point-min))
      (let (outputs)
        (while (re-search-forward
                "^[[:space:]]*[0-9]+\\. Name: \\([^[:space:]]+\\) Description:"
                nil t)
          (push (match-string-no-properties 1) outputs))
        (setq outputs (nreverse (delete-dups outputs)))
        (unless outputs
          (user-error "wf-recorder found no usable Wayland outputs%s"
                      (if (string-empty-p detail)
                          ""
                        (format ": %s" detail))))
        outputs))))

(defun p3/screen-record--wayland-output (program)
  "Choose one Wayland output reported by wf-recorder PROGRAM.
A single output is selected automatically; multiple outputs use the minibuffer."
  (let ((outputs (p3/screen-record--wayland-outputs program)))
    (if (null (cdr outputs))
        (car outputs)
      (completing-read "Wayland output to record: " outputs nil t nil nil
                       (car outputs)))))

(defun p3/screen-record--command (output)
  "Return the recorder command for OUTPUT on the current platform/session."
  (pcase system-type
    ('windows-nt
     (p3/screen-record--ffmpeg-command "gdigrab" "desktop" output))
    ('gnu/linux
     (if (p3/screen-record--wayland-p)
         (let ((program (executable-find "wf-recorder")))
           (unless program
             (user-error "Required screen recorder not found: wf-recorder"))
           (list "wf-recorder" "-o"
                 (p3/screen-record--wayland-output program)
                 "-f" output))
       (let ((display (getenv "DISPLAY")))
         (unless (and display (not (string-empty-p display)))
           (user-error "Cannot record X11 screen: DISPLAY is not set"))
         (p3/screen-record--ffmpeg-command "x11grab" display output))))
    (_
     (user-error "Screen recording is unsupported on %s" system-type))))

(defun p3/screen-record--output-file ()
  "Return a unique timestamped file below `p3/screen-record-directory'."
  (let* ((directory
          (file-name-as-directory (expand-file-name p3/screen-record-directory)))
         (stem (format "screen-%s" (format-time-string "%Y%m%d-%H%M%S")))
         (index 0)
         candidate)
    (while
        (progn
          (setq candidate
                (expand-file-name
                 (format "%s%s.mp4" stem
                         (if (zerop index) "" (format "-%d" index)))
                 directory))
          (setq index (1+ index))
          (file-exists-p candidate)))
    candidate))

(defun p3/screen-record--backend-for-command (command)
  "Return the backend symbol represented by COMMAND."
  (if (string= (file-name-nondirectory (car command)) "wf-recorder")
      'wf-recorder
    'ffmpeg))

(defun p3/screen-record--terminal-status-p (status)
  "Return non-nil when process STATUS represents a terminal state."
  (memq status '(exit signal failed closed)))

(defun p3/screen-record--ensure-output-directory (output)
  "Ensure the parent directory for OUTPUT exists and is writable."
  (let ((directory (file-name-directory output)))
    (condition-case err
        (make-directory directory t)
      (file-error
       (user-error "Cannot prepare screen-recording directory %s: %s"
                   directory (error-message-string err))))
    (unless (file-directory-p directory)
      (user-error "Screen-recording output parent is not a directory: %s"
                  directory))
    (unless (file-writable-p directory)
      (user-error "Screen-recording directory is not writable: %s" directory))))

(defun p3/screen-record--process-detail (process)
  "Return a concise final diagnostic line from PROCESS, or nil."
  (when-let ((buffer (process-buffer process)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (car (last (split-string (string-trim (buffer-string)) "\n" t
                                 "[[:space:]]+")))))))

(defun p3/screen-record--failed-process-p (process status)
  "Return non-nil when PROCESS terminated unsuccessfully with STATUS."
  (or (eq status 'failed)
      (and (memq status '(exit signal))
           (/= (process-exit-status process) 0))))

(defun p3/screen-record--sentinel (process event)
  "Clear recording state when PROCESS exits or is signaled.
EVENT is the process sentinel event string."
  (let ((status (process-status process)))
    (when (and (eq process p3/screen-record--process)
               (p3/screen-record--terminal-status-p status))
      (let* ((output p3/screen-record--output-path)
             (failed (p3/screen-record--failed-process-p process status))
             (detail (and failed (p3/screen-record--process-detail process)))
             (event-text (string-trim event)))
        (setq p3/screen-record--process nil
              p3/screen-record--backend nil
              p3/screen-record--output-path nil)
        (force-mode-line-update t)
        (message "%s%s"
                 (if failed
                     (if output
                         (format "Screen recording failed: %s" output)
                       "Screen recording failed")
                   (if output
                       (format "Screen recording finished: %s" output)
                     "Screen recording finished"))
                 (cond
                  (detail (format ": %s" detail))
                  ((string-empty-p event-text) "")
                  (t (format " (%s)" event-text))))))))

(defun p3/screen-record-start ()
  "Start a full-screen video recording for the current platform/session."
  (interactive)
  (when (p3/screen-record-active-p)
    (user-error "A screen recording is already active"))
  (let* ((output (p3/screen-record--output-file))
         (command (p3/screen-record--command output))
         (program (executable-find (car command))))
    (unless program
      (user-error "Required screen recorder not found: %s" (car command)))
    (p3/screen-record--ensure-output-directory output)
    (let* ((resolved-command (cons program (cdr command)))
           (backend (p3/screen-record--backend-for-command command))
           (buffer (get-buffer-create "*p3-screen-record*")))
      (with-current-buffer buffer
        (erase-buffer))
      (let ((process
             (make-process
              :name "p3-screen-record"
              :buffer buffer
              :command resolved-command
              :connection-type 'pipe
              :sentinel #'p3/screen-record--sentinel)))
        (setq p3/screen-record--process process
              p3/screen-record--backend backend
              p3/screen-record--output-path output)
        ;; A very fast backend failure can occur before the sentinel sees the
        ;; process as current. Reconcile that race immediately after ownership.
        (if (p3/screen-record--terminal-status-p (process-status process))
            (progn
              (p3/screen-record--sentinel process "exited during startup")
              nil)
          (force-mode-line-update t)
          (message "Screen recording started: %s" output)
          process)))))

(defun p3/screen-record-stop ()
  "Ask the active screen recorder to finalize and stop cleanly."
  (interactive)
  (unless (p3/screen-record-active-p)
    (user-error "No screen recording is active"))
  (pcase p3/screen-record--backend
    ('ffmpeg
     ;; FFmpeg's interactive `q' command exits after finalizing the container.
     (process-send-string p3/screen-record--process "q\n"))
    ('wf-recorder
     ;; SIGINT is wf-recorder's documented normal stop path.
     (interrupt-process p3/screen-record--process))
    (_
     (user-error "Unknown active screen recorder backend: %s"
                 p3/screen-record--backend)))
  (message "Stopping screen recording…"))

(defun p3/screen-record ()
  "Toggle full-screen recording on or off."
  (interactive)
  (if (p3/screen-record-active-p)
      (p3/screen-record-stop)
    (p3/screen-record-start)))

(defun p3/screen-record-indicator ()
  "Return a visible mode-line indicator while recording is active."
  (when (p3/screen-record-active-p)
    (propertize "REC"
                'face 'error
                'help-echo "Screen recording is active")))

(provide 'p3-screen-record)

;;; p3-screen-record.el ends here
