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
  (list "ffmpeg" "-y"
        "-f" input-format
        "-framerate" "30"
        "-i" input
        "-c:v" "libx264"
        "-preset" "veryfast"
        "-pix_fmt" "yuv420p"
        output))

(defun p3/screen-record--command (output)
  "Return the recorder command for OUTPUT on the current platform/session."
  (pcase system-type
    ('windows-nt
     (p3/screen-record--ffmpeg-command "gdigrab" "desktop" output))
    ('gnu/linux
     (if (p3/screen-record--wayland-p)
         (list "wf-recorder" "-f" output)
       (let ((display (getenv "DISPLAY")))
         (unless (and display (not (string-empty-p display)))
           (user-error "Cannot record X11 screen: DISPLAY is not set"))
         (p3/screen-record--ffmpeg-command "x11grab" display output))))
    (_
     (user-error "Screen recording is unsupported on %s" system-type))))

(defun p3/screen-record--output-file ()
  "Return a timestamped output file below `p3/screen-record-directory'."
  (expand-file-name
   (format "screen-%s.mp4" (format-time-string "%Y%m%d-%H%M%S"))
   (file-name-as-directory (expand-file-name p3/screen-record-directory))))

(defun p3/screen-record--backend-for-command (command)
  "Return the backend symbol represented by COMMAND."
  (if (string= (file-name-nondirectory (car command)) "wf-recorder")
      'wf-recorder
    'ffmpeg))

(defun p3/screen-record--sentinel (process event)
  "Clear recording state when PROCESS exits or is signaled.
EVENT is the process sentinel event string."
  (when (and (eq process p3/screen-record--process)
             (memq (process-status process) '(exit signal)))
    (let ((output p3/screen-record--output-path))
      (setq p3/screen-record--process nil
            p3/screen-record--backend nil
            p3/screen-record--output-path nil)
      (force-mode-line-update t)
      (message "%s%s"
               (if output
                   (format "Screen recording finished: %s" output)
                 "Screen recording finished")
               (if (string-empty-p (string-trim event))
                   ""
                 (format " (%s)" (string-trim event)))))))

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
    (make-directory (file-name-directory output) t)
    (let* ((resolved-command (cons program (cdr command)))
           (backend (p3/screen-record--backend-for-command command))
           (process
            (make-process
             :name "p3-screen-record"
             :buffer (get-buffer-create "*p3-screen-record*")
             :command resolved-command
             :connection-type 'pipe
             :sentinel #'p3/screen-record--sentinel
             :noquery t)))
      (setq p3/screen-record--process process
            p3/screen-record--backend backend
            p3/screen-record--output-path output)
      (force-mode-line-update t)
      (message "Screen recording started: %s" output)
      process)))

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
