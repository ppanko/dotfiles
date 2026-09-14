# Project-aware Org-roam Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a thin project-aware Org-roam workflow that maps normalized `project.el` roots to durable Org-roam hub IDs, supports explicit note/heading membership, project-aware capture/discovery, and a native Agenda TODO view.

**Architecture:** Keep filesystem identity in `p3-project.el` and literate project behavior in `p3-org-roam.el`. Persist only the machine-local root-to-hub alist through existing `savehist`; store durable project membership in Org `P3_PROJECT` properties keyed to the hub Org ID. Reuse normal Org-roam completion/capture and Org Agenda, with no new project/task database or workspace layer.

**Tech Stack:** Emacs Lisp, Emacs 29+ `project.el`, Org/Org Agenda, Org-roam 2.x APIs, `savehist`, ERT.

**Spec:** `docs/superpowers/specs/2026-09-14-project-aware-org-roam-design.md`

## Global Constraints

- `lisp/p3-project.el` remains unchanged; reuse `p3/project-root` and `p3/project-normalize-root`.
- Hub Org ID is the canonical durable literate-project identity.
- One normalized local root maps to at most one hub; one hub may map from multiple roots explicitly.
- Root mappings are machine-local and persisted only through existing `savehist` state.
- `P3_PROJECT` membership is singular for files and headings in v1.
- Context precedence is nearest explicit current/ancestor heading `P3_PROJECT`, then file-level `P3_PROJECT`, then normalized project-root mapping, then none.
- Hub establishment must save required self-marking metadata before recording a root mapping.
- Ordinary note/heading association must never save unrelated modified-buffer edits implicitly.
- Project Agenda inheritance is restricted to `P3_PROJECT`; global Agenda state must be restored after generation.
- `p3-org-roam.el` keeps its existing dynamic-binding contract; long-lived refresh state must use explicit buffer-local variables, not captured lexical closures.
- No dashboard, project-folder hierarchy, second task database, custom task UI, worktree lifecycle layer, Forge dependency, or live-buffer/database reconciliation layer.

---

## File Structure

- `lisp/p3-org-roam.el` — all project-aware Org-roam behavior, state helpers, command map, capture/discovery, and Agenda generation.
- `lisp/p3-config-org-roam.el` — declarative package wiring, savehist registration, declarations, and the `C-c n p` project-note prefix binding.
- `test/p3-org-roam-test.el` — behavior tests using stubs and temporary Org buffers/files; no real Org-roam database required.
- `test/p3-config-org-roam-test.el` — configuration-boundary tests for savehist registration and project-prefix wiring.
- `.github/workflows/emacs-tests.yml` — only adjust the Org-roam smoke assertion if the new public command-map surface needs verification; do not add a new workflow.

---

### Task 1: Root-to-hub identity and context resolution

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `test/p3-org-roam-test.el`

**Interfaces:**
- Consumes: `p3/project-root () -> string|nil`, `p3/project-normalize-root (root) -> string|nil`, Org entry/property APIs, Org-roam node accessors.
- Produces:
  - variable `p3/org-roam-project-associations` — alist of `(NORMALIZED-ROOT . HUB-ID)`.
  - `p3/org-roam-project-hub-id-for-root (root) -> string|nil`.
  - `p3/org-roam-project-associate-root (root hub-id &optional replace) -> hub-id`; signals `user-error` on invalid root or conflicting mapping unless `replace` is non-nil.
  - `p3/org-roam--node-file-project-id (node) -> string|nil` using `org-roam-node-properties`.
  - `p3/org-roam-project-hub-p (node) -> non-nil|nil`, requiring file node `ID == P3_PROJECT`.
  - `p3/org-roam--hub-node (hub-id) -> org-roam-node`; signals `user-error` if missing/non-self-marked.
  - `p3/org-roam-project-context () -> hub-id|nil` using the exact precedence from the spec.

- [ ] **Step 1: Add RED tests for root normalization, conflicts, multiple roots per hub, and hub recognition**

Append focused tests like:

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

