;;; p3-r-language-server-test.el --- Managed R language-server tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'seq)

(defconst p3-r-language-server-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(add-to-list 'load-path (expand-file-name "lisp" p3-r-language-server-test--root))
(require 'p3-r-language-server)

(ert-deftest p3-r-managed-tool-process-isolates-r-libraries ()
  (let ((process-environment (copy-sequence process-environment))
        captured)
    (setenv "R_LIBS" "/global/libs")
    (setenv "R_LIBS_USER" "/user/libs")
    (setenv "R_LIBS_SITE" "/site/libs")
    (cl-letf (((symbol-function 'call-process)
               (lambda (_program _input _destination _display &rest args)
                 (setq captured
                       (list (getenv "R_LIBS")
                             (getenv "R_LIBS_USER")
                             (getenv "R_LIBS_SITE")
                             args))
                 0)))
      (should
       (zerop
        (p3/r-call-managed-tool-process
         "/opt/R/bin/R" "/tmp/p3 tools/library/" nil nil "cat('ok')"))))
    (should
     (equal (seq-take captured 3)
            '("/tmp/p3 tools/library" "NULL" "NULL")))
    (should (member "--vanilla" (nth 3 captured)))
    (should (equal (getenv "R_LIBS") "/global/libs"))
    (should (equal (getenv "R_LIBS_USER") "/user/libs"))
    (should (equal (getenv "R_LIBS_SITE") "/site/libs"))))

(ert-deftest p3-r-language-server-probe-uses-isolated-runner ()
  (let (captured)
    (cl-letf (((symbol-function 'p3/r-call-managed-tool-process)
               (lambda (program library destination display expression)
                 (setq captured
                       (list program library destination display expression))
                 0)))
      (should
       (p3/r-language-server-installed-p
        "/opt/R/bin/R" "/tmp/p3-r-tools/library/")))
    (should
     (equal (seq-take captured 4)
            '("/opt/R/bin/R" "/tmp/p3-r-tools/library/" nil nil)))
    (should (string-match-p "loadNamespace" (nth 4 captured)))
    (should (string-match-p "lib.loc=" (nth 4 captured)))))

(ert-deftest p3-r-language-server-install-uses-isolated-runner-and-dependencies ()
  (let ((library (make-temp-file "p3-r-ls-test-" t))
        captured)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/r-call-managed-tool-process)
                   (lambda (program lib destination display expression)
                     (setq captured
                           (list program lib destination display expression))
                     0))
                  ((symbol-function 'p3/r-language-server-installed-p)
                   (lambda (_program _library) t)))
          (should (p3/r-install-language-server "/opt/R/bin/R" library)))
      (delete-directory library t))
    (should (equal (nth 0 captured) "/opt/R/bin/R"))
    (should (equal (nth 1 captured) library))
    (should (bufferp (nth 2 captured)))
    (should (eq (nth 3 captured) t))
    (should (string-match-p "install.packages" (nth 4 captured)))
    (should (string-match-p "dependencies=NA" (nth 4 captured)))))

(provide 'p3-r-language-server-test)

;;; p3-r-language-server-test.el ends here
