;;; p3-screen-record-test.el --- Screen-recording tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-screen-record-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-screen-record-test--root))

(require 'p3-screen-record nil t)

(defun p3-screen-record-test--contents (relative)
  "Return contents of RELATIVE under the repository root."
  (with-temp-buffer
    (insert-file-contents (expand-file-name relative p3-screen-record-test--root))
    (buffer-string)))

(defmacro p3-screen-record-test--with-module (&rest body)
  "Run BODY only when the production module is available."
  `(progn
     (skip-unless (featurep 'p3-screen-record))
     ,@body))

(ert-deftest p3-screen-record-module-exposes-interactive-command ()
  (should (featurep 'p3-screen-record))
  (should (commandp 'p3/screen-record)))

(ert-deftest p3-screen-record-base-loads-behavior-owner ()
  (let ((base (p3-screen-record-test--contents "lisp/p3-config-base.el")))
    (should
     (string-match-p
      (regexp-quote "(p3/config-load-module 'p3-screen-record)")
      base))))

(ert-deftest p3-screen-record-windows-command-uses-gdigrab-without-audio ()
  (p3-screen-record-test--with-module
   (let ((system-type 'windows-nt))
     (should
      (equal
       (p3/screen-record--command "C:/Users/test/Videos/screen.mp4")
       '("ffmpeg" "-n" "-f" "gdigrab" "-framerate" "30"
         "-i" "desktop" "-c:v" "libx264" "-preset" "veryfast"
         "-pix_fmt" "yuv420p" "C:/Users/test/Videos/screen.mp4"))))))

(ert-deftest p3-screen-record-x11-command-uses-current-display-without-audio ()
  (p3-screen-record-test--with-module
   (let ((system-type 'gnu/linux))
     (cl-letf (((symbol-function 'getenv)
                (lambda (name)
                  (pcase name
                    ("XDG_SESSION_TYPE" "x11")
                    ("DISPLAY" ":7.0")
                    (_ nil)))))
       (should
        (equal
         (p3/screen-record--command "/tmp/screen.mp4")
         '("ffmpeg" "-n" "-f" "x11grab" "-framerate" "30"
           "-i" ":7.0" "-c:v" "libx264" "-preset" "veryfast"
           "-pix_fmt" "yuv420p" "/tmp/screen.mp4")))))))

(ert-deftest p3-screen-record-wayland-command-selects-output-without-audio ()
  (p3-screen-record-test--with-module
   (let ((system-type 'gnu/linux))
     (cl-letf (((symbol-function 'getenv)
                (lambda (name)
                  (pcase name
                    ("XDG_SESSION_TYPE" "wayland")
                    ("WAYLAND_DISPLAY" "wayland-1")
                    (_ nil))))
               ((symbol-function 'executable-find)
                (lambda (program)
                  (when (equal program "wf-recorder") "/usr/bin/wf-recorder")))
               ((symbol-function 'p3/screen-record--wayland-output)
                (lambda (_program) "DP-1")))
       (should
        (equal
         (p3/screen-record--command "/tmp/screen.mp4")
         '("wf-recorder" "-o" "DP-1" "-f" "/tmp/screen.mp4")))))))

(ert-deftest p3-screen-record-wayland-output-auto-selects-single-output ()
  (p3-screen-record-test--with-module
   (should (fboundp 'p3/screen-record--wayland-output))
   (cl-letf (((symbol-function 'process-file)
              (lambda (_program _infile destination _display &rest args)
                (should (eq destination t))
                (should (equal args '("-L")))
                (insert "1. Name: eDP-1 Description: Built-in display\n")
                0)))
     (should (equal (p3/screen-record--wayland-output "/usr/bin/wf-recorder")
                    "eDP-1")))))

(ert-deftest p3-screen-record-wayland-preflight-stays-local-from-remote-buffer ()
  (p3-screen-record-test--with-module
   (let ((default-directory "/ssh:example:/tmp/")
         seen-directory)
     (cl-letf (((symbol-function 'process-file)
                (lambda (_program _infile _destination _display &rest _args)
                  (setq seen-directory default-directory)
                  (insert "1. Name: eDP-1 Description: Built-in display\n")
                  0)))
       (should (equal (p3/screen-record--wayland-output "/usr/bin/wf-recorder")
                      "eDP-1"))
       (should (equal seen-directory temporary-file-directory))))))

(ert-deftest p3-screen-record-wayland-output-prompts-in-emacs-for-multiple-outputs ()
  (p3-screen-record-test--with-module
   (should (fboundp 'p3/screen-record--wayland-output))
   (let (seen-candidates)
     (cl-letf (((symbol-function 'process-file)
                (lambda (_program _infile _destination _display &rest _args)
                  (insert "1. Name: eDP-1 Description: Built-in display\n"
                          "2. Name: DP-1 Description: External display\n")
                  0))
               ((symbol-function 'completing-read)
                (lambda (_prompt collection &rest _)
                  (setq seen-candidates collection)
                  "DP-1")))
       (should (equal (p3/screen-record--wayland-output "/usr/bin/wf-recorder")
                      "DP-1"))
       (should (equal seen-candidates '("eDP-1" "DP-1")))))))

(ert-deftest p3-screen-record-wayland-output-reports-preflight-failure ()
  (p3-screen-record-test--with-module
   (should (fboundp 'p3/screen-record--wayland-output))
   (cl-letf (((symbol-function 'process-file)
              (lambda (_program _infile _destination _display &rest _args)
                (insert "failed to create display")
                1)))
     (let ((err (should-error
                 (p3/screen-record--wayland-output "/usr/bin/wf-recorder")
                 :type 'user-error)))
       (should (string-match-p "failed to create display"
                               (error-message-string err)))))))

(ert-deftest p3-screen-record-wayland-output-explains-wlroots-requirement ()
  (p3-screen-record-test--with-module
   (cl-letf (((symbol-function 'process-file)
              (lambda (_program _infile _destination _display &rest _args)
                (insert "compositor doesn't support wlr-screencopy-unstable-v1")
                1)))
     (let ((err (should-error
                 (p3/screen-record--wayland-output "/usr/bin/wf-recorder")
                 :type 'user-error)))
       (should (string-match-p "wlroots-compatible"
                               (error-message-string err)))))))

(ert-deftest p3-screen-record-unsupported-platform-fails-clearly ()
  (p3-screen-record-test--with-module
   (let ((system-type 'darwin))
     (should-error (p3/screen-record--command "/tmp/screen.mp4")
                   :type 'user-error))))

(ert-deftest p3-screen-record-x11-without-display-fails-clearly ()
  (p3-screen-record-test--with-module
   (let ((system-type 'gnu/linux))
     (cl-letf (((symbol-function 'getenv) (lambda (_name) nil)))
       (should-error (p3/screen-record--command "/tmp/screen.mp4")
                     :type 'user-error)))))

(ert-deftest p3-screen-record-output-file-is-timestamped-under-configured-directory ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record-directory "/tmp/recordings/"))
     (cl-letf (((symbol-function 'format-time-string)
                (lambda (&rest _) "20260914-101530"))
               ((symbol-function 'file-exists-p) (lambda (_path) nil)))
       (should
        (equal
         (p3/screen-record--output-file)
         (expand-file-name "screen-20260914-101530.mp4"
                           "/tmp/recordings/")))))))

(ert-deftest p3-screen-record-output-file-avoids-existing-timestamp-collision ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record-directory "/tmp/recordings/"))
     (cl-letf (((symbol-function 'format-time-string)
                (lambda (&rest _) "20260914-101530"))
               ((symbol-function 'file-exists-p)
                (lambda (path)
                  (string-suffix-p "screen-20260914-101530.mp4" path))))
       (should
        (equal
         (p3/screen-record--output-file)
         (expand-file-name "screen-20260914-101530-1.mp4"
                           "/tmp/recordings/")))))))

(ert-deftest p3-screen-record-start-prevents-a-second-live-recording ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record--process 'existing))
     (cl-letf (((symbol-function 'process-live-p) (lambda (_process) t))
               ((symbol-function 'make-process)
                (lambda (&rest _)
                  (ert-fail "A second recorder process was started"))))
       (should-error (p3/screen-record-start) :type 'user-error)))))

(ert-deftest p3-screen-record-start-owns-process-and-backend-state ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record--process nil)
         (p3/screen-record--backend nil)
         (captured-command nil)
         (captured-noquery 'unset)
         (created-directory nil)
         (mode-line-refreshed nil))
     (cl-letf (((symbol-function 'p3/screen-record--output-file)
                (lambda () "/tmp/screen.mp4"))
               ((symbol-function 'p3/screen-record--command)
                (lambda (_output)
                  '("ffmpeg" "-f" "x11grab" "-i" ":0" "/tmp/screen.mp4")))
               ((symbol-function 'executable-find)
                (lambda (program)
                  (when (equal program "ffmpeg") "/usr/bin/ffmpeg")))
               ((symbol-function 'make-directory)
                (lambda (directory &rest _)
                  (setq created-directory directory)))
               ((symbol-function 'file-directory-p) (lambda (_directory) t))
               ((symbol-function 'file-writable-p) (lambda (_directory) t))
               ((symbol-function 'make-process)
                (lambda (&rest plist)
                  (setq captured-command (plist-get plist :command)
                        captured-noquery (plist-get plist :noquery))
                  'recorder-process))
               ((symbol-function 'process-status)
                (lambda (_process) 'run))
               ((symbol-function 'force-mode-line-update)
                (lambda (&rest _) (setq mode-line-refreshed t))))
       (p3/screen-record-start)
       (should (eq p3/screen-record--process 'recorder-process))
       (should (eq p3/screen-record--backend 'ffmpeg))
       (should (equal created-directory (file-name-directory "/tmp/screen.mp4")))
       (should (equal captured-command
                      '("/usr/bin/ffmpeg" "-f" "x11grab" "-i" ":0"
                        "/tmp/screen.mp4")))
       (should-not captured-noquery)
       (should mode-line-refreshed)))))

(ert-deftest p3-screen-record-start-clears-state-if-recorder-exits-immediately ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record--process nil)
         (p3/screen-record--backend nil)
         (p3/screen-record--output-path nil))
     (cl-letf (((symbol-function 'p3/screen-record--output-file)
                (lambda () "/tmp/screen.mp4"))
               ((symbol-function 'p3/screen-record--command)
                (lambda (_output) '("ffmpeg" "/tmp/screen.mp4")))
               ((symbol-function 'executable-find)
                (lambda (_program) "/usr/bin/ffmpeg"))
               ((symbol-function 'make-directory) (lambda (&rest _) t))
               ((symbol-function 'file-directory-p) (lambda (_directory) t))
               ((symbol-function 'file-writable-p) (lambda (_directory) t))
               ((symbol-function 'make-process)
                (lambda (&rest _) 'recorder-process))
               ((symbol-function 'process-status)
                (lambda (_process) 'exit))
               ((symbol-function 'process-exit-status) (lambda (_process) 1))
               ((symbol-function 'process-buffer) (lambda (_process) nil))
               ((symbol-function 'force-mode-line-update) (lambda (&rest _) t)))
       (p3/screen-record-start)
       (should-not p3/screen-record--process)
       (should-not p3/screen-record--backend)
       (should-not p3/screen-record--output-path)))))

(ert-deftest p3-screen-record-start-reports-missing-recorder ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record--process nil))
     (cl-letf (((symbol-function 'p3/screen-record--output-file)
                (lambda () "/tmp/screen.mp4"))
               ((symbol-function 'p3/screen-record--command)
                (lambda (_output) '("wf-recorder" "-f" "/tmp/screen.mp4")))
               ((symbol-function 'executable-find) (lambda (_program) nil)))
       (should-error (p3/screen-record-start) :type 'user-error)))))

(ert-deftest p3-screen-record-start-reports-output-directory-errors ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record--process nil))
     (cl-letf (((symbol-function 'p3/screen-record--output-file)
                (lambda () "/denied/screen.mp4"))
               ((symbol-function 'p3/screen-record--command)
                (lambda (_output) '("ffmpeg" "/denied/screen.mp4")))
               ((symbol-function 'executable-find)
                (lambda (_program) "/usr/bin/ffmpeg"))
               ((symbol-function 'make-directory)
                (lambda (&rest _)
                  (signal 'file-error '("Permission denied")))))
       (should-error (p3/screen-record-start) :type 'user-error)))))

(ert-deftest p3-screen-record-start-rejects-existing-unwritable-output-directory ()
  (p3-screen-record-test--with-module
   (cl-letf (((symbol-function 'make-directory) (lambda (&rest _) t))
             ((symbol-function 'file-directory-p) (lambda (_directory) t))
             ((symbol-function 'file-writable-p) (lambda (_directory) nil)))
     (should-error
      (p3/screen-record--ensure-output-directory "/denied/screen.mp4")
      :type 'user-error))))

(ert-deftest p3-screen-record-stop-asks-ffmpeg-to-finalize-cleanly ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record--process 'recorder-process)
         (p3/screen-record--backend 'ffmpeg)
         sent)
     (cl-letf (((symbol-function 'process-live-p) (lambda (_process) t))
               ((symbol-function 'process-send-string)
                (lambda (process string) (setq sent (list process string)))))
       (p3/screen-record-stop)
       (should (equal sent '(recorder-process "q\n")))))))

(ert-deftest p3-screen-record-stop-interrupts-wf-recorder-cleanly ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record--process 'recorder-process)
         (p3/screen-record--backend 'wf-recorder)
         interrupted)
     (cl-letf (((symbol-function 'process-live-p) (lambda (_process) t))
               ((symbol-function 'interrupt-process)
                (lambda (process) (setq interrupted process))))
       (p3/screen-record-stop)
       (should (eq interrupted 'recorder-process))))))

(ert-deftest p3-screen-record-toggle-dispatches-to-current-state ()
  (p3-screen-record-test--with-module
   (let (started stopped active)
     (cl-letf (((symbol-function 'p3/screen-record-active-p)
                (lambda () active))
               ((symbol-function 'p3/screen-record-start)
                (lambda () (setq started t)))
               ((symbol-function 'p3/screen-record-stop)
                (lambda () (setq stopped t))))
       (setq active nil)
       (p3/screen-record)
       (should started)
       (should-not stopped)
       (setq started nil
             active t)
       (p3/screen-record)
       (should stopped)
       (should-not started)))))

(ert-deftest p3-screen-record-sentinel-clears-stale-recording-state ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record--process 'recorder-process)
         (p3/screen-record--backend 'ffmpeg)
         (p3/screen-record--output-path "/tmp/screen.mp4")
         refreshed)
     (cl-letf (((symbol-function 'process-status) (lambda (_process) 'exit))
               ((symbol-function 'process-exit-status) (lambda (_process) 0))
               ((symbol-function 'process-buffer) (lambda (_process) nil))
               ((symbol-function 'force-mode-line-update)
                (lambda (&rest _) (setq refreshed t))))
       (p3/screen-record--sentinel 'recorder-process "finished\n")
       (should-not p3/screen-record--process)
       (should-not p3/screen-record--backend)
       (should-not p3/screen-record--output-path)
       (should refreshed)))))

(ert-deftest p3-screen-record-sentinel-surfaces-backend-failure-detail ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record--process 'recorder-process)
         (p3/screen-record--backend 'wf-recorder)
         (p3/screen-record--output-path "/tmp/screen.mp4")
         (buffer (generate-new-buffer " *p3-screen-record-test*"))
         seen-message)
     (unwind-protect
         (progn
           (with-current-buffer buffer
             (insert "compositor doesn't support wlr-screencopy-unstable-v1\n"))
           (cl-letf (((symbol-function 'process-status) (lambda (_process) 'exit))
                     ((symbol-function 'process-exit-status) (lambda (_process) 1))
                     ((symbol-function 'process-buffer) (lambda (_process) buffer))
                     ((symbol-function 'force-mode-line-update) (lambda (&rest _) t))
                     ((symbol-function 'message)
                      (lambda (format-string &rest args)
                        (setq seen-message (apply #'format format-string args)))))
             (p3/screen-record--sentinel 'recorder-process
                                         "exited abnormally with code 1\n")
             (should (string-match-p "Screen recording failed" seen-message))
             (should (string-match-p "wlr-screencopy" seen-message))))
       (kill-buffer buffer)))))

(ert-deftest p3-screen-record-indicator-reflects-live-process-state ()
  (p3-screen-record-test--with-module
   (let ((p3/screen-record--process 'recorder-process))
     (cl-letf (((symbol-function 'process-live-p) (lambda (_process) t)))
       (should (equal (substring-no-properties (p3/screen-record-indicator))
                      "REC")))
     (cl-letf (((symbol-function 'process-live-p) (lambda (_process) nil)))
       (should-not (p3/screen-record-indicator))))))

(ert-deftest p3-screen-record-appearance-consumes-recording-indicator ()
  (p3-screen-record-test--with-module
   (let ((appearance
          (p3-screen-record-test--contents "lisp/p3-config-appearance.el")))
     (should (string-match-p
              (regexp-quote "(p3/screen-record-indicator)")
              appearance)))))

(provide 'p3-screen-record-test)

;;; p3-screen-record-test.el ends here