(ert-deftest p3-org-roam-project-one-hub-may-own-multiple-roots ()
  (let ((p3/org-roam-project-associations nil))
    (cl-letf (((symbol-function 'p3/project-normalize-root)
               (lambda (root) (file-name-as-directory root))))
      (p3/org-roam-project-associate-root "/tmp/a" "hub")
      (p3/org-roam-project-associate-root "/tmp/b" "hub")
      (should (equal (length p3/org-roam-project-associations) 2)))))

(ert-deftest p3-org-roam-project-hub-requires-self-marked-file-node ()
  (cl-letf (((symbol-function 'org-roam-node-id)
             (lambda (node) (plist-get node :id)))
            ((symbol-function 'org-roam-node-level)
             (lambda (node) (plist-get node :level)))
            ((symbol-function 'org-roam-node-properties)
             (lambda (node) (plist-get node :properties))))
    (should (p3/org-roam-project-hub-p
             '(:id "hub" :level 0 :properties (("P3_PROJECT" . "hub")))))
    (should-not (p3/org-roam-project-hub-p
                 '(:id "hub" :level 0 :properties (("P3_PROJECT" . "other")))))))
```

- [ ] **Step 2: Run the focused test file and confirm RED**

Run:

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
```

Expected: new tests fail because the project identity functions/variable do not exist.

- [ ] **Step 3: Implement the minimal identity helpers**

At the top of `p3-org-roam.el`, add `org`, `p3-project`, and required declarations without enabling lexical binding:

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

Implement the root map with `assoc`/`setf`/`push`, always normalizing through `p3/project-normalize-root`. `replace=nil` must reject an existing different hub; `replace=t` may replace exactly that root entry.

Implement node property lookup using the Org-roam node property alist pattern:

```elisp
(defun p3/org-roam--node-file-project-id (node)
  "Return NODE's file-level P3_PROJECT value, or nil."
  (when (zerop (or (org-roam-node-level node) 0))
    (cdr (assoc-string "P3_PROJECT" (org-roam-node-properties node)))))
```

`p3/org-roam-project-hub-p` must require a non-empty node ID and equality between that ID and the file-level project ID. `p3/org-roam--hub-node` must call `org-roam-node-from-id` and validate with that predicate.

- [ ] **Step 4: Add RED tests for exact context precedence including ancestor headings**

Use temporary Org buffers, stubbing filesystem mapping only for the fallback case:

```elisp
(ert-deftest p3-org-roam-project-context-prefers-nearest-heading-ancestor ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n"
            "* Parent\n:PROPERTIES:\n:P3_PROJECT: parent-project\n:END:\n"
            "** Child\n:PROPERTIES:\n:P3_PROJECT: child-project\n:END:\n"
            "*** TODO Work\n")
    (goto-char (point-max))
    (should (equal (p3/org-roam-project-context) "child-project"))))

(ert-deftest p3-org-roam-project-context-inherits-parent-before-file ()
  (with-temp-buffer
    (org-mode)
    (insert ":PROPERTIES:\n:P3_PROJECT: file-project\n:END:\n"
            "* Parent\n:PROPERTIES:\n:P3_PROJECT: parent-project\n:END:\n"
            "** TODO Work\n")
    (goto-char (point-max))
    (should (equal (p3/org-roam-project-context) "parent-project"))))
```

Also add one test each for file-level fallback, filesystem-root fallback, and nil when none exists.

- [ ] **Step 5: Implement context resolution and rerun focused tests**

Use an explicit upward heading walk (`org-back-to-heading` plus `org-up-heading-safe`) and `org-entry-get ... nil` so file inheritance is not accidentally folded into the heading phase. Read the file-level property from the zeroth section separately. Only if both Org scopes fail, ask `p3/project-root` and map its normalized root.

Run the focused test command again. Expected: all `p3-org-roam-test.el` tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add lisp/p3-org-roam.el test/p3-org-roam-test.el
git commit -m "feat: add Org-roam project identity context"
```

---

### Task 2: Explicit file/heading association workflow

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `test/p3-org-roam-test.el`

**Interfaces:**
- Consumes: Task 1 hub/context helpers.
- Produces:
  - `p3/org-roam--read-hub-node () -> org-roam-node`, using `org-roam-node-read` with `p3/org-roam-project-hub-p` as filter and require-match enabled.
  - `p3/org-roam--file-project-id-live () -> string|nil`.
  - `p3/org-roam--set-file-project-id (hub-id)` / `p3/org-roam--remove-file-project-id ()`.
  - `p3/org-roam--heading-project-id-explicit () -> string|nil`.
  - interactive `p3/org-roam-project-associate (&optional whole-file)`; default scope current heading when in one, otherwise file; universal prefix forces file scope.

- [ ] **Step 1: Add RED tests for scope selection and mutation semantics**

Cover:

```elisp
(ert-deftest p3-org-roam-project-associate-defaults-to-heading () ...)
(ert-deftest p3-org-roam-project-associate-prefix-targets-file () ...)
(ert-deftest p3-org-roam-project-remove-heading-override-reveals-file-membership () ...)
(ert-deftest p3-org-roam-project-file-disassociation-preserves-heading-properties () ...)
(ert-deftest p3-org-roam-project-association-does-not-save-modified-buffer () ...)
```

For the last case, make the buffer modified before invoking the mutation, stub `save-buffer` to set a sentinel, and assert the sentinel remains nil while the property changes in the live buffer.

- [ ] **Step 2: Run focused tests and confirm RED**

Use the same focused ERT command. Expected: failures for missing association helpers/command.

- [ ] **Step 3: Implement property mutation helpers**

Use Org property APIs only against the current live buffer. File scope must operate on the zeroth-section property drawer; heading scope must operate on the exact heading at point. Do not call `save-buffer`, `write-file`, or `org-roam-db-sync` from ordinary association.

The remove path must remove only the explicit property at the target scope. After removing a heading override, `p3/org-roam-project-context` should naturally resolve the next ancestor/file value; do not write a sentinel.

- [ ] **Step 4: Implement the single association command**

Behavior:

```text
no explicit property -> choose/accept a self-marked hub and set it
explicit property    -> prompt "change" or "remove"
change               -> choose a self-marked hub; if different, require yes-or-no-p
remove               -> delete only this scope's explicit P3_PROJECT
```

Use the current resolved hub as the default only when it resolves to a valid self-marked hub; otherwise call `p3/org-roam--read-hub-node`. Reject non-Org buffers and file-scope operations on files that are not Org-roam file nodes with a clear `user-error`.

- [ ] **Step 5: Rerun focused tests**

Expected: association tests and all existing Org-roam behavior tests pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add lisp/p3-org-roam.el test/p3-org-roam-test.el
git commit -m "feat: add explicit Org-roam project association"
```

---

### Task 3: Project hub open/create/repair lifecycle

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `test/p3-org-roam-test.el`

**Interfaces:**
- Consumes: Task 1 root map/hub validation; Task 2 file-property helpers.
- Produces:
  - `p3/org-roam--promote-node-to-hub (node root) -> hub-id`.
  - `p3/org-roam--create-hub (root) -> hub-id` using an immediate-finish Org-roam capture.
  - `p3/org-roam--establish-hub-for-root (root) -> hub-id` prompting existing vs new explicitly.
  - interactive `p3/org-roam-project-note ()` opening the validated hub with `org-roam-node-visit`.

- [ ] **Step 1: Add RED tests for transactional promotion**

Cover these exact invariants:

```elisp
(ert-deftest p3-org-roam-project-promote-refuses-preexisting-unsaved-edits () ...)
(ert-deftest p3-org-roam-project-promote-saves-self-marking-before-root-map () ...)
(ert-deftest p3-org-roam-project-promote-save-failure-leaves-root-unmapped () ...)
(ert-deftest p3-org-roam-project-existing-self-marked-hub-maps-without-forced-save () ...)
```

Record call order in a list by stubbing the metadata write/save/root-associate helpers; assert `'(write save map)` for a clean unassociated note and no `map` call if `save-buffer` signals.

- [ ] **Step 2: Run focused tests and confirm RED**

Expected: missing lifecycle functions.

- [ ] **Step 3: Implement existing-node hub promotion**

Algorithm:

```text
validate node has file and ID
if node is already self-marked -> associate root only
if node has another P3_PROJECT -> user-error
visit/find the node's live buffer
if buffer was modified before promotion -> user-error asking user to save first
write file-level P3_PROJECT = node ID
save-buffer
optionally update that file in Org-roam if the package API is available
associate normalized root -> node ID
return node ID
```

Do not catch a failed save and continue. The mapping step occurs only after a successful save.

- [ ] **Step 4: Add RED tests for new-hub capture and `project-note` resolution**

Cover:

```elisp
(ert-deftest p3-org-roam-project-note-opens-existing-context-hub () ...)
(ert-deftest p3-org-roam-project-note-rejects-stale-mapping () ...)
(ert-deftest p3-org-roam-project-new-hub-maps-only-after-immediate-capture-finishes () ...)
```

For new hub creation, stub `org-id-new` to `"new-hub"`, stub `org-roam-capture-` to record its node/templates and return normally, and assert root association occurs after the capture stub. Also assert the dedicated template is `:immediate-finish t` and contains `P3_PROJECT: new-hub` in the file head.

- [ ] **Step 5: Implement explicit existing/new hub establishment**

Use `read-char-choice` with two options (`e` existing, `n` new). Existing selection uses `org-roam-node-read` with file-node filtering and `require-match=t`; do not infer by title.

For new creation:

```elisp
(let* ((title (read-string "Project hub title: "))
       (hub-id (org-id-new))
       (node (org-roam-node-create :id hub-id :title title))
       (template ... :immediate-finish t ...))
  (org-roam-capture- :node node :templates (list template))
  (unless (p3/org-roam--hub-node hub-id)
    (user-error "Project hub was not created"))
  (p3/org-roam-project-associate-root root hub-id)
  hub-id)
```

The template must remain flat under `org-roam-directory` and self-mark the hub. `p3/org-roam-project-note` should first resolve current project context; if present, validate/open it. If absent but a filesystem project exists, run the first-use establishment flow. If neither exists, fail clearly.

- [ ] **Step 6: Rerun focused tests and commit Task 3**

```bash
git add lisp/p3-org-roam.el test/p3-org-roam-test.el
git commit -m "feat: add Org-roam project hub lifecycle"
```

---

### Task 4: Project note capture and filtered discovery

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `test/p3-org-roam-test.el`

**Interfaces:**
- Consumes: `p3/org-roam-project-context`, `p3/org-roam--hub-node`, Org-roam node accessors/capture.
- Produces:
  - `p3/org-roam--project-node-p (node hub-id) -> non-nil|nil`; file nodes only, file-level `P3_PROJECT == hub-id`.
  - interactive `p3/org-roam-project-find-note ()`.
  - interactive `p3/org-roam-project-new-note ()`.

- [ ] **Step 1: Add RED tests for project-node filtering**

Construct stub nodes representing: hub file node, associated file node, general file node, and a heading node whose properties contain `P3_PROJECT`. Assert only level-0/file nodes with the matching file-level value pass.

- [ ] **Step 2: Add RED tests for project-find-note**

Stub `p3/org-roam-project-context` to `"hub"`, `org-roam-node-read` to verify `require-match` and the supplied filter, and `org-roam-node-visit` to capture the selected node. Assert the command uses normal Org-roam completion and visits only a matching file node.

- [ ] **Step 3: Add RED tests for project-new-note capture**

Cover both:

```elisp
(ert-deftest p3-org-roam-project-new-note-errors-without-context () ...)
(ert-deftest p3-org-roam-project-new-note-injects-file-project-property () ...)
```

Stub `read-string` to a title, `org-roam-capture-` to record its template, and assert the generated file head contains exactly one `P3_PROJECT: hub-id` while remaining in the existing timestamp/slug flat-file pattern. Do not require a project-specific directory or tag.

- [ ] **Step 4: Implement discovery and capture**

`p3/org-roam-project-find-note` should call `org-roam-node-read` with a filter function and `require-match=t`, then `org-roam-node-visit`.

`p3/org-roam-project-new-note` should:

```text
resolve/validate active hub or user-error
read a new note title
create a new Org-roam node for that title
invoke org-roam-capture- with a one-off normal file+head template
head includes P3_PROJECT=<hub-id>; Org-roam supplies the node ID
leave body at %? for ordinary interactive capture
```

Do not call `p3/org-roam-project-note` implicitly when context is absent.

- [ ] **Step 5: Run focused tests and commit Task 4**

```bash
git add lisp/p3-org-roam.el test/p3-org-roam-test.el
git commit -m "feat: add project-aware Org-roam capture and discovery"
```

---

### Task 5: Native project TODO Agenda with dynamic-binding-safe refresh

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `test/p3-org-roam-test.el`

**Interfaces:**
- Consumes: project context; `p3/org-roam-list-notes`; native `org-tags-view`/Agenda state.
- Produces:
  - buffer-local `p3/org-roam-project-agenda-hub-id`.
  - `p3/org-roam--project-todos (hub-id) -> agenda-buffer`.
  - interactive `p3/org-roam-project-agenda-redo ()` reading only the buffer-local hub ID.
  - interactive `p3/org-roam-project-todos ()` resolving current context and delegating to the generator.

- [ ] **Step 1: Add RED tests for dynamic Agenda state**

Stub `org-tags-view` so it records dynamically visible values of `org-agenda-files`, `org-use-property-inheritance`, and match string. Start with sentinel global values and assert after `p3/org-roam--project-todos` returns they are restored exactly.

Expected during generation:

```elisp
org-use-property-inheritance => '("P3_PROJECT")
org-agenda-files              => unique files from `p3/org-roam-list-notes`
match                         => property match for the exact hub ID
todo-only                     => non-nil
```

- [ ] **Step 2: Add RED tests for refresh state under dynamic binding**

Create a temporary `org-agenda-mode`-like buffer, set `p3/org-roam-project-agenda-hub-id` buffer-locally to `"hub-a"`, then call `p3/org-roam-project-agenda-redo` while no dynamically bound local `hub-id` variable exists. Stub `p3/org-roam--project-todos` and assert it receives `"hub-a"`.

Also assert generation installs an `org-agenda-redo-command` that calls the named refresh function, not a lambda.

- [ ] **Step 3: Run focused tests and confirm RED**

Expected: missing Agenda project functions/variable.

- [ ] **Step 4: Implement the Agenda generator**

Use:

```elisp
(let ((org-agenda-files (delete-dups (p3/org-roam-list-notes)))
      (org-use-property-inheritance '("P3_PROJECT")))
  (org-tags-view t (format "P3_PROJECT=\"%s\"" hub-id)))
```

After `org-tags-view` creates/selects the Agenda buffer, set in that buffer:

```elisp
(setq-local p3/org-roam-project-agenda-hub-id hub-id)
(setq-local org-agenda-redo-command '(p3/org-roam-project-agenda-redo))
```

`p3/org-roam-project-agenda-redo` must read `p3/org-roam-project-agenda-hub-id` from the current Agenda buffer and call `p3/org-roam--project-todos` with it. It must not depend on a lambda closure or a dynamic local variable that disappeared after the initial command.

- [ ] **Step 5: Add a small real-Org inheritance regression test**

Use temporary Org content containing file-level project membership, an ancestor heading override, and a descendant override. Test the property resolution helper used by command context and verify the Agenda query is configured with selective `P3_PROJECT` inheritance only. Do not test Org's internal matcher implementation.

- [ ] **Step 6: Run focused tests and commit Task 5**

```bash
git add lisp/p3-org-roam.el test/p3-org-roam-test.el
git commit -m "feat: add project-scoped Org agenda"
```

---

### Task 6: Persistence registration, command surface, and full regression verification

**Files:**
- Modify: `lisp/p3-org-roam.el`
- Modify: `lisp/p3-config-org-roam.el`
- Modify: `test/p3-config-org-roam-test.el`
- Modify only if needed for smoke assertion: `.github/workflows/emacs-tests.yml`

**Interfaces:**
- Consumes: all five commands from Tasks 2–5.
- Produces:
  - `p3/org-roam-project-command-map` with exactly five entries:
    - `h` -> `p3/org-roam-project-note`
    - `f` -> `p3/org-roam-project-find-note`
    - `n` -> `p3/org-roam-project-new-note`
    - `a` -> `p3/org-roam-project-associate`
    - `t` -> `p3/org-roam-project-todos`
  - global prefix `C-c n p` wired declaratively through `use-package` `:bind-keymap`.
  - `p3/org-roam-project-associations` present in `savehist-additional-variables`.

- [ ] **Step 1: Add RED configuration-boundary tests**

Extend `test/p3-config-org-roam-test.el` with helpers for `:bind-keymap` if needed and assertions equivalent to:

```elisp
(ert-deftest p3-config-org-roam-registers-project-associations-with-savehist ()
  (let ((contents ...))
    (should (string-match-p
             (regexp-quote "p3/org-roam-project-associations")
             contents))
    (should (string-match-p
             (regexp-quote "savehist-additional-variables")
             contents))))

(ert-deftest p3-config-org-roam-binds-project-prefix ()
  (should
   (member '("C-c n p" . p3/org-roam-project-command-map)
           (p3-config-org-roam-test--keyword-values :bind-keymap))))
```

Also add a behavior test asserting the command map contains exactly the five intended operations and no sixth project-management command.

- [ ] **Step 2: Run the two Org-roam test files and confirm RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-org-roam-test.el \
  -l test/p3-config-org-roam-test.el \
  -f ert-run-tests-batch-and-exit
```

- [ ] **Step 3: Add the command map and config wiring**

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

In `p3-config-org-roam.el`, declare `savehist-additional-variables`, register the association variable after loading the behavior module, and add:

```elisp
:bind-keymap
("C-c n p" . p3/org-roam-project-command-map)
```

Do not replace any existing `C-c n` bindings.

- [ ] **Step 4: Update the Org-roam smoke assertion only if necessary**

If current smoke loading already accepts the new code, leave the workflow untouched. If a new required public surface should be protected, extend the existing Org-roam smoke assertion to require `keymapp p3/org-roam-project-command-map` and `fboundp 'p3/org-roam-project-note`; do not create another CI job.

- [ ] **Step 5: Run byte compilation with warnings as errors for touched modules**

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile \
  lisp/p3-org-roam.el \
  lisp/p3-config-org-roam.el
```

Expected: zero warnings/errors.

- [ ] **Step 6: Run the complete ERT suite using the repository CI command**

Run the same `emacs -Q --batch -L lisp ... -f ert-run-tests-batch-and-exit` test list in `.github/workflows/emacs-tests.yml`, including all existing test files. Expected: zero unexpected results; only the repository's pre-existing intentional skips, if any.

- [ ] **Step 7: Verify scope against the design**

Run:

```bash
git diff master...HEAD -- lisp test .github
```

Confirm:

```text
p3-project.el unchanged
no new runtime module
no project-specific Org-roam directory logic
no custom task database/buffer
no title/tag/backlink/Git-remote inference
no live-buffer/database reconciliation state
no worktree/Forge/build-system additions
```

- [ ] **Step 8: Commit Task 6**

```bash
git add lisp/p3-org-roam.el lisp/p3-config-org-roam.el test/p3-org-roam-test.el test/p3-config-org-roam-test.el .github/workflows/emacs-tests.yml
git commit -m "feat: wire project-aware Org-roam workflow"
```

Only add `.github/workflows/emacs-tests.yml` if it actually changed.

---

## Final Review Gate

Before opening a PR:

- [ ] Compare the implementation against every success criterion in `docs/superpowers/specs/2026-09-14-project-aware-org-roam-design.md`.
- [ ] Confirm `git diff master...HEAD -- lisp/p3-project.el` is empty.
- [ ] Confirm `p3-org-roam.el` still has no `lexical-binding: t` cookie.
- [ ] Confirm hub mapping is written only after durable self-marking metadata exists.
- [ ] Confirm ordinary association never calls `save-buffer` implicitly.
- [ ] Confirm descendant command context and Agenda inheritance agree on nearest explicit heading/ancestor membership.
- [ ] Confirm Agenda refresh works after the initial dynamic bindings have unwound.
- [ ] Confirm existing tag-based `p3/org-roam-get-agenda`, tagged capture, search, and Org-roam bindings remain green.
- [ ] Run the full Linux CI-equivalent test/byte-compile commands locally or rely on a green GitHub Actions run before merge.
