;;; p3-pptx-spike.el --- Throwaway PPTX visual-layout feasibility spike -*- lexical-binding: t; -*-

;; This is intentionally a spike, not a supported package.  It edits a working
;; copy of a PPTX by patching only one slide XML member, then renders that real
;; PPTX through LibreOffice for display in Emacs.

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

(defvar-local p3-pptx-spike--source nil)
(defvar-local p3-pptx-spike--working nil)
(defvar-local p3-pptx-spike--temp-directory nil)
(defvar-local p3-pptx-spike--slide 1)
(defvar-local p3-pptx-spike--model nil)
(defvar-local p3-pptx-spike--selected-id nil)
(defvar-local p3-pptx-spike--render-file nil)

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
  "Render the current real PPTX slide to PNG and refresh geometry."
  (p3-pptx-spike--program p3-pptx-spike-soffice "LibreOffice")
  (p3-pptx-spike--program p3-pptx-spike-pdftoppm "pdftoppm")
  (p3-pptx-spike--run
   "render" p3-pptx-spike--working p3-pptx-spike--render-file
   "--slide" (number-to-string p3-pptx-spike--slide)
   "--soffice" p3-pptx-spike-soffice
   "--pdftoppm" p3-pptx-spike-pdftoppm)
  (p3-pptx-spike--inspect)
  (p3-pptx-spike--redisplay))

(defun p3-pptx-spike--get (key object)
  "Return KEY from JSON alist OBJECT."
  (alist-get key object))

(defun p3-pptx-spike--canvas-size ()
  "Return displayed canvas size as (WIDTH . HEIGHT)."
  (let* ((slide-width (p3-pptx-spike--get 'slide_width p3-pptx-spike--model))
         (slide-height (p3-pptx-spike--get 'slide_height p3-pptx-spike--model))
         (width p3-pptx-spike-canvas-width))
    (cons width (round (* width (/ slide-height slide-width))))))

(defun p3-pptx-spike--shape-rect (shape)
  "Return SHAPE rectangle in displayed canvas pixels."
  (pcase-let* ((`(,canvas-width . ,canvas-height) (p3-pptx-spike--canvas-size))
               (slide-width (p3-pptx-spike--get 'slide_width p3-pptx-spike--model))
               (slide-height (p3-pptx-spike--get 'slide_height p3-pptx-spike--model))
               (sx (/ canvas-width slide-width))
               (sy (/ canvas-height slide-height))
               (x (round (* sx (p3-pptx-spike--get 'left shape))))
               (y (round (* sy (p3-pptx-spike--get 'top shape))))
               (w (round (* sx (p3-pptx-spike--get 'width shape))))
               (h (round (* sy (p3-pptx-spike--get 'height shape)))))
    (list x y w h)))

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
  (if-let ((shape (seq-find
                   (lambda (item)
                     (= (p3-pptx-spike--get 'id item) p3-pptx-spike--selected-id))
                   (p3-pptx-spike--get 'shapes p3-pptx-spike--model))))
      (format "%s (#%s)"
              (or (p3-pptx-spike--get 'name shape) "shape")
              p3-pptx-spike--selected-id)
    "none"))

(defun p3-pptx-spike--redisplay ()
  "Redraw the rendered slide plus editable bounding boxes."
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
    (insert (format "\n\nSlide %d  |  selected: %s\n"
                    p3-pptx-spike--slide (p3-pptx-spike--selection-label)))
    (insert "Drag a shape to move it. Arrow keys nudge the selected shape.  s saves a copy; g rerenders; q quits.\n")
    (goto-char (point-min))))

(defun p3-pptx-spike--event-xy (position)
  "Return image-relative pixel coordinates for mouse POSITION."
  (or (posn-object-x-y position)
      (user-error "Mouse event is not over the slide image")))

(defun p3-pptx-spike-select-mouse (event)
  "Select the PPTX shape under mouse EVENT."
  (interactive "e")
  (pcase-let* ((`(,x . ,y) (p3-pptx-spike--event-xy (event-start event)))
               (shape (p3-pptx-spike--shape-at x y)))
    (when shape
      (setq p3-pptx-spike--selected-id (p3-pptx-spike--get 'id shape))
      (p3-pptx-spike--redisplay))))

(defun p3-pptx-spike-drag-mouse (event)
  "Move the PPTX shape dragged by mouse EVENT, then rerender the real deck."
  (interactive "e")
  (pcase-let* ((start (p3-pptx-spike--event-xy (event-start event)))
               (end (p3-pptx-spike--event-xy (event-end event)))
               (`(,x0 . ,y0) start)
               (`(,x1 . ,y1) end)
               (shape (p3-pptx-spike--shape-at x0 y0))
               (canvas (p3-pptx-spike--canvas-size))
               (slide-width (p3-pptx-spike--get 'slide_width p3-pptx-spike--model))
               (slide-height (p3-pptx-spike--get 'slide_height p3-pptx-spike--model)))
    (unless shape
      (user-error "No editable PPTX shape at drag start"))
    (setq p3-pptx-spike--selected-id (p3-pptx-spike--get 'id shape))
    (p3-pptx-spike--edit
     (* (- x1 x0) (/ slide-width (car canvas)))
     (* (- y1 y0) (/ slide-height (cdr canvas))))))

(defun p3-pptx-spike--edit (dx dy &optional dw dh)
  "Patch selected shape by DX/DY and optional DW/DH inches, then rerender."
  (unless p3-pptx-spike--selected-id
    (user-error "No PPTX shape is selected"))
  (p3-pptx-spike--run
   "edit" p3-pptx-spike--working
   "--slide" (number-to-string p3-pptx-spike--slide)
   "--shape-id" (number-to-string p3-pptx-spike--selected-id)
   "--dx" (number-to-string dx)
   "--dy" (number-to-string dy)
   "--dw" (number-to-string (or dw 0.0))
   "--dh" (number-to-string (or dh 0.0)))
  (p3-pptx-spike--render))

(defun p3-pptx-spike-nudge-left () (interactive) (p3-pptx-spike--edit (- p3-pptx-spike-nudge) 0))
(defun p3-pptx-spike-nudge-right () (interactive) (p3-pptx-spike--edit p3-pptx-spike-nudge 0))
(defun p3-pptx-spike-nudge-up () (interactive) (p3-pptx-spike--edit 0 (- p3-pptx-spike-nudge)))
(defun p3-pptx-spike-nudge-down () (interactive) (p3-pptx-spike--edit 0 p3-pptx-spike-nudge))

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
  "Rerender the current working deck."
  (interactive)
  (p3-pptx-spike--render))

(defun p3-pptx-spike-quit ()
  "Kill the spike buffer and its disposable working directory."
  (interactive)
  (let ((directory p3-pptx-spike--temp-directory))
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
    (define-key map [pptx-shape drag-mouse-1] #'p3-pptx-spike-drag-mouse)
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
                p3-pptx-spike--selected-id nil)
    (p3-pptx-spike--render)))

(provide 'p3-pptx-spike)

;;; p3-pptx-spike.el ends here
