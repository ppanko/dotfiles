# Project-aware Org-roam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a thin project-aware Org-roam workflow that maps normalized `project.el` roots to durable Org-roam hub IDs, supports explicit note/heading membership, project-aware capture/discovery, and a native Agenda TODO view.

**Architecture:** Keep filesystem identity in `p3-project.el` and literate-project behavior in `p3-org-roam.el`. Persist only the machine-local root-to-hub alist through existing `savehist`; store durable membership in Org `P3_PROJECT` properties keyed to the hub Org ID. Reuse normal Org-roam node completion/capture and Org Agenda rather than introducing a project/task database or alternate UI.

**Tech Stack:** Emacs Lisp, Emacs 29+ `project.el`, Org/Org Agenda, Org-roam 2.x, `savehist`, ERT.

**Spec:** `docs/superpowers/specs/2026-09-14-project-aware-org-roam-design.md`

## Global Constraints

- `lisp/p3-project.el` remains unchanged; reuse `p3/project-root` and `p3/project-normalize-root`.
- Hub Org ID is the canonical durable literate-project identity.
- One normalized local root maps to at most one hub; one hub may map from multiple roots explicitly.
- Root mappings are machine-local and persisted only through existing `savehist` state.
- `P3_PROJECT` membership is singular for files and headings in v1.
- Context precedence is nearest explicit current/ancestor heading `P3_PROJECT`, then file-level `P3_PROJECT`, then normalized project-root mapping, then none.
- Hub establishment must save and index required self-marking metadata before recording a root mapping.
- Ordinary note/heading association must never save unrelated modified-buffer edits implicitly.
- Project Agenda inheritance is restricted to `P3_PROJECT`; global Agenda state must be restored after generation.
- `p3-org-roam.el` keeps its existing dynamic-binding contract; long-lived refresh state must use explicit buffer-local variables, not captured lexical closures.
- No dashboard, project-folder hierarchy, second task database, custom task UI, worktree lifecycle layer, Forge dependency, or live-buffer/database reconciliation layer.

---

## File Structure

- `lisp/p3-org-roam.el` — all project-aware Org-roam behavior, state helpers, command map, capture/discovery, and Agenda generation.
- `lisp/p3-config-org-roam.el` — declarative package wiring, savehist registration, declarations, and the `C-c n p` prefix binding.
- `test/p3-org-roam-test.el` — behavior tests using stubs and temporary Org buffers/files; no real Org-roam database required.
- `test/p3-config-org-roam-test.el` — configuration-boundary tests for savehist registration and project-prefix wiring.
- `.github/workflows/emacs-tests.yml` — leave unchanged unless the existing Org-roam smoke assertion needs to protect the new public command-map surface.

---

### Task 1: Root-to-hub identity and project-context resolution

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `test/p3-org-roam-test.el`

**Interfaces:**
- Consumes: `p3/project-root ()`, `p3/project-normalize-root (root)`, Org property APIs, Org-roam node accessors.
- Produces:
  - `p3/org-roam-project-associations` — alist of `(NORMALIZED-ROOT . HUB-ID)`.
  - `p3/org-roam-project-hub-id-for-root (root)`.
  - `p3/org-roam-project-associate-root (root hub-id &optional replace)`.
  - `p3/org-roam--node-file-project-id (node)`.
  - `p3/org-roam-project-hub-p (node)`.
  - `p3/org-roam--hub-node (hub-id)`.
  - `p3/org-roam--nearest-heading-project-id ()`.
  - `p3/org-roam--file-project-id-live ()`.
  - `p3/org-roam-project-context ()`.

- [ ] **Step 1: Write RED root-mapping and hub-recognition tests**

Add these tests to `test/p3-org-roam-test.el`:

```elisp
(ert-deftest p3-org-roam-project-root-association-normalizes-and-rejects-conflict ()
  (let ((p3/org-roam-project-associations nil))
    (cl-letf (((symbol-function 'p3/project-normalize-root)
               (lambda (_root) "/tmp/repo/")))
      (should (equal (p3/org-roam-project-associate-root "/tmp/repo" "hub-a")
                     "hub-a"))
      (should (equal (p3/org-roam-project-hub-id-for-root "/tmp/repo/")
                     "hub-a"))
      (should-error
       (p3/org-roam-project-associate-root "/tmp/repo" "hub-b")
       :type 'user-error))))

(ert-deftest p3-org-roam-project-root-association-can-replace-explicitly ()
  (let ((p3/org-roam-project-associations '(("/tmp/repo/" . "hub-a"))))
    (cl-letf (((symbol-function 'p3/project-normalize-root)
               (lambda (_root) "/tmp/repo/")))
      (should (equal (p3/org-roam-project-associate-root
                      "/tmp/repo" "hub-b" t)
                     "hub-b"))
      (should (equal p3/org-roam-project-associations
                     '(("/tmp/repo/" . "hub-b")))))))

(ert-deftest p3-org-roam-project-one-hub-may-own-multiple-roots ()
  (let ((p3/org-roam-project-associations nil))
    (cl-letf (((symbol-function 'p3/project-normalize-root)
               (lambda (root) (file-name-as-directory root))))
      (p3/org-roam-project-associate-root "/tmp/a" "hub")
      (p3/org-roam-project-associate-root "/tmp/b" "hub")
      (should (= (length p3/org-roam-project-associations) 2)))))

(ert-deftest p3-org-roam-project-hub-requires-self-marked-file-node ()
  (cl-letf (((symbol-function 'org-roam-node-id)
             (lambda (node) (plist-get node :id)))
            ((symbol-function 'org-roam-node-level)
             (lambda (node) (plist-get node :level)))
            ((symbol-function 'org-roam-node-properties)
             (lambda (node) (plist-get node :properties))))
    (should (p3/org-roam-project-hub-p
             '(:id "hub" :level 0 :properties (("P3_PROJECT" . "hub")))))
    (should-not
     (p3/org-roam-project-hub-p
      '(:id "hub" :level 0 :properties (("P3_PROJECT" . "other")))))
    (should-not
     (p3/org-roam-project-hub-p
      '(:id "hub" :level 1 :properties (("P3_PROJECT" . "hub")))))))
```

- [ ] **Step 2: Run focused tests and confirm RED**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
```

Expected: the new tests fail because the project identity functions and variable do not exist.

- [ ] **Step 3: Implement the minimal root/hub helpers**

Add without enabling lexical binding:

```elisp
(require 'org)
(require 'p3-project)

(defvar p3/org-roam-project-associations nil
  "Machine-local normalized project-root to Org-roam hub-ID mappings.")

(declare-function org-roam-node-from-id "org-roam-node" (id))
(declare-function org-roam-node-id "org-roam-node" (node))
(declare-function org-roam-node-level "org-roam-node" (node))
(declare-function org-roam-node-properties "org-roam-node" (node))
```

Implement mapping with `assoc`, `setcdr`, `push`, and `p3/project-normalize-root`. Nil/nonexistent roots must raise `user-error`; a different existing hub must raise unless `replace` is non-nil.

Use Org-roam's properties alist:

```elisp
(defun p3/org-roam--node-file-project-id (node)
  "Return NODE's file-level P3_PROJECT value, or nil."
  (when (and node (zerop (or (org-roam-node-level node) 0)))
    (cdr (assoc-string "P3_PROJECT" (org-roam-node-properties node)))))
```

`p3/org-roam-project-hub-p` requires non-empty `org-roam-node-id` equal to `p3/org-roam--node-file-project-id`. `p3/org-roam--hub-node` calls `org-roam-node-from-id` and raises `user-error` unless the result is self-marked.

- [ ] **Step 4: Write RED context-precedence tests**

Add exact tests for child override, ancestor inheritance, file fallback, filesystem fallback, and none:

```elisp
(ert-deftest p3-org-roam-project-context-prefers-nearest-heading ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n"
            "* Parent\n:PROPERTIES:\n:P3_PROJECT: parent-project\n:END:\n"
            "** Child\n:PROPERTIES:\n:P3_PROJECT: child-project\n:END:\n"
            "*** TODO Work\n")
    (goto-char (point-max))
    (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
      (should (equal (p3/org-roam-project-context) "child-project")))))

(ert-deftest p3-org-roam-project-context-inherits-nearest-ancestor-before-file ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n"
            "* Parent\n:PROPERTIES:\n:P3_PROJECT: parent-project\n:END:\n"
            "** TODO Work\n")
    (goto-char (point-max))
    (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
      (should (equal (p3/org-roam-project-context) "parent-project")))))

(ert-deftest p3-org-roam-project-context-falls-back-to-file-property ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n* TODO Work\n")
    (goto-char (point-max))
    (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
      (should (equal (p3/org-roam-project-context) "file-project")))))

(ert-deftest p3-org-roam-project-context-falls-back-to-root-map ()
  (let ((p3/org-roam-project-associations '(("/tmp/repo/" . "root-project"))))
    (with-temp-buffer
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () "/tmp/repo/"))
                ((symbol-function 'p3/project-normalize-root)
                 (lambda (_root) "/tmp/repo/")))
        (should (equal (p3/org-roam-project-context) "root-project"))))))

(ert-deftest p3-org-roam-project-context-is-nil-without-any-source ()
  (let ((p3/org-roam-project-associations nil))
    (with-temp-buffer
      (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
        (should-not (p3/org-roam-project-context))))))
