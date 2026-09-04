;;; p3-pptx-spike.el --- Throwaway PPTX visual-layout feasibility spike -*- lexical-binding: t; -*-

;; This is intentionally a spike, not a supported package.  It edits a working
;; copy of a PPTX by patching only one slide XML member.  LibreOffice provides
;; fidelity renders, while Emacs provides immediate local movement feedback.

(require 'json)
(require 'svg)
(require 'subr-x)

(defgroup p3-pptx-spike nil
  "Feasibility spike for visually positioning PPTX shapes from Emacs."
  :group 'applications)

(defconst p3-pptx-spike--module-directory
  (file-name-directory (or load-file-name buffer-file-name default-directory)))

(defcustom p3-pptx-spike-python "python3"
  "Python executable used by the spike."
  :type 'string
  :group 'p3-pptx-spike)

(defcustom p3-pptx-spike-soffice "libreoffice"
  "LibreOffice/soffice executable used to render PPTX files."
  :type 'string
  :group 'p3-pptx-spike)

(defcustom p3-pptx-spike-pdftoppm "pdftoppm"
  "pdftoppm executable used to rasterize one rendered slide."
  :type 'string
  :group 'p3-pptx-spike)

(defcustom p3-pptx-spike-bridge
  (expand-file-name "pptx_bridge.py" p3-pptx-spike--module-directory)
  "Path to the Python OOXML bridge used by this spike."
  :type 'file
  :group 'p3-pptx-spike)

(defcustom p3-pptx-spike-canvas-width 1100
  "Width in pixels of the slide canvas displayed in Emacs."
  :type 'integer
  :group 'p3-pptx-spike)

(defcustom p3-pptx-spike-nudge 0.05
  "Keyboard nudge distance in inches."
  :type 'number
  :group 'p3-pptx-spike)

(defcustom p3-pptx-spike-render-delay 0.45
  "Seconds of editing idle time before starting a fidelity render."
  :type 'number
  :group 'p3-pptx-spike)

(defvar-local p3-pptx-spike--source nil)
(defvar-local p3-pptx-spike--working nil)
(defvar-local p3-pptx-spike--temp-directory nil)
(defvar-local p3-pptx-spike--slide 1)
(defvar-local p3-pptx-spike--model nil)
(defvar-local p3-pptx-spike--render-model nil)
(defvar-local p3-pptx-spike--selected-id nil)
(defvar-local p3-pptx-spike--render-file nil)
(defvar-local p3-pptx-spike--render-timer nil)
(defvar-local p3-pptx-spike--render-process nil)
(defvar-local p3-pptx-spike--edit-generation 0)
(defvar-local p3-pptx-spike--drag-delta nil)

(defun p3-pptx-spike--program (program label)
  "Return executable PROGRAM or signal a user error mentioning LABEL."
  (or (executable-find program)
      (user-error "%s executable not found: %s" label program)))

(defun p3-pptx-spike--run (&rest args)
  "Run the bridge with ARGS and return stdout as a string."
  (unless (file-readable-p p3-pptx-spike-bridge)
    (user-error "PPTX bridge is not readable: %s" p3-pptx-spike-bridge))
  (let ((python (p3-pptx-spike--program p3-pptx-spike-python "Python")))
    (with-temp-buffer
      (let ((status (apply #'process-file python nil (current-buffer) nil
                           p3-pptx-spike-bridge args)))
        (unless (and (integerp status) (zerop status))
          (user-error "PPTX bridge failed: %s" (string-trim (buffer-string))))
        (buffer-string)))))

(defun p3-pptx-spike--inspect ()
  "Refresh the in-memory geometry model for the working deck."
  (setq p3-pptx-spike--model
        (json-parse-string
         (p3-pptx-spike--run
          "inspect" p3-pptx-spike--working
          "--slide" (number-to-string p3-pptx-spike--slide))
         :object-type 'alist :array-type 'list
         :null-object nil :false-object nil)))

(defun p3-pptx-spike--render ()
  "Synchronously render the current PPTX slide for initial display only."
  (p3-pptx-spike--program p3-pptx-spike-soffice "LibreOffice")
  (p3-pptx-spike--program p3-pptx-spike-pdftoppm "pdftoppm")
  (p3-pptx-spike--run
   "render" p3-pptx-spike--working p3-pptx-spike--render-file
   "--slide" (number-to-string p3-pptx-spike--slide)
   "--soffice" p3-pptx-spike-soffice
   "--pdftoppm" p3-pptx-spike-pdftoppm)
  (p3-pptx-spike--inspect)
  (setq p3-pptx-spike--render-model (copy-tree p3-pptx-spike--model))
  (p3-pptx-spike--redisplay))

(defun p3-pptx-spike--get (key object)
  "Return KEY from JSON alist OBJECT."
  (alist-get key object))

(defun p3-pptx-spike--shape-by-id (id &optional model)
  "Return shape ID from MODEL, defaulting to the current geometry model."
  (seq-find
   (lambda (shape) (= (p3-pptx-spike--get 'id shape) id))
   (p3-pptx-spike--get 'shapes (or model p3-pptx-spike--model))))

(defun p3-pptx-spike--canvas-size ()
  "Return displayed canvas size as (WIDTH . HEIGHT)."
  (let* ((slide-width (p3-pptx-spike--get 'slide_width p3-pptx-spike--model))
         (slide-height (p3-pptx-spike--get 'slide_height p3-pptx-spike--model))
         (width p3-pptx-spike-canvas-width))
    (cons width (round (* width (/ slide-height slide-width))))))

(defun p3-pptx-spike--shape-rect-in-model (shape model)
  "Return SHAPE rectangle in canvas pixels using MODEL dimensions."
  (pcase-let* ((`(,canvas-width . ,canvas-height) (p3-pptx-spike--canvas-size))
               (slide-width (p3-pptx-spike--get 'slide_width model))
               (slide-height (p3-pptx-spike--get 'slide_height model))
               (sx (/ canvas-width slide-width))
               (sy (/ canvas-height slide-height))
               (x (round (* sx (p3-pptx-spike--get 'left shape))))
               (y (round (* sy (p3-pptx-spike--get 'top shape))))
               (w (round (* sx (p3-pptx-spike--get 'width shape))))
               (h (round (* sy (p3-pptx-spike--get 'height shape)))))
    (list x y w h)))

(defun p3-pptx-spike--shape-rect (shape)
  "Return SHAPE rectangle in displayed canvas pixels."
  (p3-pptx-spike--shape-rect-in-model shape p3-pptx-spike--model))

(defun p3-pptx-spike--shape-at (x y)
  "Return top-most editable shape at canvas coordinates X Y."
  (seq-find
   (lambda (shape)
     (pcase-let ((`(,sx ,sy ,sw ,sh) (p3-pptx-spike--shape-rect shape)))
       (and (<= sx x (+ sx sw)) (<= sy y (+ sy sh)))))
   (reverse (p3-pptx-spike--get 'shapes p3-pptx-spike--model))))

(defun p3-pptx-spike--image-map ()
  "Build one Emacs image-map hotspot per editable shape."
  (mapcar
   (lambda (shape)
     (pcase-let* ((`(,x ,y ,w ,h) (p3-pptx-spike--shape-rect shape))
                  (name (p3-pptx-spike--get 'name shape)))
       (list (cons 'rect (cons (cons x y) (cons (+ x w) (+ y h))))
             'pptx-shape
             (list 'help-echo (if (string-empty-p name) "PPTX shape" name)
                   'pointer 'hand))))
   (p3-pptx-spike--get 'shapes p3-pptx-spike--model)))

(defun p3-pptx-spike--selection-label ()
  "Return a short label for the current selection."
  (if-let ((shape (and p3-pptx-spike--selected-id
                       (p3-pptx-spike--shape-by-id p3-pptx-spike--selected-id))))
      (format "%s (#%s)  x %.2f  y %.2f"
              (or (p3-pptx-spike--get 'name shape) "shape")
              p3-pptx-spike--selected-id
              (p3-pptx-spike--get 'left shape)
              (p3-pptx-spike--get 'top shape))
    "none"))

(defun p3-pptx-spike--draw-preview-ghost (svg shape width height normal)
  "Draw a live raster movement preview for SHAPE onto SVG.
WIDTH and HEIGHT are canvas dimensions; NORMAL is the old-position outline."
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
          (svg-embed svg p3-pptx-spike--render-file "image/png" nil
                     :x dx :y dy :width width :height height
                     :clip-path (format "url(#%s)" clip-id)
                     :opacity 0.78)
          (svg-rectangle svg old-x old-y old-w old-h
                         :fill-color "none"
                         :stroke-color normal
                         :stroke-width 1
                         :stroke-dasharray "6 4"))))))

(defun p3-pptx-spike--redisplay ()
  "Redraw the authoritative slide raster plus live geometry feedback."
  (let* ((inhibit-read-only t)
         (size (p3-pptx-spike--canvas-size))
         (width (car size))
         (height (cdr size))
         (svg (svg-create width height))
         (normal (face-foreground 'shadow nil t))
         (selected (face-foreground 'font-lock-keyword-face nil t)))
    (erase-buffer)
    (svg-embed svg p3-pptx-spike--render-file "image/png" nil
               :x 0 :y 0 :width width :height height)
    (dolist (shape (p3-pptx-spike--get 'shapes p3-pptx-spike--model))
      (p3-pptx-spike--draw-preview-ghost svg shape width height normal))
    (dolist (shape (p3-pptx-spike--get 'shapes p3-pptx-spike--model))
      (pcase-let ((`(,x ,y ,w ,h) (p3-pptx-spike--shape-rect shape)))
        (svg-rectangle
         svg x y w h
         :fill-color "none"
         :stroke-color (if (equal (p3-pptx-spike--get 'id shape)
                                  p3-pptx-spike--selected-id)
                           selected normal)
         :stroke-width (if (equal (p3-pptx-spike--get 'id shape)
                                  p3-pptx-spike--selected-id)
                           3 1))))
    (insert-image
     (svg-image svg :scale 1.0 :map (p3-pptx-spike--image-map)))
    (insert (format "\n\nSlide %d  |  selected: %s"
                    p3-pptx-spike--slide (p3-pptx-spike--selection-label)))
    (when p3-pptx-spike--drag-delta
      (insert (format "  |  drag Δx %+.2f Δy %+.2f in"
                      (car p3-pptx-spike--drag-delta)
                      (cdr p3-pptx-spike--drag-delta))))
    (insert "\nDrag and arrow keys preview immediately. Fidelity rendering updates after editing pauses; g requests it now; s saves; q quits.\n")
    (goto-char (point-min))))

(defun p3-pptx-spike--event-xy (position)
  "Return image-relative pixel coordinates for mouse POSITION."
  (or (posn-object-x-y position)
      (user-error "Mouse event is not over the slide image")))

(defun p3-pptx-spike--event-xy-safe (position)
  "Return image-relative coordinates for POSITION, or nil off the image."
  (condition-case nil
      (p3-pptx-spike--event-xy position)
    (user-error nil)))

(defun p3-pptx-spike--slide-delta (x0 y0 x1 y1)
  "Convert canvas displacement X0/Y0 to X1/Y1 into slide inches."
  (let* ((canvas (p3-pptx-spike--canvas-size))
         (slide-width (p3-pptx-spike--get 'slide_width p3-pptx-spike--model))
         (slide-height (p3-pptx-spike--get 'slide_height p3-pptx-spike--model)))
    (cons (* (- x1 x0) (/ slide-width (car canvas)))
          (* (- y1 y0) (/ slide-height (cdr canvas))))))

(defun p3-pptx-spike--set-shape-position (shape left top)
  "Set SHAPE LEFT and TOP in the live model."
  (setf (alist-get 'left shape) left
        (alist-get 'top shape) top))

(defun p3-pptx-spike-select-mouse (event)
  "Select the PPTX shape under mouse EVENT."
  (interactive "e")
  (pcase-let* ((`(,x . ,y) (p3-pptx-spike--event-xy (event-start event)))
               (shape (p3-pptx-spike--shape-at x y)))
    (when shape
      (setq p3-pptx-spike--selected-id (p3-pptx-spike--get 'id shape))
      (p3-pptx-spike--redisplay))))

(defun p3-pptx-spike--commit-edit (dx dy &optional dw dh model-already-updated)
  "Commit selected shape DX/DY and optional DW/DH inches to OOXML.
When MODEL-ALREADY-UPDATED is non-nil, only persist and schedule fidelity
rendering; otherwise update the live geometry model after persistence."
  (unless p3-pptx-spike--selected-id
    (user-error "No PPTX shape is selected"))
  (let ((shape (p3-pptx-spike--shape-by-id p3-pptx-spike--selected-id)))
    (unless shape
      (user-error "Selected PPTX shape no longer exists"))
    (p3-pptx-spike--run
     "edit" p3-pptx-spike--working
     "--slide" (number-to-string p3-pptx-spike--slide)
     "--shape-id" (number-to-string p3-pptx-spike--selected-id)
     "--dx" (number-to-string dx)
     "--dy" (number-to-string dy)
     "--dw" (number-to-string (or dw 0.0))
     "--dh" (number-to-string (or dh 0.0)))
    (unless model-already-updated
      (setf (alist-get 'left shape) (+ (p3-pptx-spike--get 'left shape) dx)
            (alist-get 'top shape) (+ (p3-pptx-spike--get 'top shape) dy)
            (alist-get 'width shape) (+ (p3-pptx-spike--get 'width shape) (or dw 0.0))
            (alist-get 'height shape) (+ (p3-pptx-spike--get 'height shape) (or dh 0.0))))
    (setq p3-pptx-spike--edit-generation (1+ p3-pptx-spike--edit-generation))
    (p3-pptx-spike--redisplay)
    (p3-pptx-spike--schedule-render)))

(defun p3-pptx-spike--edit (dx dy &optional dw dh)
  "Immediately preview and persist selected shape DX/DY and optional DW/DH."
  (p3-pptx-spike--commit-edit dx dy dw dh nil))

(defun p3-pptx-spike-drag-mouse (event)
  "Track mouse EVENT continuously, preview movement, and commit on release."
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
      (p3-pptx-spike--redisplay)
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
                    (p3-pptx-spike--set-shape-position shape (+ left0 dx) (+ top0 dy))
                    (p3-pptx-spike--redisplay)))))
             ((eq (event-basic-type next) 'mouse-1)
              (when-let ((xy (p3-pptx-spike--event-xy-safe (event-end next))))
                (pcase-let ((`(,end-x . ,end-y) xy))
                  (pcase-let ((`(,end-dx . ,end-dy)
                               (p3-pptx-spike--slide-delta x0 y0 end-x end-y)))
                    (setq dx end-dx dy end-dy)
                    (p3-pptx-spike--set-shape-position shape (+ left0 dx) (+ top0 dy)))))
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
        (p3-pptx-spike--redisplay))
       ((and (= dx 0.0) (= dy 0.0))
        (p3-pptx-spike--redisplay))
       (t
        (condition-case err
            (p3-pptx-spike--commit-edit dx dy nil nil t)
          (error
           (p3-pptx-spike--set-shape-position shape left0 top0)
           (p3-pptx-spike--redisplay)
           (signal (car err) (cdr err)))))))))

(defun p3-pptx-spike--render-command (input output)
  "Return asynchronous bridge command rendering INPUT to OUTPUT."
  (unless (file-readable-p p3-pptx-spike-bridge)
    (user-error "PPTX bridge is not readable: %s" p3-pptx-spike-bridge))
  (list (p3-pptx-spike--program p3-pptx-spike-python "Python")
        p3-pptx-spike-bridge
        "render" input output
        "--slide" (number-to-string p3-pptx-spike--slide)
        "--soffice" (p3-pptx-spike--program p3-pptx-spike-soffice "LibreOffice")
        "--pdftoppm" (p3-pptx-spike--program p3-pptx-spike-pdftoppm "pdftoppm")))

(defun p3-pptx-spike--render-timer-fire (buffer)
  "Start a fidelity render for BUFFER when its debounce timer fires."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq p3-pptx-spike--render-timer nil)
      (p3-pptx-spike--start-render))))

(defun p3-pptx-spike--schedule-render (&optional delay)
  "Debounce an asynchronous fidelity render by DELAY seconds."
  (when (timerp p3-pptx-spike--render-timer)
    (cancel-timer p3-pptx-spike--render-timer))
  (setq p3-pptx-spike--render-timer
        (run-with-timer (or delay p3-pptx-spike-render-delay) nil
                        #'p3-pptx-spike--render-timer-fire
                        (current-buffer))))

(defun p3-pptx-spike--render-sentinel (process _event)
  "Install a completed fidelity render from PROCESS when it is still current."
  (when (memq (process-status process) '(exit signal))
    (let ((editor (process-get process 'editor-buffer))
          (generation (process-get process 'generation))
          (output (process-get process 'output))
          (snapshot (process-get process 'snapshot))
          (model (process-get process 'model))
          (process-buffer (process-buffer process))
          (status (process-exit-status process)))
      (when (buffer-live-p editor)
        (with-current-buffer editor
          (when (eq process p3-pptx-spike--render-process)
            (setq p3-pptx-spike--render-process nil))
          (cond
           ((and (= status 0) (= generation p3-pptx-spike--edit-generation))
            (setq p3-pptx-spike--render-file output
                  p3-pptx-spike--render-model model)
            (p3-pptx-spike--redisplay))
           ((not (= status 0))
            (let ((diagnostics
                   (when (buffer-live-p process-buffer)
                     (with-current-buffer process-buffer
                       (string-trim (buffer-string))))))
              (message "PPTX fidelity render failed: %s"
                       (if (string-empty-p (or diagnostics ""))
                           (format "status %s" status)
                         diagnostics)))))
          (when (> p3-pptx-spike--edit-generation generation)
            (p3-pptx-spike--schedule-render 0.0))))
      (when (and snapshot (file-exists-p snapshot))
        (delete-file snapshot))
      (unless (and (= status 0)
                   (buffer-live-p editor)
                   (with-current-buffer editor
                     (= generation p3-pptx-spike--edit-generation)))
        (when (and output (file-exists-p output))
          (delete-file output)))
      (when (buffer-live-p process-buffer)
        (kill-buffer process-buffer)))))

(defun p3-pptx-spike--make-render-snapshot (generation)
  "Copy the working deck to a complete render snapshot for GENERATION."
  (let ((snapshot
         (make-temp-file
          (expand-file-name (format "render-%d-" generation)
                            p3-pptx-spike--temp-directory)
          nil ".pptx")))
    (copy-file p3-pptx-spike--working snapshot t)
    snapshot))

(defun p3-pptx-spike--start-render ()
  "Start one nonblocking fidelity render of the current working deck."
  (if (and p3-pptx-spike--render-process
           (process-live-p p3-pptx-spike--render-process))
      nil
    (let* ((generation p3-pptx-spike--edit-generation)
           (snapshot (p3-pptx-spike--make-render-snapshot generation))
           (output (concat (file-name-sans-extension snapshot) ".png"))
           (model (copy-tree p3-pptx-spike--model))
           (process-buffer (generate-new-buffer " *p3-pptx-render*"))
           (process
            (make-process
             :name (format "p3-pptx-render-%d" generation)
             :buffer process-buffer
             :command (p3-pptx-spike--render-command snapshot output)
             :connection-type 'pipe
             :noquery t
             :sentinel #'p3-pptx-spike--render-sentinel)))
      (process-put process 'editor-buffer (current-buffer))
      (process-put process 'generation generation)
      (process-put process 'output output)
      (process-put process 'snapshot snapshot)
      (process-put process 'model model)
      (setq p3-pptx-spike--render-process process))))

(defun p3-pptx-spike-nudge-left ()
  (interactive)
  (p3-pptx-spike--edit (- p3-pptx-spike-nudge) 0))

(defun p3-pptx-spike-nudge-right ()
  (interactive)
  (p3-pptx-spike--edit p3-pptx-spike-nudge 0))

(defun p3-pptx-spike-nudge-up ()
  (interactive)
  (p3-pptx-spike--edit 0 (- p3-pptx-spike-nudge)))

(defun p3-pptx-spike-nudge-down ()
  (interactive)
  (p3-pptx-spike--edit 0 p3-pptx-spike-nudge))

(defun p3-pptx-spike-save-as (output)
  "Save the edited working PPTX as OUTPUT without modifying the source file."
  (interactive
   (list (read-file-name "Save edited PPTX as: "
                         (file-name-directory p3-pptx-spike--source)
                         nil nil
                         (concat (file-name-base p3-pptx-spike--source)
                                 "-edited.pptx"))))
  (copy-file p3-pptx-spike--working output t)
  (message "Saved edited PPTX to %s" output))

(defun p3-pptx-spike-refresh ()
  "Request an immediate nonblocking fidelity render of the working deck."
  (interactive)
  (p3-pptx-spike--schedule-render 0.0)
  (message "PPTX fidelity render requested"))

(defun p3-pptx-spike--cancel-background-work ()
  "Cancel timers and rendering owned by the current spike buffer."
  (when (timerp p3-pptx-spike--render-timer)
    (cancel-timer p3-pptx-spike--render-timer)
    (setq p3-pptx-spike--render-timer nil))
  (when (and p3-pptx-spike--render-process
             (process-live-p p3-pptx-spike--render-process))
    (let ((process-buffer (process-buffer p3-pptx-spike--render-process)))
      (set-process-sentinel p3-pptx-spike--render-process #'ignore)
      (delete-process p3-pptx-spike--render-process)
      (when (buffer-live-p process-buffer)
        (kill-buffer process-buffer))))
  (setq p3-pptx-spike--render-process nil))

(defun p3-pptx-spike-quit ()
  "Kill the spike buffer and its disposable working directory."
  (interactive)
  (let ((directory p3-pptx-spike--temp-directory))
    (p3-pptx-spike--cancel-background-work)
    (kill-buffer (current-buffer))
    (when (and directory (file-directory-p directory))
      (delete-directory directory t))))

(defvar p3-pptx-spike-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "<left>") #'p3-pptx-spike-nudge-left)
    (define-key map (kbd "<right>") #'p3-pptx-spike-nudge-right)
    (define-key map (kbd "<up>") #'p3-pptx-spike-nudge-up)
    (define-key map (kbd "<down>") #'p3-pptx-spike-nudge-down)
    (define-key map (kbd "g") #'p3-pptx-spike-refresh)
    (define-key map (kbd "s") #'p3-pptx-spike-save-as)
    (define-key map (kbd "q") #'p3-pptx-spike-quit)
    (define-key map [pptx-shape mouse-1] #'p3-pptx-spike-select-mouse)
    (define-key map [pptx-shape down-mouse-1] #'p3-pptx-spike-drag-mouse)
    map)
  "Keymap for `p3-pptx-spike-mode'.")

(define-derived-mode p3-pptx-spike-mode special-mode "PPTX-Spike"
  "Throwaway visual positioning mode for real PPTX shapes."
  (setq-local truncate-lines t))

;;;###autoload
(defun p3/pptx-spike-open (pptx slide)
  "Open PPTX at SLIDE in the visual-layout feasibility spike.
The source is never modified; edits are made to a temporary working copy."
  (interactive
   (list (read-file-name "PPTX file: " nil nil t nil
                         (lambda (file)
                           (or (file-directory-p file)
                               (string-equal (downcase (or (file-name-extension file) ""))
                                             "pptx"))))
         (read-number "Slide number: " 1)))
  (unless (file-readable-p pptx)
    (user-error "PPTX is not readable: %s" pptx))
  (let* ((source (expand-file-name pptx))
         (directory (make-temp-file "p3-pptx-spike-" t))
         (working (expand-file-name "working.pptx" directory))
         (render (expand-file-name "slide.png" directory))
         (buffer (get-buffer-create
                  (format "*PPTX spike: %s [%d]*" (file-name-nondirectory source) slide))))
    (copy-file source working t)
    (pop-to-buffer buffer)
    (p3-pptx-spike-mode)
    (setq-local p3-pptx-spike--source source
                p3-pptx-spike--working working
                p3-pptx-spike--temp-directory directory
                p3-pptx-spike--slide slide
                p3-pptx-spike--render-file render
                p3-pptx-spike--render-model nil
                p3-pptx-spike--render-timer nil
                p3-pptx-spike--render-process nil
                p3-pptx-spike--edit-generation 0
                p3-pptx-spike--drag-delta nil
                p3-pptx-spike--selected-id nil)
    (p3-pptx-spike--render)))

(provide 'p3-pptx-spike)

;;; p3-pptx-spike.el ends here
