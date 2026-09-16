;;; p3-terminal-test-support.el --- Shared terminal test helpers -*- lexical-binding: t; -*-

(require 'ert)
(require 'eshell)
(require 'esh-proc)
(require 'p3-platform)

(defconst p3-terminal-test-support-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-terminal-test-support-python ()
  (or (executable-find "python3")
      (executable-find "python")
      (ert-skip "Python is unavailable for terminal fixture")))

(defun p3-terminal-test-support-prepare-platform ()
  (when (eq system-type 'windows-nt)
    (let* ((msys-root
            (or (getenv "P3_TEST_MSYS2_ROOT")
                (ert-skip "P3_TEST_MSYS2_ROOT is required on Windows")))
           (usr-bin (file-name-as-directory
                     (expand-file-name "usr/bin" msys-root))))
      (setq linuxy-environment-path usr-bin)
      (p3/windows-path-prepend usr-bin))))

(defun p3-terminal-test-support-run-fixture (buffer exit-code)
  "Run the terminal fixture in BUFFER and return an observation plist."
  (let* ((fixture (expand-file-name "test/fixtures/p3-terminal-fixture.py"
                                    p3-terminal-test-support-root))
         (python (p3-terminal-test-support-python))
         (command (mapconcat #'shell-quote-argument
                             (list python fixture (number-to-string exit-code))
                             " "))
         timer
         timeout-timer
         observed-terminal
         observed-raw-escape
         input-sent)
    (setq timer
          (run-at-time
           0.05 0.05
           (lambda ()
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (when-let ((proc (eshell-head-process)))
                   (save-excursion
                     (goto-char (point-min))
                     (when (search-forward "__P3_CURSOR__" nil t)
                       (setq observed-terminal t)
                       (goto-char (point-min))
                       (setq observed-raw-escape
                             (search-forward "\033[" nil t))
                       (process-send-string proc "x")
                       (setq input-sent t)
                       (cancel-timer timer)))))))))
    (setq timeout-timer
          (run-at-time
           5 nil
           (lambda ()
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (when-let ((proc (eshell-head-process)))
                   (delete-process proc)))))))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (goto-char (point-max))
            (insert command)
            (eshell-send-input))
          (with-current-buffer buffer
            (let (tty size input)
              (save-excursion
                (goto-char (point-min))
                (when (re-search-forward "__P3_TTY__\\([01]:[01]\\)" nil t)
                  (setq tty (match-string-no-properties 1)))
                (goto-char (point-min))
                (when (re-search-forward
                       "__P3_SIZE__\\([0-9]+\\):\\([0-9]+\\)" nil t)
                  (setq size (cons (string-to-number
                                    (match-string-no-properties 1))
                                   (string-to-number
                                    (match-string-no-properties 2)))))
                (goto-char (point-min))
                (when (re-search-forward "__P3_INPUT__\\([0-9a-f]+\\)" nil t)
                  (setq input (match-string-no-properties 1))))
              (list :terminal observed-terminal
                    :raw-escape observed-raw-escape
                    :input-sent input-sent
                    :tty tty
                    :size size
                    :input input))))
      (when (timerp timer) (cancel-timer timer))
      (when (timerp timeout-timer) (cancel-timer timeout-timer)))))

(provide 'p3-terminal-test-support)