```

- [ ] **Step 5: Implement explicit heading walk and file fallback**

Use this shape for the nearest-heading helper so normal Org inheritance does not collapse the heading/file precedence phases:

```elisp
(defun p3/org-roam--nearest-heading-project-id ()
  "Return nearest explicit heading P3_PROJECT at point or an ancestor."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (unless (org-before-first-heading-p)
        (org-back-to-heading t)
        (catch 'project
          (while t
            (when-let ((project-id
                        (org-entry-get (point) "P3_PROJECT" nil)))
              (throw 'project project-id))
            (unless (org-up-heading-safe)
              (throw 'project nil))))))))
```

Read file scope separately from the zeroth section using `org-entry-get` at `point-min`. `p3/org-roam-project-context` checks nearest heading, then file scope, then root mapping.

- [ ] **Step 6: Run focused tests and commit Task 1**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
git add lisp/p3-org-roam.el test/p3-org-roam-test.el
git commit -m "feat: add Org-roam project identity context"
```

---

### Task 2: Explicit note/heading association

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `test/p3-org-roam-test.el`

**Interfaces:**
- Consumes: Task 1 hub/context helpers.
- Produces:
  - `p3/org-roam--read-hub-node ()`.
  - `p3/org-roam--set-file-project-id (hub-id)`.
  - `p3/org-roam--remove-file-project-id ()`.
  - `p3/org-roam--heading-project-id-explicit ()`.
  - `p3/org-roam--set-heading-project-id (hub-id)`.
  - `p3/org-roam--remove-heading-project-id ()`.
  - interactive `p3/org-roam-project-associate (&optional whole-file)`.

- [ ] **Step 1: Write RED tests for file/heading mutation and unsaved-buffer safety**

Add:

```elisp
(ert-deftest p3-org-roam-project-heading-remove-reveals-file-membership ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n"
            "* TODO Work\n:PROPERTIES:\n:P3_PROJECT: other-project\n:END:\n")
    (goto-char (point-max))
    (org-back-to-heading t)
    (p3/org-roam--remove-heading-project-id)
    (should (equal (p3/org-roam-project-context) "file-project"))))

(ert-deftest p3-org-roam-project-file-remove-preserves-heading-membership ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n"
            "* TODO Work\n:PROPERTIES:\n:P3_PROJECT: heading-project\n:END:\n")
    (p3/org-roam--remove-file-project-id)
    (goto-char (point-max))
    (org-back-to-heading t)
    (should (equal (org-entry-get (point) "P3_PROJECT" nil)
                   "heading-project"))))

(ert-deftest p3-org-roam-project-ordinary-association-does-not-save-buffer ()
  (with-temp-buffer
    (org-mode)
    (insert "* TODO Work\n")
    (set-buffer-modified-p t)
    (let (saved)
      (cl-letf (((symbol-function 'save-buffer)
                 (lambda (&rest _) (setq saved t))))
        (p3/org-roam--set-heading-project-id "hub")
        (should-not saved)
        (should (equal (org-entry-get (point) "P3_PROJECT" nil) "hub"))))))
```

Add one command-level test where point is on a heading and no prefix is supplied, stubbing `p3/org-roam--set-heading-project-id` and asserting the file setter is not called. Add a second command-level test with prefix `(4)`, asserting only the file setter is called.

- [ ] **Step 2: Run focused tests and confirm RED**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
```

- [ ] **Step 3: Implement property helpers against the live buffer only**

Use `org-entry-put`/`org-entry-delete` at the current heading for heading scope and at `point-min` for file scope. Do not call `save-buffer`, `write-file`, or Org-roam DB update functions in these ordinary mutation helpers.

Add:

```elisp
(defun p3/org-roam--read-hub-node ()
  "Read an existing self-marked project hub node."
  (org-roam-node-read nil #'p3/org-roam-project-hub-p nil t "Project hub: "))
```

Declare `org-roam-node-read` with its current 5-argument signature.

- [ ] **Step 4: Implement the single association command**

Exact behavior:

```text
scope = file when WHOLE-FILE is non-nil or point is before first heading
scope = heading otherwise
explicit property absent -> use valid current project when available, else read a hub; set property
explicit property present -> completing-read action from ("change" "remove")
change -> read a self-marked hub; if hub differs, yes-or-no-p before mutation
remove -> delete only that scope's explicit property
```

If an explicit heading property is removed, do not write a no-project sentinel; normal ancestor/file membership becomes effective. Reject non-Org buffers with `user-error`.

- [ ] **Step 5: Rerun focused tests and commit Task 2**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
git add lisp/p3-org-roam.el test/p3-org-roam-test.el
git commit -m "feat: add explicit Org-roam project association"
```

---

### Task 3: Project hub lifecycle and explicit stale-mapping repair

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `test/p3-org-roam-test.el`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - `p3/org-roam--project-template (hub-id &optional immediate-finish)`.
  - `p3/org-roam--promote-node-to-hub (node root &optional replace-root)`.
  - `p3/org-roam--create-hub (root &optional replace-root)`.
  - `p3/org-roam--establish-hub-for-root (root &optional replace-root)`.
  - interactive `p3/org-roam-project-note ()`.

- [ ] **Step 1: Write RED transactional-promotion tests**

Use stubs to enforce ordering:

```elisp
(ert-deftest p3-org-roam-project-promote-saves-before-mapping ()
  (let (calls)
    (cl-letf (((symbol-function 'p3/org-roam-project-hub-p) (lambda (_node) nil))
              ((symbol-function 'p3/org-roam--node-file-project-id) (lambda (_node) nil))
              ((symbol-function 'org-roam-node-id) (lambda (_node) "hub"))
              ((symbol-function 'org-roam-node-file) (lambda (_node) "/tmp/hub.org"))
              ((symbol-function 'find-file-noselect) (lambda (_file) (current-buffer)))
              ((symbol-function 'buffer-modified-p) (lambda (&optional _buffer) nil))
              ((symbol-function 'p3/org-roam--set-file-project-id)
               (lambda (_id) (push 'write calls)))
              ((symbol-function 'save-buffer) (lambda (&rest _) (push 'save calls)))
              ((symbol-function 'org-roam-db-update-file)
               (lambda (&optional _file) (push 'index calls)))
              ((symbol-function 'p3/org-roam-project-associate-root)
               (lambda (&rest _) (push 'map calls) "hub")))
      (p3/org-roam--promote-node-to-hub 'node "/tmp/repo")
      (should (equal (nreverse calls) '(write save index map))))))

(ert-deftest p3-org-roam-project-promote-save-failure-never-maps-root ()
  (let (mapped)
    (cl-letf (((symbol-function 'p3/org-roam-project-hub-p) (lambda (_node) nil))
              ((symbol-function 'p3/org-roam--node-file-project-id) (lambda (_node) nil))
              ((symbol-function 'org-roam-node-id) (lambda (_node) "hub"))
              ((symbol-function 'org-roam-node-file) (lambda (_node) "/tmp/hub.org"))
              ((symbol-function 'find-file-noselect) (lambda (_file) (current-buffer)))
              ((symbol-function 'buffer-modified-p) (lambda (&optional _buffer) nil))
              ((symbol-function 'p3/org-roam--set-file-project-id) #'ignore)
              ((symbol-function 'save-buffer) (lambda (&rest _) (error "save failed")))
              ((symbol-function 'p3/org-roam-project-associate-root)
               (lambda (&rest _) (setq mapped t))))
      (should-error (p3/org-roam--promote-node-to-hub 'node "/tmp/repo"))
      (should-not mapped))))
```

Add a third test with `buffer-modified-p => t` asserting `user-error` before the property setter is called. Add a fourth where `p3/org-roam-project-hub-p => t` asserting mapping occurs without `save-buffer`.

- [ ] **Step 2: Run focused tests and confirm RED**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
```

- [ ] **Step 3: Implement the shared project capture template**

Create a normal flat file+head template; reuse it for hub creation and project-note capture:

```elisp
(defun p3/org-roam--project-template (hub-id &optional immediate-finish)
  "Return an Org-roam file capture template associated with HUB-ID."
  (append
   (list "p" "project" 'plain "%?"
         :if-new
         (list 'file+head
               "%<%Y%m%d%H%M%S>-${slug}.org"
               (format
                ":PROPERTIES:\n:P3_PROJECT: %s\n:END:\n#+title: ${title}\n#+category:${title}\n#+created: %%U\n#+last_modified: %%U\n"
                hub-id))
         :unnarrowed t)
   (when immediate-finish '(:immediate-finish t))))
```

- [ ] **Step 4: Implement existing-node promotion transactionally**

Declare `org-roam-node-file`, `org-roam-db-update-file`, and use `find-file-noselect`.

Exact order for an unassociated existing node:

```text
validate node file + ID
reject another file-level P3_PROJECT
if buffer already visiting file and buffer-modified-p -> user-error before mutation
set file-level P3_PROJECT to node ID
save-buffer
org-roam-db-update-file
associate root -> ID, passing replace-root through as REPLACE
return ID
```

If node is already self-marked, skip file mutation/save/index and only map the root.

- [ ] **Step 5: Write RED new-hub and stale-repair tests**

Add:

```elisp
(ert-deftest p3-org-roam-project-create-hub-maps-after-capture-and-index ()
  (let (calls template)
    (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "New Hub"))
              ((symbol-function 'org-id-new) (lambda () "new-hub"))
              ((symbol-function 'org-roam-node-create) (lambda (&rest args) args))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest args)
                 (setq template (car (plist-get args :templates)))
                 (push 'capture calls)))
              ((symbol-function 'org-roam-db-update-file)
               (lambda (&optional _file) (push 'index calls)))
              ((symbol-function 'p3/org-roam--hub-node)
               (lambda (_id) 'hub-node))
              ((symbol-function 'p3/org-roam-project-associate-root)
               (lambda (&rest _) (push 'map calls) "new-hub")))
      (should (equal (p3/org-roam--create-hub "/tmp/repo") "new-hub"))
      (should (equal (nreverse calls) '(capture index map)))
      (should (eq (plist-get (nthcdr 4 template) :immediate-finish) t)))))

(ert-deftest p3-org-roam-project-note-offers-explicit-repair-for-stale-root-map ()
  (let (repaired)
    (cl-letf (((symbol-function 'p3/org-roam-project-context) (lambda () "stale"))
              ((symbol-function 'p3/org-roam--hub-node)
               (lambda (_id) (user-error "stale")))
              ((symbol-function 'p3/project-root) (lambda () "/tmp/repo/"))
              ((symbol-function 'yes-or-no-p) (lambda (&rest _) t))
              ((symbol-function 'p3/org-roam--establish-hub-for-root)
               (lambda (_root replace-root)
                 (setq repaired replace-root)
                 "new-hub"))
              ((symbol-function 'org-roam-node-from-id) (lambda (_id) 'hub-node))
              ((symbol-function 'org-roam-node-visit) #'ignore))
      (p3/org-roam-project-note)
      (should repaired))))
```

- [ ] **Step 6: Implement create/establish/open/repair**

`p3/org-roam--create-hub`:

```text
read title
preallocate hub ID with org-id-new
org-roam-capture- with node (:id hub-id :title title), project template immediate-finish=t, and :props '(:finalize find-file)
org-roam-db-update-file in the finalized hub buffer
validate p3/org-roam--hub-node
associate root only now; pass REPLACE-ROOT through
return hub ID
```

`p3/org-roam--establish-hub-for-root` uses `read-char-choice` with `e` (existing) and `n` (new). Existing selection uses `org-roam-node-read` with file-node filtering and `require-match=t`, then promotes/maps it.

`p3/org-roam-project-note`:

```text
if context resolves and hub validates -> visit hub
if context is a stale root mapping -> ask yes-or-no-p before explicit repair; repair uses establish-hub-for-root with replace-root=t
if no project context but project.el root exists -> establish hub with replace-root=nil and visit it
if neither Org nor filesystem context exists -> user-error
```

Do not silently replace a stale mapping without the confirmation step.

- [ ] **Step 7: Run focused tests and commit Task 3**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
git add lisp/p3-org-roam.el test/p3-org-roam-test.el
git commit -m "feat: add Org-roam project hub lifecycle"
```

---

### Task 4: Project-aware new-note capture and note discovery

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `test/p3-org-roam-test.el`

**Interfaces:**
- Consumes: Task 1 context/hub validation and Task 3 capture template.
- Produces:
  - `p3/org-roam--project-node-p (node hub-id)`.
  - interactive `p3/org-roam-project-find-note ()`.
  - interactive `p3/org-roam-project-new-note ()`.

- [ ] **Step 1: Write RED filter/discovery tests**

Add:

```elisp
(ert-deftest p3-org-roam-project-node-filter-requires-file-scope-and-hub-id ()
  (cl-letf (((symbol-function 'org-roam-node-level)
             (lambda (node) (plist-get node :level)))
            ((symbol-function 'org-roam-node-properties)
             (lambda (node) (plist-get node :properties))))
    (should (p3/org-roam--project-node-p
             '(:level 0 :properties (("P3_PROJECT" . "hub"))) "hub"))
    (should-not (p3/org-roam--project-node-p
                 '(:level 0 :properties (("P3_PROJECT" . "other"))) "hub"))
    (should-not (p3/org-roam--project-node-p
                 '(:level 2 :properties (("P3_PROJECT" . "hub"))) "hub"))))

(ert-deftest p3-org-roam-project-find-note-uses-required-filtered-completion ()
  (let (seen-filter seen-require visited)
    (cl-letf (((symbol-function 'p3/org-roam-project-context) (lambda () "hub"))
              ((symbol-function 'p3/org-roam--hub-node) (lambda (_id) 'hub-node))
              ((symbol-function 'org-roam-node-read)
               (lambda (_initial filter _sort require-match _prompt)
                 (setq seen-filter filter seen-require require-match)
                 'chosen-node))
              ((symbol-function 'org-roam-node-visit)
               (lambda (node &rest _) (setq visited node))))
      (p3/org-roam-project-find-note)
      (should (functionp seen-filter))
      (should seen-require)
      (should (eq visited 'chosen-node)))))
```

- [ ] **Step 2: Write RED project-new-note tests**

```elisp
(ert-deftest p3-org-roam-project-new-note-errors-without-context ()
  (cl-letf (((symbol-function 'p3/org-roam-project-context) (lambda () nil)))
    (should-error (p3/org-roam-project-new-note) :type 'user-error)))

(ert-deftest p3-org-roam-project-new-note-injects-project-file-property ()
  (let (template)
    (cl-letf (((symbol-function 'p3/org-roam-project-context) (lambda () "hub"))
              ((symbol-function 'p3/org-roam--hub-node) (lambda (_id) 'hub-node))
              ((symbol-function 'read-string) (lambda (&rest _) "Project Note"))
              ((symbol-function 'org-roam-node-create) (lambda (&rest args) args))
              ((symbol-function 'org-roam-capture-)
               (lambda (&rest args)
                 (setq template (car (plist-get args :templates))))))
      (p3/org-roam-project-new-note)
      (let* ((plist (nthcdr 4 template))
             (target (plist-get plist :if-new))
             (head (nth 2 target)))
        (should (string-match-p "P3_PROJECT: hub" head))
        (should-not (plist-get plist :immediate-finish))))))
```

- [ ] **Step 3: Run focused tests and confirm RED**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
```

- [ ] **Step 4: Implement discovery and normal interactive capture**

`p3/org-roam--project-node-p` requires node level 0 and matching file-level property.

`p3/org-roam-project-find-note` validates the current hub, calls `org-roam-node-read` with a filter for that hub and `require-match=t`, then calls `org-roam-node-visit`.

`p3/org-roam-project-new-note` validates current hub, reads a new title, calls `org-roam-capture-` with `(org-roam-node-create :title title)` and `(p3/org-roam--project-template hub-id nil)`. Do not invoke hub creation when context is absent; fail with an actionable `user-error` directing the user to `p3/org-roam-project-note` first.

- [ ] **Step 5: Run focused tests and commit Task 4**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
git add lisp/p3-org-roam.el test/p3-org-roam-test.el
git commit -m "feat: add project-aware Org-roam capture and discovery"
```

---

### Task 5: Native project TODO Agenda with dynamic-binding-safe refresh

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `test/p3-org-roam-test.el`

**Interfaces:**
- Consumes: `p3/org-roam-project-context`, `p3/org-roam--hub-node`, `p3/org-roam-list-notes`, native `org-tags-view`.
- Produces:
  - buffer-local `p3/org-roam-project-agenda-hub-id`.
  - `p3/org-roam--project-todos (hub-id)`.
  - interactive `p3/org-roam-project-agenda-redo ()`.
  - interactive `p3/org-roam-project-todos ()`.

- [ ] **Step 1: Write RED dynamic-state tests**

```elisp
(ert-deftest p3-org-roam-project-todos-scopes-agenda-state ()
  (let ((org-agenda-files '("global.org"))
        (org-use-property-inheritance '("GLOBAL"))
        seen-files seen-inheritance seen-match seen-todo-only)
    (cl-letf (((symbol-function 'p3/org-roam-list-notes)
               (lambda () '("a.org" "a.org" "b.org")))
              ((symbol-function 'org-tags-view)
               (lambda (todo-only match)
                 (setq seen-files org-agenda-files
                       seen-inheritance org-use-property-inheritance
                       seen-match match
                       seen-todo-only todo-only)
                 (get-buffer-create "*p3-project-agenda-test*"))))
      (p3/org-roam--project-todos "hub")
      (should (equal seen-files '("a.org" "b.org")))
      (should (equal seen-inheritance '("P3_PROJECT")))
      (should (equal seen-match "P3_PROJECT=\"hub\""))
      (should seen-todo-only)
      (should (equal org-agenda-files '("global.org")))
      (should (equal org-use-property-inheritance '("GLOBAL"))))))

(ert-deftest p3-org-roam-project-agenda-redo-uses-buffer-local-hub-id ()
  (with-temp-buffer
    (setq-local p3/org-roam-project-agenda-hub-id "hub-a")
    (let (seen)
      (cl-letf (((symbol-function 'p3/org-roam--project-todos)
                 (lambda (hub-id) (setq seen hub-id))))
        (p3/org-roam-project-agenda-redo)
        (should (equal seen "hub-a"))))))
```

Add a third test that stubs `org-tags-view` to return a buffer, then asserts that buffer contains:

```elisp
(equal p3/org-roam-project-agenda-hub-id "hub")
(equal org-agenda-redo-command '(p3/org-roam-project-agenda-redo))
```

- [ ] **Step 2: Run focused tests and confirm RED**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
```

- [ ] **Step 3: Implement Agenda generation and refresh explicitly**

Declare `org-tags-view`, `org-use-property-inheritance`, and `org-agenda-redo-command`.

Use:

```elisp
(defvar-local p3/org-roam-project-agenda-hub-id nil
  "Hub ID represented by the current project Agenda buffer.")

(defun p3/org-roam--project-todos (hub-id)
  "Generate the native Org Agenda TODO view for HUB-ID."
  (let ((org-agenda-files (delete-dups (p3/org-roam-list-notes)))
        (org-use-property-inheritance '("P3_PROJECT")))
    (let ((buffer (org-tags-view t (format "P3_PROJECT=\"%s\"" hub-id))))
      (when (bufferp buffer)
        (with-current-buffer buffer
          (setq-local p3/org-roam-project-agenda-hub-id hub-id)
          (setq-local org-agenda-redo-command
                      '(p3/org-roam-project-agenda-redo))))
      buffer)))
```

If the installed Org version's `org-tags-view` returns nil while selecting the Agenda buffer, capture `(current-buffer)` immediately after the call instead; tests should pin the P3 behavior, not Org's return-value detail.

`p3/org-roam-project-agenda-redo` reads only `p3/org-roam-project-agenda-hub-id`; if nil, raise `user-error`; otherwise call the generator. Do not create a lambda closure around `hub-id`.

`p3/org-roam-project-todos` resolves and validates the current hub before generation.

- [ ] **Step 4: Run focused tests and commit Task 5**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
git add lisp/p3-org-roam.el test/p3-org-roam-test.el
git commit -m "feat: add project-scoped Org agenda"
```

---

### Task 6: Persistence registration, five-command surface, and regression verification

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `lisp/p3-config-org-roam.el`
- Modify: `test/p3-org-roam-test.el`
- Modify: `test/p3-config-org-roam-test.el`
- Modify only if necessary: `.github/workflows/emacs-tests.yml`

**Interfaces:**
- Consumes: all commands from Tasks 2–5.
- Produces:
  - `p3/org-roam-project-command-map` with exactly five bindings:
    - `h` -> `p3/org-roam-project-note`
    - `f` -> `p3/org-roam-project-find-note`
    - `n` -> `p3/org-roam-project-new-note`
    - `a` -> `p3/org-roam-project-associate`
    - `t` -> `p3/org-roam-project-todos`
  - `C-c n p` bound to that map through `use-package :bind-keymap`.
  - `p3/org-roam-project-associations` registered in `savehist-additional-variables`.

- [ ] **Step 1: Write RED command-map and config-boundary tests**

Behavior test:

```elisp
(ert-deftest p3-org-roam-project-command-map-has-five-workflow-commands ()
  (should (eq (lookup-key p3/org-roam-project-command-map (kbd "h"))
              #'p3/org-roam-project-note))
  (should (eq (lookup-key p3/org-roam-project-command-map (kbd "f"))
              #'p3/org-roam-project-find-note))
  (should (eq (lookup-key p3/org-roam-project-command-map (kbd "n"))
              #'p3/org-roam-project-new-note))
  (should (eq (lookup-key p3/org-roam-project-command-map (kbd "a"))
              #'p3/org-roam-project-associate))
  (should (eq (lookup-key p3/org-roam-project-command-map (kbd "t"))
              #'p3/org-roam-project-todos)))
```

Config tests:

```elisp
(ert-deftest p3-config-org-roam-registers-project-associations-with-savehist ()
  (let ((contents
         (with-temp-buffer
           (insert-file-contents
            (p3-config-org-roam-test--path "lisp/p3-config-org-roam.el"))
           (buffer-string))))
    (should (string-match-p
             (regexp-quote "savehist-additional-variables") contents))
    (should (string-match-p
             (regexp-quote "p3/org-roam-project-associations") contents))))

(ert-deftest p3-config-org-roam-binds-project-prefix-map ()
  (should
   (equal
    (p3-config-org-roam-test--keyword-values :bind-keymap)
    '(("C-c n p" . p3/org-roam-project-command-map)))))
```

Keep the existing `:bind` test unchanged so all old Org-roam shortcuts remain protected.

- [ ] **Step 2: Run the two Org-roam test files and confirm RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-org-roam-test.el \
  -l test/p3-config-org-roam-test.el \
  -f ert-run-tests-batch-and-exit
```

- [ ] **Step 3: Add the command map and declarative wiring**

In `p3-org-roam.el`:

```elisp
(defvar-keymap p3/org-roam-project-command-map
  :doc "Project-aware Org-roam commands."
  "h" #'p3/org-roam-project-note
  "f" #'p3/org-roam-project-find-note
  "n" #'p3/org-roam-project-new-note
  "a" #'p3/org-roam-project-associate
  "t" #'p3/org-roam-project-todos)
```

In `p3-config-org-roam.el`, add:

```elisp
(defvar savehist-additional-variables)

(with-eval-after-load 'savehist
  (add-to-list 'savehist-additional-variables
               'p3/org-roam-project-associations))
```

and inside `use-package org-roam`:

```elisp
:bind-keymap
("C-c n p" . p3/org-roam-project-command-map)
```

Do not replace any existing `C-c n` bindings.

- [ ] **Step 4: Run touched-module byte compilation with warnings as errors**

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile \
  lisp/p3-org-roam.el \
  lisp/p3-config-org-roam.el
```

Expected: zero warnings/errors. Add any missing `declare-function`/`defvar` declarations rather than suppressing warnings globally.

- [ ] **Step 5: Run the full ERT suite using the repository's current CI test list**

```bash
emacs -Q --batch \
  -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-config-test.el \
  -l test/p3-config-retirement-test.el \
  -l test/p3-config-appearance-test.el \
  -l test/p3-tab-bar-appearance-test.el \
  -l test/p3-config-editing-ownership-test.el \
  -l test/p3-config-ess-test.el \
  -l test/p3-project-test.el \
  -l test/p3-config-project-test.el \
  -l test/p3-project-preview-window-test.el \
  -l test/p3-core-test.el \
  -l test/p3-platform-test.el \
  -l test/p3-config-python-test.el \
  -l test/p3-python-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -l test/p3-ess-test.el \
  -l test/p3-gptel-test.el \
  -l test/p3-config-gptel-test.el \
  -l test/p3-r-tools-test.el \
  -l test/p3-org-test.el \
  -l test/p3-config-org-test.el \
  -l test/p3-org-roam-test.el \
  -l test/p3-config-org-roam-test.el \
  -l test/p3-org-present-test.el \
  -l test/p3-config-org-present-test.el \
  -l test/p3-org-export-test.el \
  -l test/p3-reference-test.el \
  -l test/p3-reference-reconstruction-test.el \
  -l test/p3-reference-adversarial-test.el \
  -l test/p3-config-reference-test.el \
  -l test/p3-commands-test.el \
  -l test/p3-git-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: zero unexpected results; retain only the repository's intentional pre-existing skips.

- [ ] **Step 6: Smoke-load the configuration boundary**

Run the existing Org-roam smoke command from `.github/workflows/emacs-tests.yml`. If it fails only because the new prefix-map symbol must be protected, extend the existing assertion to include:

```elisp
(keymapp p3/org-roam-project-command-map)
(fboundp 'p3/org-roam-project-note)
```

Do not create another CI job or duplicate package setup.

- [ ] **Step 7: Verify architectural scope before the final commit**

```bash
git diff master...HEAD -- lisp test .github
git diff master...HEAD -- lisp/p3-project.el
```

The second command must be empty. In the first diff, confirm there is no project-directory hierarchy, title/tag/backlink/Git-remote inference, custom task buffer/database, live-buffer/database reconciliation cache, worktree/Forge/build-system behavior, or unrelated Org cleanup.

- [ ] **Step 8: Commit Task 6**

```bash
git add lisp/p3-org-roam.el lisp/p3-config-org-roam.el \
        test/p3-org-roam-test.el test/p3-config-org-roam-test.el
git commit -m "feat: wire project-aware Org-roam workflow"
```

If `.github/workflows/emacs-tests.yml` changed in Step 6, include it in `git add`; otherwise leave it untouched.

---

## Final Review Gate

Before opening the PR:

- [ ] Every success criterion in `docs/superpowers/specs/2026-09-14-project-aware-org-roam-design.md` maps to a passing Task 1–6 test or an explicit final scope check.
- [ ] `git diff master...HEAD -- lisp/p3-project.el` is empty.
- [ ] `p3-org-roam.el` still has no `lexical-binding: t` cookie.
- [ ] Hub mapping is written only after self-marking metadata is saved and `org-roam-db-update-file` completes.
- [ ] Ordinary association never calls `save-buffer` implicitly.
- [ ] Removing a heading override exposes normal ancestor/file membership rather than a no-project sentinel.
- [ ] Stale root mappings have an explicit confirmed repair flow; they are never silently replaced.
- [ ] Project note discovery ignores general notes that contain only associated headings.
- [ ] No-context project-note capture fails instead of guessing/creating identity implicitly.
- [ ] Descendant command context and Agenda inheritance agree on nearest explicit heading/ancestor membership.
- [ ] Agenda refresh still works after the initial dynamic bindings unwind because it reads a buffer-local hub ID.
- [ ] Existing tag-based `p3/org-roam-get-agenda`, tagged capture, search, and all old Org-roam bindings remain green.
- [ ] Byte compilation and the complete ERT suite are green before opening the PR.
