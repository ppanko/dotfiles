;;; p3-org-export-test.el --- Tests for p3-org-export -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)

(defconst p3-org-export-test--config-directory
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path
             (expand-file-name "lisp" p3-org-export-test--config-directory))

(require 'p3-org-export)

(defmacro p3-org-export-test--with-temp-directory (binding &rest body)
  "Bind BINDING to a temporary directory while evaluating BODY."
  (declare (indent 1) (debug (symbolp body)))
  `(let ((,binding (make-temp-file "p3-org-export-test-" t)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,binding t))))

(defun p3-org-export-test--contents (path)
  "Return the contents of PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(defun p3-org-export-test--write-bibliography (path)
  "Write a minimal BibTeX bibliography to PATH."
  (with-temp-file path
    (insert
     "@article{doe2020,\n"
     "  author = {Doe, Jane},\n"
     "  title = {Example Article},\n"
     "  journal = {Example Journal},\n"
     "  year = {2020}\n"
     "}\n")))

(defun p3-org-export-test--write-png (path)
  "Write a tiny valid PNG image to PATH."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert
     (base64-decode-string
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII="))
    (let ((coding-system-for-write 'binary))
      (write-region (point-min) (point-max) path nil 'silent))))

(defun p3-org-export-test--python-executable ()
  "Return a Python executable suitable for DOCX package inspection."
  (or (executable-find "python3")
      (executable-find "python")))

(defun p3-org-export-test--zip-member-contents (archive member)
  "Return MEMBER contents from ZIP ARCHIVE as UTF-8 text."
  (with-temp-buffer
    (let ((status
           (call-process
            (p3-org-export-test--python-executable)
            nil (current-buffer) nil
            "-c"
            (concat
             "import sys, zipfile; "
             "sys.stdout.write(zipfile.ZipFile(sys.argv[1]).read(sys.argv[2]).decode('utf-8'))")
            archive member)))
      (unless (and (integerp status) (zerop status))
        (error "Could not read %s from %s: %s"
               member archive (buffer-string)))
      (buffer-string))))

(defun p3-org-export-test--zip-members (archive)
  "Return member names from ZIP ARCHIVE."
  (with-temp-buffer
    (let ((status
           (call-process
            (p3-org-export-test--python-executable)
            nil (current-buffer) nil
            "-c"
            (concat
             "import sys, zipfile; "
             "sys.stdout.write('\\n'.join(zipfile.ZipFile(sys.argv[1]).namelist()))")
            archive)))
      (unless (and (integerp status) (zerop status))
        (error "Could not list %s: %s" archive (buffer-string)))
      (split-string (buffer-string) "\n" t))))

(defun p3-org-export-test--customize-reference-docx (path)
  "Customize PATH outside Pandoc to simulate an external Word template."
  (let ((script (make-temp-file "p3-org-export-reference-" nil ".py")))
    (unwind-protect
        (progn
          (with-temp-file script
            (insert
             "import os, sys, tempfile, zipfile\n"
             "import xml.etree.ElementTree as ET\n"
             "path = sys.argv[1]\n"
             "w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'\n"
             "ET.register_namespace('w', w)\n"
             "with zipfile.ZipFile(path, 'r') as zin:\n"
             "    files = {name: zin.read(name) for name in zin.namelist()}\n"
             "styles = ET.fromstring(files['word/styles.xml'])\n"
             "heading = next(s for s in styles.findall('{%s}style' % w) if s.get('{%s}styleId' % w) == 'Heading1')\n"
             "rpr = heading.find('{%s}rPr' % w)\n"
             "if rpr is None:\n"
             "    rpr = ET.SubElement(heading, '{%s}rPr' % w)\n"
             "fonts = rpr.find('{%s}rFonts' % w)\n"
             "if fonts is None:\n"
             "    fonts = ET.SubElement(rpr, '{%s}rFonts' % w)\n"
             "fonts.set('{%s}ascii' % w, 'Courier New')\n"
             "fonts.set('{%s}hAnsi' % w, 'Courier New')\n"
             "files['word/styles.xml'] = ET.tostring(styles, encoding='utf-8', xml_declaration=True)\n"
             "document = ET.fromstring(files['word/document.xml'])\n"
             "margin = document.find('.//{%s}sectPr/{%s}pgMar' % (w, w))\n"
             "margin.set('{%s}top' % w, '1008')\n"
             "files['word/document.xml'] = ET.tostring(document, encoding='utf-8', xml_declaration=True)\n"
             "fd, tmp = tempfile.mkstemp(suffix='.docx')\n"
             "os.close(fd)\n"
             "try:\n"
             "    with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as zout:\n"
             "        for name, data in files.items():\n"
             "            zout.writestr(name, data)\n"
             "    os.replace(tmp, path)\n"
             "finally:\n"
             "    if os.path.exists(tmp): os.unlink(tmp)\n"))
          (let ((status
                 (call-process
                  (p3-org-export-test--python-executable)
                  nil nil nil script path)))
            (unless (and (integerp status) (zerop status))
              (error "Could not customize reference DOCX"))))
      (delete-file script))))

(defun p3-org-export-test--zip-file-p (path)
  "Return non-nil when PATH starts with the ZIP file signature."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally path nil 0 2)
    (equal (buffer-string) "PK")))

(ert-deftest p3-org-export-profiles-preserve-office-and-add-markdown ()
  (dolist (profile '(docx gfm pptx))
    (should (p3-org-export--profile profile)))
  (should (equal (plist-get (p3-org-export--profile 'gfm) :extension) "md"))
  (should (equal (plist-get (p3-org-export--profile 'gfm) :format) "gfm")))

(ert-deftest p3-org-export-output-file-respects-export-file-name ()
  (p3-org-export-test--with-temp-directory directory
    (with-temp-buffer
      (setq buffer-file-name (expand-file-name "notes.org" directory)
            default-directory directory)
      (insert "#+EXPORT_FILE_NAME: final-report\n\n* Heading\n")
      (org-mode)
      (should
       (equal (p3-org-export--output-file 'gfm)
              (expand-file-name "final-report.md" directory))))))

(ert-deftest p3-org-export-gfm-arguments-preserve-metadata-and-disable-wrapping ()
  (let ((source "/tmp/report.org")
        (output "/tmp/report.md"))
    (should
     (equal
      (p3-org-export--arguments 'gfm source output nil)
      (list "--from=org" "--to=gfm" "--standalone" "--wrap=none"
            source "-o" output)))))

(ert-deftest p3-org-export-docx-arguments-use-reference-document ()
  (let ((source "/tmp/report.org")
        (output "/tmp/report.docx")
        (reference "/tmp/reference.docx"))
    (should
     (equal
      (p3-org-export--arguments 'docx source output reference)
      (list "--from=org" "--to=docx" "--fail-if-warnings"
            source "-o" output
            "--reference-doc=/tmp/reference.docx")))))

(ert-deftest p3-org-export-reference-defaults-are-profile-specific ()
  (let ((p3-org-export-reference-docx "/tmp/reference.docx")
        (p3-org-export-reference-pptx "/tmp/reference.pptx"))
    (should (equal (p3-org-export--default-reference 'docx)
                   "/tmp/reference.docx"))
    (should (equal (p3-org-export--default-reference 'pptx)
                   "/tmp/reference.pptx"))
    (should-not (p3-org-export--default-reference 'gfm))))

(ert-deftest p3-org-export-citations-use-global-bibliography ()
  (p3-org-export-test--with-temp-directory directory
    (let ((bibliography (expand-file-name "references.bib" directory)))
      (p3-org-export-test--write-bibliography bibliography)
      (with-temp-buffer
        (setq default-directory directory)
        (insert "A claim [cite:@doe2020].\n")
        (org-mode)
        (let ((org-cite-global-bibliography (list bibliography)))
          (should
           (equal (p3-org-export--citation-arguments)
                  (list "--citeproc"
                        (concat "--bibliography=" bibliography)))))))))

(ert-deftest p3-org-export-local-and-global-bibliographies-are-combined ()
  (p3-org-export-test--with-temp-directory directory
    (let ((local (expand-file-name "local.bib" directory))
          (global (expand-file-name "global.bib" directory)))
      (p3-org-export-test--write-bibliography local)
      (p3-org-export-test--write-bibliography global)
      (with-temp-buffer
        (setq default-directory directory)
        (insert "#+BIBLIOGRAPHY: local.bib\n\nA claim [cite:@doe2020].\n")
        (org-mode)
        (let ((org-cite-global-bibliography (list global)))
          (should
           (equal (p3-org-export--citation-arguments)
                  (list "--citeproc"
                        (concat "--bibliography=" local)
                        (concat "--bibliography=" global)))))))))

(ert-deftest p3-org-export-citations-require-a-bibliography ()
  (with-temp-buffer
    (insert "A claim [cite:@doe2020].\n")
    (org-mode)
    (let ((org-cite-global-bibliography nil))
      (should-error (p3-org-export--citation-arguments)
                    :type 'user-error))))

(ert-deftest p3-org-export-does-not-run-citeproc-without-citations ()
  (with-temp-buffer
    (insert "Plain text without citations.\n")
    (org-mode)
    (let ((org-cite-global-bibliography '("/tmp/global.bib")))
      (should-not (p3-org-export--citation-arguments)))))

(ert-deftest p3-org-export-rejects-unreadable-reference-document ()
  (should-error
   (p3-org-export--validate-reference "/path/that/does/not/exist.docx")
   :type 'user-error))

(ert-deftest p3-org-export-setup-restores-org-open-and-adds-export-binding ()
  (p3-org-export-setup)
  (should (eq (lookup-key org-mode-map (kbd "C-c C-o"))
              #'org-open-at-point))
  (should (eq (lookup-key org-mode-map (kbd "C-c E"))
              #'p3/org-export)))

(ert-deftest p3-org-export-gfm-runs-through-pandoc-when-available ()
  (skip-unless (executable-find "pandoc"))
  (p3-org-export-test--with-temp-directory directory
    (let ((source (expand-file-name "report.org" directory)))
      (with-temp-file source
        (insert "#+TITLE: Export Test\n\n* Heading\n\nBody text.\n"))
      (with-current-buffer (find-file-noselect source)
        (unwind-protect
            (progn
              (org-mode)
              (let* ((output (p3-org-export-run 'gfm nil))
                     (contents (p3-org-export-test--contents output)))
                (should (file-exists-p output))
                (should (string-match-p "# Heading" contents))
                (should (string-match-p "title:.*Export Test" contents))))
          (set-buffer-modified-p nil)
          (kill-buffer (current-buffer)))))))

(ert-deftest p3-org-export-gfm-renders-org-citations-with-global-bibliography ()
  (skip-unless (executable-find "pandoc"))
  (p3-org-export-test--with-temp-directory directory
    (let* ((source (expand-file-name "cited-report.org" directory))
           (bibliography (expand-file-name "references.bib" directory)))
      (p3-org-export-test--write-bibliography bibliography)
      (with-temp-file source
        (insert "#+TITLE: Citation Test\n\nA claim [cite:@doe2020].\n"))
      (with-current-buffer (find-file-noselect source)
        (unwind-protect
            (let ((org-cite-global-bibliography (list bibliography)))
              (org-mode)
              (let* ((output (p3-org-export-run 'gfm nil))
                     (contents (p3-org-export-test--contents output)))
                (should (string-match-p "Doe 2020" contents))
                (should (string-match-p "Doe, Jane" contents))
                (should-not (string-match-p "cite:@doe2020" contents))))
          (set-buffer-modified-p nil)
          (kill-buffer (current-buffer)))))))

(ert-deftest p3-org-export-gfm-renders-org-citations-with-local-bibliography ()
  (skip-unless (executable-find "pandoc"))
  (p3-org-export-test--with-temp-directory directory
    (let* ((source (expand-file-name "local-cited-report.org" directory))
           (bibliography (expand-file-name "references.bib" directory)))
      (p3-org-export-test--write-bibliography bibliography)
      (with-temp-file source
        (insert
         "#+TITLE: Local Citation Test\n"
         "#+BIBLIOGRAPHY: references.bib\n\n"
         "A claim [cite:@doe2020].\n"))
      (with-current-buffer (find-file-noselect source)
        (unwind-protect
            (let ((org-cite-global-bibliography nil))
              (org-mode)
              (let* ((output (p3-org-export-run 'gfm nil))
                     (contents (p3-org-export-test--contents output)))
                (should (string-match-p "Doe 2020" contents))
                (should (string-match-p "Doe, Jane" contents))
                (should-not (string-match-p "cite:@doe2020" contents))))
          (set-buffer-modified-p nil)
          (kill-buffer (current-buffer)))))))

(ert-deftest p3-org-export-docx-runs-realistic-report-through-pandoc ()
  (skip-unless (and (executable-find "pandoc")
                    (p3-org-export-test--python-executable)))
  (p3-org-export-test--with-temp-directory directory
    (let* ((source (expand-file-name "report.org" directory))
           (bibliography (expand-file-name "references.bib" directory))
           (figure-directory (expand-file-name "figures" directory))
           (figure (expand-file-name "example.png" figure-directory))
           (reference-source (expand-file-name "reference.md" directory))
           (reference (expand-file-name "reference.docx" directory)))
      (make-directory figure-directory)
      (p3-org-export-test--write-bibliography bibliography)
      (p3-org-export-test--write-png figure)
      (with-temp-file source
        (insert
         "#+TITLE: Word Export Test\n"
         "#+AUTHOR: Example Author\n"
         "#+BIBLIOGRAPHY: references.bib\n\n"
         "* Executive summary\n"
         "A paragraph with *bold*, /italic/, a [[https://example.com][link]], "
         "a footnote[fn:1], and a citation [cite:@doe2020].\n\n"
         "- First item\n"
         "- Second item\n\n"
         "#+BEGIN_EXPORT openxml\n"
         "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>\n"
         "#+END_EXPORT\n\n"
         "* Data\n"
         "#+CAPTION: Example table\n"
         "| Name | Value |\n"
         "|------+-------|\n"
         "| A    |     1 |\n"
         "| B    |     2 |\n\n"
         "#+CAPTION: Example figure\n"
         "[[file:figures/example.png]]\n\n"
         "[fn:1] A footnote.\n"))
      (with-temp-file reference-source
        (insert "# Reference document\n"))
      (should
       (zerop
        (call-process "pandoc" nil nil nil
                      reference-source "-o" reference)))
      (p3-org-export-test--customize-reference-docx reference)
      (with-current-buffer (find-file-noselect source)
        (unwind-protect
            (let ((org-cite-global-bibliography nil))
              (org-mode)
              (let* ((output (p3-org-export-run 'docx reference))
                     (document-xml
                      (p3-org-export-test--zip-member-contents
                       output "word/document.xml"))
                     (styles-xml
                      (p3-org-export-test--zip-member-contents
                       output "word/styles.xml"))
                     (relationships
                      (p3-org-export-test--zip-member-contents
                       output "word/_rels/document.xml.rels"))
                     (footnotes
                      (p3-org-export-test--zip-member-contents
                       output "word/footnotes.xml"))
                     (members (p3-org-export-test--zip-members output)))
                (should (file-exists-p output))
                (should (> (file-attribute-size (file-attributes output)) 0))
                (should (p3-org-export-test--zip-file-p output))
                (should (string-match-p "Executive summary" document-xml))
                (should (string-match-p "<w:tbl" document-xml))
                (should (string-match-p "<w:numPr" document-xml))
                (should (string-match-p "<w:drawing" document-xml))
                (should (string-match-p "Example figure" document-xml))
                (should (string-match-p "Doe" document-xml))
                (should (string-match-p "Example Article" document-xml))
                (should (string-match-p "w:type=\"page\"" document-xml))
                (should (string-match-p "w:top=\"1008\"" document-xml))
                (should (string-match-p "Courier New" styles-xml))
                (should (string-match-p "https://example.com" relationships))
                (should (string-match-p "A footnote" footnotes))
                (should
                 (string-match-p
                  "word/media/[^\n]*\\.png"
                  (mapconcat #'identity members "\n")))))
          (set-buffer-modified-p nil)
          (kill-buffer (current-buffer)))))))

(ert-deftest p3-org-export-docx-warning-fails-without-overwriting-output ()
  (skip-unless (executable-find "pandoc"))
  (p3-org-export-test--with-temp-directory directory
    (let* ((source (expand-file-name "report.org" directory))
           (output (expand-file-name "report.docx" directory))
           (sentinel "previous valid output"))
      (with-temp-file source
        (insert
         "#+TITLE: Missing Asset\n\n"
         "* Figure\n"
         "#+CAPTION: Missing figure\n"
         "[[file:figures/does-not-exist.png]]\n"))
      (with-temp-file output
        (insert sentinel))
      (with-current-buffer (find-file-noselect source)
        (unwind-protect
            (progn
              (org-mode)
              (should-error (p3-org-export-run 'docx nil)
                            :type 'user-error)
              (should (equal (p3-org-export-test--contents output)
                             sentinel)))
          (set-buffer-modified-p nil)
          (kill-buffer (current-buffer)))))))

(provide 'p3-org-export-test)

;;; p3-org-export-test.el ends here
