;;; p3-pptx-spike-test.el --- Tests for PPTX visual-layout spike -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-pptx-spike-test--config-directory
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(load-file
 (expand-file-name "spikes/pptx-editor/p3-pptx-spike.el"
                   p3-pptx-spike-test--config-directory))

(defun p3-pptx-spike-test--shape ()
  "Return one editable shape suitable for latency tests."
  '((id . 7)
    (name . "Test shape")
    (type . "pic")
    (left . 1.0)
    (top . 2.0)
    (width . 3.0)
    (height . 1.0)))

(ert-deftest p3-pptx-spike-edit-previews-immediately-without-sync-render ()
  (with-temp-buffer
    (setq-local p3-pptx-spike--working "/tmp/working.pptx"
                p3-pptx-spike--slide 1
                p3-pptx-spike--selected-id 7
                p3-pptx-spike--model
                `((slide_width . 10.0)
                  (slide_height . 7.5)
                  (shapes . (,(p3-pptx-spike-test--shape)))))
    (let ((bridge-called nil)
          (render-called nil)
          (render-scheduled nil)
          (redisplayed nil))
      (cl-letf (((symbol-function 'p3-pptx-spike--run)
                 (lambda (&rest _args) (setq bridge-called t) ""))
                ((symbol-function 'p3-pptx-spike--render)
                 (lambda () (setq render-called t)))
                ((symbol-function 'p3-pptx-spike--schedule-render)
                 (lambda () (setq render-scheduled t)))
                ((symbol-function 'p3-pptx-spike--redisplay)
                 (lambda () (setq redisplayed t))))
        (p3-pptx-spike--edit 0.5 -0.25)
        (let ((shape (car (alist-get 'shapes p3-pptx-spike--model))))
          (should (= (alist-get 'left shape) 1.5))
          (should (= (alist-get 'top shape) 1.75)))
        (should bridge-called)
        (should redisplayed)
        (should render-scheduled)
        (should-not render-called)))))

(ert-deftest p3-pptx-spike-render-snapshot-is-complete-before-use ()
  (let ((directory (make-temp-file "p3-pptx-spike-test-" t)))
    (unwind-protect
        (let ((working (expand-file-name "working.pptx" directory)))
          (with-temp-file working
            (insert "complete-pptx-snapshot"))
          (with-temp-buffer
            (setq-local p3-pptx-spike--working working
                        p3-pptx-spike--temp-directory directory)
            (let ((snapshot (p3-pptx-spike--make-render-snapshot 3)))
              (should (file-exists-p snapshot))
              (with-temp-buffer
                (insert-file-contents-literally snapshot)
                (should (equal (buffer-string) "complete-pptx-snapshot"))))))
      (delete-directory directory t))))

(provide 'p3-pptx-spike-test)

;;; p3-pptx-spike-test.el ends here
