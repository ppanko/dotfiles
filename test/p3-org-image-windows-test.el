;;; p3-org-image-windows-test.el --- Windows Org image clipboard tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defconst p3-org-image-windows-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-org-image-windows-test--root))
(require 'p3-org-image)

(defun p3-org-image-windows-test--powershell ()
  "Return the PowerShell executable used by the Windows image tests."
  (or (executable-find "powershell.exe")
      (executable-find "powershell")))

(defun p3-org-image-windows-test--ps-quote (path)
  "Return PATH escaped for a single-quoted PowerShell string."
  (replace-regexp-in-string "'" "''" (expand-file-name path) t t))

(ert-deftest p3-org-image-windows-helper-disposes-images-in-finally ()
  (let (seen-script)
    (cl-letf (((symbol-function 'executable-find)
               (lambda (program)
                 (when (equal program "powershell.exe")
                   "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")))
              ((symbol-function 'call-process)
               (lambda (_program _infile _destination _display &rest args)
                 (setq seen-script (car (last args)))
                 0)))
      (p3/org--save-windows-clipboard-image "C:/tmp/pasted.png")
      (should (string-match-p
               (regexp-quote "finally { $image.Dispose() }")
               seen-script))
      (should (string-match-p
               (regexp-quote
                "finally { if ($null -ne $fileImage) { $fileImage.Dispose() } }")
               seen-script)))))

(ert-deftest p3-org-image-windows-filedrop-clipboard-roundtrip ()
  (skip-unless (eq system-type 'windows-nt))
  (let ((powershell (p3-org-image-windows-test--powershell)))
    (skip-unless powershell)
    (let* ((directory (make-temp-file "p3-org-image-clipboard-" t))
           (source (expand-file-name "source.png" directory))
           (destination (expand-file-name "destination.png" directory))
           (source-ps (p3-org-image-windows-test--ps-quote source))
           (destination-ps (p3-org-image-windows-test--ps-quote destination))
           (setup-script
            (format
             (concat
              "Add-Type -AssemblyName System.Windows.Forms; "
              "Add-Type -AssemblyName System.Drawing; "
              "$bitmap = New-Object System.Drawing.Bitmap -ArgumentList 2,2; "
              "try { "
              "$bitmap.SetPixel(0, 0, [System.Drawing.Color]::Red); "
              "$bitmap.Save('%s', [System.Drawing.Imaging.ImageFormat]::Png) "
              "} finally { $bitmap.Dispose() }; "
              "$files = New-Object System.Collections.Specialized.StringCollection; "
              "[void]$files.Add('%s'); "
              "[System.Windows.Forms.Clipboard]::SetFileDropList($files)")
             source-ps source-ps))
           (verify-script
            (format
             (concat
              "Add-Type -AssemblyName System.Drawing; "
              "$image = $null; $status = 0; "
              "try { "
              "$image = [System.Drawing.Image]::FromFile('%s'); "
              "if (($image.Width -ne 2) -or ($image.Height -ne 2)) { $status = 5 } "
              "} catch { $status = 4 } "
              "finally { if ($null -ne $image) { $image.Dispose() } }; "
              "exit $status")
             destination-ps)))
      (unwind-protect
          (progn
            (should
             (zerop
              (call-process powershell nil nil nil
                            "-NoProfile" "-STA" "-NonInteractive"
                            "-Command" setup-script)))
            (p3/org--save-windows-clipboard-image destination)
            (should (file-exists-p destination))
            (should (> (file-attribute-size (file-attributes destination)) 0))
            (should
             (zerop
              (call-process powershell nil nil nil
                            "-NoProfile" "-STA" "-NonInteractive"
                            "-Command" verify-script))))
        (delete-directory directory t)))))

(provide 'p3-org-image-windows-test)

;;; p3-org-image-windows-test.el ends here
