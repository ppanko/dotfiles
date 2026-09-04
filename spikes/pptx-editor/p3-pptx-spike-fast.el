;;; p3-pptx-spike-fast.el --- Nonblocking interaction layer for PPTX spike -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'dom)
(require 'seq)
(require 'svg)

(defconst p3-pptx-spike-fast--module-directory
  (file-name-directory
   (or load-file-name byte-compile-current-file buffer-file-name default-directory)))

(add-to-list 'load-path p3-pptx-spike-fast--module-directory)
(require 'p3-pptx-spike)

(defcustom p3-pptx-spike-persist-delay 0.20
  "Seconds of editing idle time before persisting geometry to the working PPTX."
  :type 'number
  :group 'p3-pptx-spike)

(defcustom p3-pptx-spike-preview-frame-rate 30.0
  "Maximum live-preview redraw rate in frames per second."
  :type 'number
  :group 'p3-pptx-spike)

(defvar-local p3-pptx-spike--pending-edits nil)
(defvar-local p3-pptx-spike--persist-timer nil)
(defvar-local p3-pptx-spike--persist-process nil)
(defvar-local p3-pptx-spike--persist-error nil)
(defvar-local p3-pptx-spike--preview-timer nil)
(defvar-local p3-pptx-spike--preview-last-draw nil)

(defalias 'p3-pptx-spike-fast--original-start-render
  (symbol-function 'p3-pptx-spike--start-render))
(defalias 'p3-pptx-spike-fast--original-cancel-background-work
  (symbol-function 'p3-pptx-spike--cancel-background-work))

(defun p3-pptx-spike--ensure-fast-state ()
  "Initialize buffer-local state used by the nonblocking interaction layer."
  (unless (hash-table-p p3-pptx-spike--pending-edits)
    (setq p3-pptx-spike--pending-edits (make-hash-table :test #'eql))))

(defun p3-pptx-spike--pending-count ()
  "Return the number of shapes with unpersisted geometry edits."
  (p3-pptx-spike--ensure-fast-state)
  (hash-table-count p3-pptx-spike--pending-edits))

(defun p3-pptx-spike--accumulate-pending (shape-id dx dy &optional dw dh)
  "Accumulate SHAPE-ID geometry delta DX/DY and optional DW/DH in memory."
  (p3-pptx-spike--ensure-fast-state)
  (let ((current (gethash shape-id p3-pptx-spike--pending-edits)))
    (puthash
     shape-id
     (list :dx (+ (or (plist-get current :dx) 0.0) dx)
           :dy (+ (or (plist-get current :dy) 0.0) dy)
           :dw (+ (or (plist-get current :dw) 0.0) (or dw 0.0))
           :dh (+ (or (plist-get current :dh) 0.0) (or dh 0.0)))
     p3-pptx-spike--pending-edits)))

(defun p3-pptx-spike--preview-timer-fire (buffer)
  "Redraw BUFFER once when a coalesced preview timer fires."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq p3-pptx-spike--preview-timer nil
            p3-pptx-spike--preview-last-draw (float-time))
      (p3-pptx-spike--redisplay))))

(defun p3-pptx-spike--request-preview (&optional force)
  "Request a live preview redraw, capped by the configured frame rate.
With FORCE, redraw immediately."
  (let* ((now (float-time))
         (interval (/ 1.0 (max 1.0 p3-pptx-spike-preview-frame-rate)))
         (last (or p3-pptx-spike--preview-last-draw 0.0))
         (elapsed (- now last)))
    (cond
     ((or force (>= elapsed interval))
      (when (timerp p3-pptx-spike--preview-timer)
        (cancel-timer p3-pptx-spike--preview-timer)
        (setq p3-pptx-spike--preview-timer nil))
      (setq p3-pptx-spike--preview-last-draw now)
      (p3-pptx-spike--redisplay))
     ((not (timerp p3-pptx-spike--preview-timer))
      (setq p3-pptx-spike--preview-timer
            (run-with-timer
             (max 0.001 (- interval elapsed)) nil
             #'p3-pptx-spike--preview-timer-fire (current-buffer)))))))

(defun p3-pptx-spike--commit-edit (dx dy &optional dw dh model-already-updated)
  "Apply selected-shape DX/DY and optional DW/DH to the live model only.
The resulting delta is queued for asynchronous persistence.  When
MODEL-ALREADY-UPDATED is non-nil, the live model is not changed again."
  (unless p3-pptx-spike--selected-id
    (user-error "No PPTX shape is selected"))
  (let ((shape (p3-pptx-spike--shape-by-id p3-pptx-spike--selected-id)))
    (unless shape
      (user-error "Selected PPTX shape no longer exists"))
    (unless model-already-updated
      (setf (alist-get 'left shape) (+ (p3-pptx-spike--get 'left shape) dx)
            (alist-get 'top shape) (+ (p3-pptx-spike--get 'top shape) dy)
            (alist-get 'width shape)
            (+ (p3-pptx-spike--get 'width shape) (or dw 0.0))
            (alist-get 'height shape)
            (+ (p3-pptx-spike--get 'height shape) (or dh 0.0))))
    (p3-pptx-spike--accumulate-pending
     p3-pptx-spike--selected-id dx dy dw dh)
    (setq p3-pptx-spike--edit-generation
          (1+ p3-pptx-spike--edit-generation))
    (p3-pptx-spike--request-preview)
    (p3-pptx-spike--schedule-persist)))

(defun p3-pptx-spike--edit (dx dy &optional dw dh)
  "Preview selected-shape DX/DY and optional DW/DH without process or file I/O."
  (p3-pptx-spike--commit-edit dx dy dw dh nil))

(defun p3-pptx-spike--persist-command (shape-id edit)
  "Return an asynchronous bridge command for SHAPE-ID and accumulated EDIT."
  (unless (file-readable-p p3-pptx-spike-bridge)
    (user-error "PPTX bridge is not readable: %s" p3-pptx-spike-bridge))
  (list (p3-pptx-spike--program p3-pptx-spike-python "Python")
        p3-pptx-spike-bridge
        "edit" p3-pptx-spike--working
        "--slide" (number-to-string p3-pptx-spike--slide)
        "--shape-id" (number-to-string shape-id)
        "--dx" (number-to-string (plist-get edit :dx))
        "--dy" (number-to-string (plist-get edit :dy))
        "--dw" (number-to-string (plist-get edit :dw))
        "--dh" (number-to-string (plist-get edit :dh))))

(defun p3-pptx-spike--take-pending-edit ()
  "Remove and return one pending edit as (SHAPE-ID . EDIT), or nil."
  (p3-pptx-spike--ensure-fast-state)
  (let (item)
    (maphash
     (lambda (shape-id edit)
       (unless item
         (setq item (cons shape-id edit))))
     p3-pptx-spike--pending-edits)
    (when item
      (remhash (car item) p3-pptx-spike--pending-edits))
    item))

(defun p3-pptx-spike--persist-timer-fire (buffer)
  "Begin deferred persistence for BUFFER when its idle timer fires."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq p3-pptx-spike--persist-timer nil)
      (p3-pptx-spike--start-persist))))

(defun p3-pptx-spike--schedule-persist (&optional delay)
  "Debounce persistence of accumulated edits by DELAY seconds."
  (when (timerp p3-pptx-spike--persist-timer)
    (cancel-timer p3-pptx-spike--persist-timer))
  (setq p3-pptx-spike--persist-timer
        (run-with-timer
         (or delay p3-pptx-spike-persist-delay) nil
         #'p3-pptx-spike--persist-timer-fire (current-buffer))))

(defun p3-pptx-spike--persist-sentinel (process _event)
  "Continue the persistence queue when PROCESS finishes."
  (when (memq (process-status process) '(exit signal))
    (let ((editor (process-get process 'editor-buffer))
          (shape-id (process-get process 'shape-id))
          (edit (process-get process 'edit))
          (process-buffer (process-buffer process))
          (status (process-exit-status process)))
      (when (buffer-live-p editor)
        (with-current-buffer editor
          (when (eq process p3-pptx-spike--persist-process)
            (setq p3-pptx-spike--persist-process nil))
          (if (= status 0)
              (progn
                (setq p3-pptx-spike--persist-error nil)
                (if (> (p3-pptx-spike--pending-count) 0)
                    (p3-pptx-spike--start-persist)
                  (p3-pptx-spike--schedule-render 0.0)))
            (p3-pptx-spike--accumulate-pending
             shape-id
             (plist-get edit :dx) (plist-get edit :dy)
             (plist-get edit :dw) (plist-get edit :dh))
            (setq p3-pptx-spike--persist-error
                  (when (buffer-live-p process-buffer)
                    (with-current-buffer process-buffer
                      (string-trim (buffer-string)))))
            (message "PPTX persistence failed: %s"
                     (or p3-pptx-spike--persist-error
                         (format "status %s" status))))))
      (when (buffer-live-p process-buffer)
        (kill-buffer process-buffer)))))

(defun p3-pptx-spike--start-persist ()
  "Start one asynchronous persistence operation if one is needed."
  (p3-pptx-spike--ensure-fast-state)
  (unless (and p3-pptx-spike--persist-process
               (process-live-p p3-pptx-spike--persist-process))
    (when-let ((item (p3-pptx-spike--take-pending-edit)))
      (let* ((shape-id (car item))
             (edit (cdr item))
             (process-buffer (generate-new-buffer " *p3-pptx-persist*"))
             (process
              (make-process
               :name (format "p3-pptx-persist-%s" shape-id)
               :buffer process-buffer
               :command (p3-pptx-spike--persist-command shape-id edit)
               :connection-type 'pipe
               :noquery t
               :sentinel nil)))
        (process-put process 'editor-buffer (current-buffer))
        (process-put process 'shape-id shape-id)
        (process-put process 'edit edit)
        (setq p3-pptx-spike--persist-process process)
        (set-process-sentinel process #'p3-pptx-spike--persist-sentinel)))))

(defun p3-pptx-spike--persistence-busy-p ()
  "Return non-nil when memory edits have not fully reached the working PPTX."
  (or (> (p3-pptx-spike--pending-count) 0)
      (and p3-pptx-spike--persist-process
           (process-live-p p3-pptx-spike--persist-process))))

(defun p3-pptx-spike--start-render ()
  "Start fidelity rendering only after all queued geometry has been persisted."
  (if (p3-pptx-spike--persistence-busy-p)
      (p3-pptx-spike--schedule-persist 0.0)
    (p3-pptx-spike-fast--original-start-render)))

(defun p3-pptx-spike--flush-persistence ()
  "Synchronously drain pending persistence for explicit save operations only."
  (when (timerp p3-pptx-spike--persist-timer)
    (cancel-timer p3-pptx-spike--persist-timer)
    (setq p3-pptx-spike--persist-timer nil))
  (setq p3-pptx-spike--persist-error nil)
  (let ((iterations 0))
    (while (and (< iterations 100)
                (or (p3-pptx-spike--persistence-busy-p)
                    (> (p3-pptx-spike--pending-count) 0)))
      (setq iterations (1+ iterations))
      (unless (and p3-pptx-spike--persist-process
                   (process-live-p p3-pptx-spike--persist-process))
        (p3-pptx-spike--start-persist))
      (when (and p3-pptx-spike--persist-process
                 (process-live-p p3-pptx-spike--persist-process))
        (accept-process-output p3-pptx-spike--persist-process 0.1))
      (when p3-pptx-spike--persist-error
        (user-error "PPTX persistence failed: %s" p3-pptx-spike--persist-error)))
    (when (p3-pptx-spike--persistence-busy-p)
      (user-error "PPTX persistence did not finish"))))

(defun p3-pptx-spike--canvas-image-map ()
  "Return one whole-canvas image map used for mouse selection and dragging."
  (pcase-let ((`(,width . ,height) (p3-pptx-spike--canvas-size)))
    (list
     (list (cons 'rect (cons (cons 0 0) (cons width height)))
           'pptx-canvas
           (list 'help-echo "PPTX slide canvas" 'pointer 'hand)))))

(defun p3-pptx-spike--draw-fast-preview-ghost (svg shape width height normal)
  "Draw SHAPE from the existing raster by reusing its single SVG image node."
  (when-let* ((render-model p3-pptx-spike--render-model)
              (render-shape
               (p3-pptx-spike--shape-by-id
                (p3-pptx-spike--get 'id shape) render-model)))
    (pcase-let* ((`(,x ,y ,w ,h) (p3-pptx-spike--shape-rect shape))
                 (`(,old-x ,old-y ,old-w ,old-h)
                  (p3-pptx-spike--shape-rect-in-model render-shape render-model))
                 (dx (- x old-x))
                 (dy (- y old-y)))
      (unless (and (= dx 0) (= dy 0) (= w old-w) (= h old-h))
        (let* ((clip-id (format "pptx-preview-%s" (p3-pptx-spike--get 'id shape)))
               (clip (svg-clip-path svg :id clip-id)))
          (svg-rectangle clip x y w h)
          (svg-use svg "pptx-slide-raster"
                   :x dx :y dy
                   :clip-path (format "url(#%s)" clip-id)
                   :opacity 0.78)
          (svg-rectangle svg old-x old-y old-w old-h
                         :fill-color "none"
                         :stroke-color normal
                         :stroke-width 1
                         :stroke-dasharray "6 4"))))))

(defun p3-pptx-spike--redisplay ()
  "Redraw using an external raster reference instead of base64-embedding PNG data."
  (let* ((inhibit-read-only t)
         (size (p3-pptx-spike--canvas-size))
         (width (car size))
         (height (cdr size))
         (svg (svg-create width height))
         (normal (face-foreground 'shadow nil t))
         (selected (face-foreground 'font-lock-keyword-face nil t))
         (base-uri (expand-file-name "canvas.svg" p3-pptx-spike--temp-directory))
         (render-name (file-name-nondirectory p3-pptx-spike--render-file)))
    (erase-buffer)
    (svg-embed-base-uri-image
     svg render-name
     :id "pptx-slide-raster"
     :x 0 :y 0 :width width :height height)
    (dolist (shape (p3-pptx-spike--get 'shapes p3-pptx-spike--model))
      (p3-pptx-spike--draw-fast-preview-ghost svg shape width height normal))
    (dolist (shape (p3-pptx-spike--get 'shapes p3-pptx-spike--model))
      (pcase-let ((`(,x ,y ,w ,h) (p3-pptx-spike--shape-rect shape)))
        (svg-rectangle
         svg x y w h
         :fill-color "none"
         :stroke-color
         (if (equal (p3-pptx-spike--get 'id shape) p3-pptx-spike--selected-id)
             selected normal)
         :stroke-width
         (if (equal (p3-pptx-spike--get 'id shape) p3-pptx-spike--selected-id)
             3 1))))
    (insert-image
     (svg-image svg
                :scale 1.0
                :base-uri base-uri
                :map (p3-pptx-spike--canvas-image-map)))
    (insert (format "\n\nSlide %d  |  selected: %s"
                    p3-pptx-spike--slide
                    (p3-pptx-spike--selection-label)))
    (when p3-pptx-spike--drag-delta
      (insert (format "  |  drag Δx %+.2f Δy %+.2f in"
                      (car p3-pptx-spike--drag-delta)
                      (cdr p3-pptx-spike--drag-delta))))
    (when (> (p3-pptx-spike--pending-count) 0)
      (insert (format "  |  %d pending" (p3-pptx-spike--pending-count))))
    (insert "\nInteraction is memory-only; PPTX persistence and fidelity rendering happen after editing pauses.  s saves; g refreshes; q quits.\n")
    (goto-char (point-min))))

(defun p3-pptx-spike-select-mouse (event)
  "Select the PPTX shape under mouse EVENT without rebuilding shape image maps."
  (interactive "e")
  (pcase-let* ((`(,x . ,y) (p3-pptx-spike--event-xy (event-start event)))
               (shape (p3-pptx-spike--shape-at x y)))
    (when shape
      (setq p3-pptx-spike--selected-id (p3-pptx-spike--get 'id shape))
      (p3-pptx-spike--request-preview t))))

(defun p3-pptx-spike-drag-mouse (event)
  "Track EVENT in memory, coalescing redraws and persisting only after release."
  (interactive "e")
  (pcase-let* ((`(,x0 . ,y0) (p3-pptx-spike--event-xy (event-start event)))
               (shape (p3-pptx-spike--shape-at x0 y0)))
    (unless shape
      (user-error "No editable PPTX shape at drag start"))
    (setq p3-pptx-spike--selected-id (p3-pptx-spike--get 'id shape))
    (let ((left0 (p3-pptx-spike--get 'left shape))
          (top0 (p3-pptx-spike--get 'top shape))
          (dx 0.0)
          (dy 0.0)
          (finished nil)
          (cancelled nil))
      (p3-pptx-spike--request-preview t)
      (track-mouse
        (while (not finished)
          (let ((next (read-event)))
            (cond
             ((mouse-movement-p next)
              (when-let ((xy (p3-pptx-spike--event-xy-safe (event-start next))))
                (pcase-let ((`(,next-x . ,next-y) xy))
                  (pcase-let ((`(,next-dx . ,next-dy)
                               (p3-pptx-spike--slide-delta x0 y0 next-x next-y)))
                    (setq dx next-dx
                          dy next-dy
                          p3-pptx-spike--drag-delta (cons dx dy))
                    (p3-pptx-spike--set-shape-position
                     shape (+ left0 dx) (+ top0 dy))
                    (p3-pptx-spike--request-preview)))))
             ((eq (event-basic-type next) 'mouse-1)
              (when-let ((xy (p3-pptx-spike--event-xy-safe (event-end next))))
                (pcase-let ((`(,end-x . ,end-y) xy))
                  (pcase-let ((`(,end-dx . ,end-dy)
                               (p3-pptx-spike--slide-delta x0 y0 end-x end-y)))
                    (setq dx end-dx dy end-dy)
                    (p3-pptx-spike--set-shape-position
                     shape (+ left0 dx) (+ top0 dy)))))
              (setq finished t))
             (t
              (setq cancelled t
                    finished t
                    unread-command-events
                    (append unread-command-events (list next))))))))
      (setq p3-pptx-spike--drag-delta nil)
      (cond
       (cancelled
        (p3-pptx-spike--set-shape-position shape left0 top0)
        (p3-pptx-spike--request-preview t))
       ((and (= dx 0.0) (= dy 0.0))
        (p3-pptx-spike--request-preview t))
       (t
        (p3-pptx-spike--commit-edit dx dy nil nil t)
        (p3-pptx-spike--request-preview t))))))

(defun p3-pptx-spike-save-as (output)
  "Persist queued geometry, then save the edited working PPTX as OUTPUT."
  (interactive
   (list (read-file-name "Save edited PPTX as: "
                         (file-name-directory p3-pptx-spike--source)
                         nil nil
                         (concat (file-name-base p3-pptx-spike--source)
                                 "-edited.pptx"))))
  (p3-pptx-spike--flush-persistence)
  (copy-file p3-pptx-spike--working output t)
  (message "Saved edited PPTX to %s" output))

(defun p3-pptx-spike-refresh ()
  "Persist queued edits and request fidelity rendering without blocking interaction."
  (interactive)
  (if (p3-pptx-spike--persistence-busy-p)
      (p3-pptx-spike--schedule-persist 0.0)
    (p3-pptx-spike--schedule-render 0.0))
  (message "PPTX fidelity refresh queued"))

(defun p3-pptx-spike--cancel-background-work ()
  "Cancel preview, persistence, and fidelity-render background work."
  (p3-pptx-spike-fast--original-cancel-background-work)
  (when (timerp p3-pptx-spike--preview-timer)
    (cancel-timer p3-pptx-spike--preview-timer)
    (setq p3-pptx-spike--preview-timer nil))
  (when (timerp p3-pptx-spike--persist-timer)
    (cancel-timer p3-pptx-spike--persist-timer)
    (setq p3-pptx-spike--persist-timer nil))
  (when (and p3-pptx-spike--persist-process
             (process-live-p p3-pptx-spike--persist-process))
    (let ((process-buffer (process-buffer p3-pptx-spike--persist-process)))
      (set-process-sentinel p3-pptx-spike--persist-process #'ignore)
      (delete-process p3-pptx-spike--persist-process)
      (when (buffer-live-p process-buffer)
        (kill-buffer process-buffer))))
  (setq p3-pptx-spike--persist-process nil))

(define-key p3-pptx-spike-mode-map [pptx-canvas mouse-1]
            #'p3-pptx-spike-select-mouse)
(define-key p3-pptx-spike-mode-map [pptx-canvas down-mouse-1]
            #'p3-pptx-spike-drag-mouse)

(provide 'p3-pptx-spike-fast)

;;; p3-pptx-spike-fast.el ends here
