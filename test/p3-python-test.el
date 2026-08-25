;;; p3-python-test.el --- Tests for p3-python -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-python-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-python-test--root))

(require 'p3-core)
(require 'p3-python)

(defmacro p3-python-test--with-temp-project (binding &rest body)
  "Bind BINDING to a temporary project directory while evaluating BODY."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,binding (make-temp-file "p3-python-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,binding t))))

(defun p3-python-test--make-executable (path)
  "Create an executable file at PATH."
  (make-directory (file-name-directory path) t)
  (with-temp-file path
    (insert "#!/bin/sh\n"))
  (set-file-modes path #o755)
  path)

(ert-deftest p3-python-project-interpreter-prefers-dot-venv ()
  (p3-python-test--with-temp-project root
    (let* ((dot-venv (p3-python-test--make-executable
                      (expand-file-name ".venv/bin/python" root)))
           (_venv (p3-python-test--make-executable
                   (expand-file-name "venv/bin/python" root))))
      (let ((system-type 'gnu/linux))
        (cl-letf (((symbol-function 'project-current)
                   (lambda (&optional _maybe-prompt _directory) 'fake-project))
                  ((symbol-function 'project-root)
                   (lambda (_project) root)))
          (should (equal (p3/python-project-interpreter) dot-venv)))))))

(ert-deftest p3-python-project-interpreter-preserves-project-el-root ()
  "Python environment lookup should retain its pre-refactor project.el scope."
  (p3-python-test--with-temp-project project-root-directory
    (p3-python-test--with-temp-project projectile-root-directory
      (let ((project-interpreter
             (p3-python-test--make-executable
              (expand-file-name ".venv/bin/python" project-root-directory)))
            (_projectile-interpreter
             (p3-python-test--make-executable
              (expand-file-name ".venv/bin/python" projectile-root-directory)))
            (system-type 'gnu/linux))
        (cl-letf (((symbol-function 'project-current)
                   (lambda (&optional _maybe-prompt _directory) 'fake-project))
                  ((symbol-function 'project-root)
                   (lambda (_project) project-root-directory))
                  ((symbol-function 'p3/project-root)
                   (lambda () projectile-root-directory)))
          (should (equal (p3/python-project-interpreter)
                         project-interpreter)))))))

(ert-deftest p3-python-setup-project-interpreter-is-buffer-local ()
  (p3-python-test--with-temp-project root
    (let ((interpreter (p3-python-test--make-executable
                        (expand-file-name ".venv/bin/python" root))))
      (with-temp-buffer
        (let ((system-type 'gnu/linux))
          (cl-letf (((symbol-function 'project-current)
                     (lambda (&optional _maybe-prompt _directory) 'fake-project))
                    ((symbol-function 'project-root)
                     (lambda (_project) root)))
            (p3/python-setup-project-interpreter)
            (should (local-variable-p 'python-shell-interpreter))
            (should (equal python-shell-interpreter interpreter))
            (should (equal python-shell-virtualenv-root
                           (file-name-as-directory
                            (expand-file-name ".venv" root))))))))))

(ert-deftest p3-python-project-interpreter-supports-windows-venv-layout ()
  (p3-python-test--with-temp-project root
    (let ((interpreter (p3-python-test--make-executable
                        (expand-file-name ".venv/Scripts/python.exe" root)))
          (system-type 'windows-nt))
      (cl-letf (((symbol-function 'project-current)
                 (lambda (&optional _maybe-prompt _directory) 'fake-project))
                ((symbol-function 'project-root)
                 (lambda (_project) root)))
        (should (equal (p3/python-project-interpreter) interpreter))))))

(ert-deftest p3-python-tools-path-is-platform-specific ()
  (let ((user-emacs-directory "/tmp/p3-emacs/"))
    (let ((system-type 'gnu/linux))
      (should (equal (p3/python-tools-path "bin/basedpyright-langserver")
                     "/tmp/p3-emacs/python-tools/linux/bin/basedpyright-langserver")))
    (let ((system-type 'windows-nt))
      (should (equal (p3/python-tools-path "Scripts/basedpyright-langserver.exe")
                     "/tmp/p3-emacs/python-tools/windows/Scripts/basedpyright-langserver.exe")))))

(ert-deftest p3-python-language-server-reuses-installed-server ()
  (p3-python-test--with-temp-project tools
    (let* ((system-type 'gnu/linux)
           (server (p3-python-test--make-executable
                    (expand-file-name "bin/basedpyright-langserver" tools))))
      (cl-letf (((symbol-function 'p3/python-tools-path)
                 (lambda (file) (expand-file-name file tools)))
                ((symbol-function 'call-process)
                 (lambda (&rest _args)
                   (ert-fail "Existing language server should not bootstrap"))))
        (should (equal (p3/python-ensure-language-server) server))))))

(ert-deftest p3-python-disable-flycheck-is-safe-without-flycheck ()
  (with-temp-buffer
    (let ((flycheck-mode nil))
      (p3/python-disable-flycheck)
      (should-not flycheck-mode))))

(provide 'p3-python-test)

;;; p3-python-test.el ends here
