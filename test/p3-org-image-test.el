;;; p3-org-image-test.el --- Tests for p3-org-image -*- lexical-binding: t; -*-

(require 'bytecomp)
(require 'cl-lib)
(require 'ert)
(require 'org)

(defconst p3-org-image-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-org-image-test--root))
(require 'p3-org-image)

(ert-deftest p3-org-image-module-owns-image-workflow ()
  (should (featurep 'p3-org-image))
  (should (commandp #'p3/org-insert-image))
  (should (keymapp p3/org-image-command-map)))

(ert-deftest p3-org-image-module-byte-compiles-cleanly ()
  (let* ((source (expand-file-name "lisp/p3-org-image.el"
                                   p3-org-image-test--root))
         (compiled (byte-compile-dest-file source))
         (byte-compile-error-on-warn t))
    (unwind-protect
        (should (byte-compile-file source))
      (when (file-exists-p compiled)
        (delete-file compiled)))))

(ert-deftest p3-org-image-layout-presets-write-native-org-attributes ()
  (dolist (case '((p3/org-image-layout-center "center" "70%")
                  (p3/org-image-layout-full "center" "100%")
                  (p3/org-image-layout-left "left" "40%")
                  (p3/org-image-layout-right "right" "40%")))
    (with-temp-buffer
      (org-mode)
      (insert "[[file:images/chart.png]]\n")
      (goto-char (point-min))
      (funcall (nth 0 case))
      (goto-char (point-min))
      (should
       (looking-at
        (regexp-quote
         (format "#+ATTR_ORG: :align %s :width %s\n"
                 (nth 1 case) (nth 2 case))))))))

(ert-deftest p3-org-image-layout-updates-existing-attributes-without-clobbering-others ()
  (with-temp-buffer
    (org-mode)
    (insert "#+CAPTION: Results\n"
            "#+ATTR_ORG: :foo keep :align left :width 25%\n"
            "[[file:images/chart.png]]\n")
    (goto-char (point-min))
    (forward-line 2)
    (p3/org-image-layout-right)
    (let ((contents (buffer-string)))
      (should (string-match-p (regexp-quote ":foo keep") contents))
      (should (string-match-p (regexp-quote ":align right") contents))
      (should (string-match-p (regexp-quote ":width 40%") contents))
      (should (= (how-many "^#\\+ATTR_ORG:" (point-min) (point-max)) 1)))))

(ert-deftest p3-org-image-layout-requires-a-standalone-image-link ()
  (with-temp-buffer
    (org-mode)
    (insert "plain text\n")
    (goto-char (point-min))
    (should-error (p3/org-image-layout-right) :type 'user-error)))

(ert-deftest p3-org-image-legacy-alignment-applies-center-and-right-overlays ()
  (dolist (case '(("center" . (space :align-to (- center (0.5 . fake-image))))
                  ("right" . (space :align-to (- right fake-image)))))
    (with-temp-buffer
      (org-mode)
      (insert (format "#+ATTR_ORG: :align %s :width 40%%\n" (car case))
              "[[file:images/chart.png]]\n")
      (goto-char (point-min))
      (forward-line 1)
      (let* ((overlay (make-overlay (line-beginning-position) (line-end-position)))
             (org-inline-image-overlays (list overlay)))
        (overlay-put overlay 'display 'fake-image)
        (cl-letf (((symbol-function 'org-version) (lambda () "9.6.15")))
          (p3/org-apply-image-layouts))
        (let ((before (overlay-get overlay 'before-string)))
          (should before)
          (should (equal (get-text-property 0 'display before)
                         (cdr case))))))))

(ert-deftest p3-org-image-command-map-exposes-insert-and-layout-actions ()
  (should (eq (lookup-key p3/org-image-command-map (kbd "i"))
              #'p3/org-insert-image))
  (should (eq (lookup-key p3/org-image-command-map (kbd "c"))
              #'p3/org-image-layout-center))
  (should (eq (lookup-key p3/org-image-command-map (kbd "f"))
              #'p3/org-image-layout-full))
  (should (eq (lookup-key p3/org-image-command-map (kbd "l"))
              #'p3/org-image-layout-left))
  (should (eq (lookup-key p3/org-image-command-map (kbd "r"))
              #'p3/org-image-layout-right)))

(ert-deftest p3-org-image-clipboard-method-uses-native-windows-helper ()
  (let ((system-type 'windows-nt))
    (should (eq (p3/org--clipboard-image-method)
                #'p3/org--save-windows-clipboard-image))))

(ert-deftest p3-org-image-clipboard-method-uses-xclip-on-x11 ()
  (let ((system-type 'gnu/linux)
        (process-environment (copy-sequence process-environment)))
    (setenv "XDG_SESSION_TYPE" "x11")
    (cl-letf (((symbol-function 'executable-find)
               (lambda (program)
                 (when (equal program "xclip") "/usr/bin/xclip"))))
      (should
       (equal (p3/org--clipboard-image-method)
              "xclip -selection clipboard -t image/png -o > %s")))))

(ert-deftest p3-org-image-insert-uses-document-local-images-directory ()
  (with-temp-buffer
    (org-mode)
    (setq buffer-file-name "/tmp/deck/talk.org"
          default-directory "/tmp/")
    (let (seen-directory seen-method seen-default-directory)
      (cl-letf (((symbol-function 'p3/org--clipboard-image-method)
                 (lambda () 'fake-clipboard-method))
                ((symbol-function 'org-download-screenshot)
                 (lambda (&optional _basename)
                   (setq seen-directory org-download-image-dir
                         seen-method org-download-screenshot-method
                         seen-default-directory default-directory))))
        (p3/org-insert-image)
        (should (equal seen-directory "images"))
        (should (eq seen-method 'fake-clipboard-method))
        (should (equal seen-default-directory "/tmp/deck/"))))))

(ert-deftest p3-org-image-insert-requires-a-saved-org-buffer ()
  (with-temp-buffer
    (org-mode)
    (should-error (p3/org-insert-image) :type 'user-error)))

(ert-deftest p3-org-image-windows-clipboard-helper-uses-powershell-sta-and-escapes-path ()
  (let (seen-program seen-args)
    (cl-letf (((symbol-function 'executable-find)
               (lambda (program)
                 (when (equal program "powershell.exe")
                   "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")))
              ((symbol-function 'call-process)
               (lambda (program _infile _destination _display &rest args)
                 (setq seen-program program
                       seen-args args)
                 0)))
      (p3/org--save-windows-clipboard-image "C:/tmp/a'b.png")
      (should (string-suffix-p "powershell.exe" seen-program))
      (should (member "-STA" seen-args))
      (should
       (string-match-p
        (regexp-quote "C:/tmp/a''b.png")
        (car (last seen-args)))))))

(provide 'p3-org-image-test)

;;; p3-org-image-test.el ends here
