;;; p3-gptel.el --- Custom GPTel task workflow -*- lexical-binding: t; -*-

(require 'thingatpt)

(declare-function gptel-request "gptel" (prompt &rest args))

(defconst p3/gptel-task-prompts
  '(("Write Code" . "Write the requested code for the current programming language. Return only the code.")
    ("Refactor" . "Refactor the selected code while preserving its behavior. Return only the replacement code.")
    ("Generate Documentation" . "Add concise documentation for the selected code. Return only documentation appropriate for its language.")
    ("Write Tests" . "Write tests for the selected code. Return only the test code.")
    ("Translate Code" . "Translate the selected code to the requested target language. Return only the translated code.")
    ("Send Line" . "Explain or respond to the selected line briefly."))
  "Prompt instructions used by `p3/gptel-send-task'.")

(defun p3/gptel-task-code (task-type)
  "Return the active region or current line for TASK-TYPE."
  (if (equal task-type "Send Line")
      (thing-at-point 'line t)
    (when (use-region-p)
      (filter-buffer-substring (region-beginning) (region-end)))))

(defun p3/gptel-sensitive-buffer-p ()
  "Return non-nil when the current file looks like a secrets file."
  (and buffer-file-name
       (string-match-p
        "\\(?:^\\|[/\\\\]\\)\\(?:secrets?\\|\\.env\\|credentials?\\)"
        (file-name-nondirectory buffer-file-name))))

(defun p3/gptel-stream-begin (response context)
  "Start inserting RESPONSE directly into the target described by CONTEXT."
  (let ((buffer (plist-get context :target-buffer))
        (start (plist-get context :start-marker))
        (end (plist-get context :end-marker))
        (insert-type (plist-get context :insert-type)))
    (when (and (stringp response)
               (buffer-live-p buffer)
               (not (plist-get context :started)))
      (with-current-buffer buffer
        (save-excursion
          (pcase insert-type
            ('replace
             (delete-region (marker-position start) (marker-position end))
             (goto-char (marker-position start)))
            ('append
             (goto-char (marker-position end))
             (setf (plist-get context :insert-start) (point))
             (insert "\n"))
            ('prepend
             (goto-char (marker-position start)))
            ('message nil))
          (setf (plist-get context :insert-marker)
                (copy-marker (point) t))
          (unless (plist-get context :insert-start)
            (setf (plist-get context :insert-start) (point)))
          (unless (eq insert-type 'message)
            (insert response))))
      (setf (plist-get context :started) t)
      (when (eq insert-type 'message)
        (setf (plist-get context :displayed-response) response)))))

(defun p3/gptel-stream-insert (response context)
  "Insert one streamed RESPONSE chunk into the target buffer."
  (when (stringp response)
    (if (not (plist-get context :started))
        (p3/gptel-stream-begin response context)
      (if (eq (plist-get context :insert-type) 'message)
          (setf (plist-get context :displayed-response)
                (concat (plist-get context :displayed-response) response))
        (with-current-buffer (plist-get context :target-buffer)
          (save-excursion
            (goto-char (plist-get context :insert-marker))
            (insert response)))))
    (when (eq (plist-get context :insert-type) 'message)
      (message "%s" (plist-get context :displayed-response)))))

(defun p3/gptel-finish-stream (context)
  "Finish a direct-to-buffer stream described by CONTEXT."
  (let ((buffer (plist-get context :target-buffer))
        (insert-type (plist-get context :insert-type))
        (insert-marker (plist-get context :insert-marker)))
    (when (and (buffer-live-p buffer) (plist-get context :started))
      (with-current-buffer buffer
        (save-excursion
          (when (eq insert-type 'prepend)
            (goto-char insert-marker)
            (insert "\n\n")))))
    (p3/gptel-cleanup-context context)
    (message "GPT task complete: %s" (plist-get context :task))))

(defun p3/gptel-abort-stream (context)
  "Roll back a partial direct-to-buffer stream described by CONTEXT."
  (let ((buffer (plist-get context :target-buffer))
        (insert-type (plist-get context :insert-type))
        (insert-start (plist-get context :insert-start))
        (insert-marker (plist-get context :insert-marker)))
    (when (and (buffer-live-p buffer) (plist-get context :started))
      (with-current-buffer buffer
        (save-excursion
          (delete-region insert-start insert-marker)
          (when (eq insert-type 'replace)
            (goto-char insert-start)
            (insert (plist-get context :original))))))
    (p3/gptel-cleanup-context context)
    (message "GPT task aborted: %s" (plist-get context :task))))

(defun p3/gptel-cleanup-context (context)
  "Release markers held by a completed or aborted GPTel CONTEXT."
  (dolist (marker (mapcar (lambda (key) (plist-get context key))
                          '(:start-marker :end-marker :insert-marker)))
    (when (markerp marker)
      (set-marker marker nil))))

(defun p3/gptel-stream-callback (response info)
  "Handle streamed RESPONSE chunks and completion for a custom task."
  (let ((context (plist-get info :context)))
    (cond
     ((stringp response)
      (p3/gptel-stream-insert response context))
     ((and (consp response) (stringp (cdr response)))
      (p3/gptel-stream-insert (cdr response) context))
     ((eq response t)
      (p3/gptel-finish-stream context))
     ((eq response 'abort)
      (p3/gptel-abort-stream context))
     ((null response)
      (p3/gptel-abort-stream context)
      (message "GPT task failed: %s"
               (or (plist-get info :status) "unknown error"))))))

(defun p3/gptel-send-task (task-type insert-type)
  "Stream TASK-TYPE directly into the target using INSERT-TYPE."
  (let* ((code (p3/gptel-task-code task-type))
         (instruction (cdr (assoc task-type p3/gptel-task-prompts))))
    (cond
     ((null code)
      (user-error "Select a region first"))
     ((p3/gptel-sensitive-buffer-p)
      (user-error "Refusing to send content from a sensitive-looking file"))
     (t
      (let* ((start-pos (if (use-region-p)
                            (region-beginning)
                          (line-beginning-position)))
             (end-pos (if (use-region-p)
                          (region-end)
                        (line-end-position)))
             (context (list :task task-type
                            :insert-type insert-type
                            :target-buffer (current-buffer)
                            :original code
                            :start-marker
                            (unless (eq insert-type 'message)
                              (copy-marker start-pos nil))
                            :end-marker
                            (unless (eq insert-type 'message)
                              (copy-marker end-pos t))
                            :started nil)))
        (gptel-request
         (format "%s\n\nLanguage/mode: %s\n\nCode:\n%s"
                 instruction major-mode code)
         :buffer (current-buffer)
         :stream t
         :context context
         :callback #'p3/gptel-stream-callback))))))

(defun p3/gptel-send-current-line ()
  "Stream a response to the current line."
  (interactive)
  (p3/gptel-send-task "Send Line" 'message))

(defun p3/gptel-write-tests ()
  "Stream tests for the region and append them after it."
  (interactive)
  (p3/gptel-send-task "Write Tests" 'append))

(defun p3/gptel-write-code ()
  "Stream replacement code for the region."
  (interactive)
  (p3/gptel-send-task "Write Code" 'replace))

(defun p3/gptel-refactor-region ()
  "Stream a refactoring and replace the region when complete."
  (interactive)
  (p3/gptel-send-task "Refactor" 'replace))

(defun p3/gptel-generate-doc ()
  "Stream documentation and prepend it to the region when complete."
  (interactive)
  (p3/gptel-send-task "Generate Documentation" 'prepend))

(defun p3/gptel-translate-code ()
  "Stream a translation and append it after the region."
  (interactive)
  (p3/gptel-send-task "Translate Code" 'append))

(defvar p3/gptel-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "l") #'p3/gptel-send-current-line)
    (define-key map (kbd "r") #'p3/gptel-refactor-region)
    (define-key map (kbd "d") #'p3/gptel-generate-doc)
    (define-key map (kbd "t") #'p3/gptel-write-tests)
    (define-key map (kbd "c") #'p3/gptel-translate-code)
    (define-key map (kbd "w") #'p3/gptel-write-code)
    map)
  "Prefix map for project-local GPTel tasks.")

(defun p3/gptel-setup ()
  "Install the global key prefix for custom GPTel tasks."
  (define-key global-map (kbd "C-c g") p3/gptel-command-map))

(provide 'p3-gptel)

;;; p3-gptel.el ends here
