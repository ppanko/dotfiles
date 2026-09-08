;;; p3-platform-gnupg-review-test.el --- Review regressions for GnuPG boundary -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-platform-gnupg-review-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path
             (expand-file-name "lisp" p3-platform-gnupg-review-test--root))

(require 'p3-platform)

(ert-deftest p3-platform-gnupg-normalizer-is-domain-specific ()
  (should (fboundp 'p3/windows-normalize-gnupg-path))
  (should-not (fboundp 'p3/windows-to-msys-path))
  (should (equal (p3/windows-normalize-gnupg-path
                  "C:\\Users\\Pavel\\.emacs.d\\elpa\\gnupg")
                 "/c/users/pavel/.emacs.d/elpa/gnupg")))

(ert-deftest p3-platform-gnupg-configurator-is-noop-off-windows ()
  (let ((was-bound (boundp 'package-gnupghome-dir))
        (old-value (and (boundp 'package-gnupghome-dir)
                        (symbol-value 'package-gnupghome-dir))))
    (unwind-protect
        (progn
          (set 'package-gnupghome-dir "unchanged")
          (cl-letf (((symbol-function 'p3/windows-p) (lambda () nil)))
            (p3/windows-configure-gnupg))
          (should (equal (symbol-value 'package-gnupghome-dir) "unchanged")))
      (if was-bound
          (set 'package-gnupghome-dir old-value)
        (makunbound 'package-gnupghome-dir)))))

(provide 'p3-platform-gnupg-review-test)

;;; p3-platform-gnupg-review-test.el ends here
