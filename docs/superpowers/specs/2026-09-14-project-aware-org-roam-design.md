# Project-aware Org-roam workflow design

## Goal

Connect the existing `project.el` workspace model to Org-roam so each logical software/data project can have a durable literate context without turning Org-roam into a project-folder hierarchy or creating a second project/task database.

The durable logical identity is the Org ID of a project hub note. Filesystem projects remain identified by normalized `project.el` roots. A small machine-local association connects those two domains.

This design implements GitHub issue #25 as one focused feature. It deliberately reuses existing project, Org-roam, Org Agenda, and persistence mechanisms.

## Existing boundaries

The current repository already has the right owners:

- `lisp/p3-project.el` owns filesystem project identity and normalized roots through `p3/project-root` and `p3/project-normalize-root`.
- `lisp/p3-org-roam.el` owns reusable Org-roam workflow behavior.
- `lisp/p3-config-org-roam.el` owns package wiring, capture configuration, persistence registration, and keybindings.
- `savehist` is already enabled for machine-local Emacs state.

The implementation must preserve those boundaries. `p3-project.el` does not gain Org-roam knowledge, and Org-roam does not replace `project.el` as the filesystem project authority.

## Identity model

### Literate project identity

Each logical project has one hub Org-roam file node. The hub's Org `ID` is the durable project identity.

The hub marks itself with a file-level property:

```org
:PROPERTIES:
:ID: <hub-id>
:P3_PROJECT: <hub-id>
:END:
#+title: ji2
```

A wholly project-scoped Org-roam note stores the same hub ID in its own file-level `P3_PROJECT` property:

```org
:PROPERTIES:
:ID: <note-id>
:P3_PROJECT: <hub-id>
:END:
#+title: ji2 development
```

A heading inside a general-purpose note may instead carry an explicit heading-level `P3_PROJECT` property. That heading establishes project membership for its subtree through normal Org property inheritance unless a descendant heading has a nearer explicit override. File and heading membership are singular in v1.

A node is recognized as a project hub when its file node has an Org `ID` and its file-level `P3_PROJECT` equals that same ID.

Ordinary Org-roam links, backlinks, tags, note titles, filenames, Git remotes, repository names, and directory names are not project-membership truth.

### Filesystem association

A machine-local mapping connects normalized filesystem roots to hub IDs:

```text
normalized project.el root -> hub Org ID
```

The mapping lives in a small P3 variable owned by the Org-roam integration layer and is persisted through the existing `savehist` mechanism. No dedicated state file, serializer, registry, or database is added.

Before lookup or mutation, roots are normalized through `p3/project-normalize-root`. One root maps to at most one hub. A hub may be explicitly associated with multiple roots, including clones or future worktrees.

Absolute filesystem roots never need to be written into synced Org-roam notes or Git-tracked project files.

## Project context resolution

Commands that need a current literate project resolve it in this exact order:

1. the nearest explicit `P3_PROJECT` on the current Org heading or one of its ancestor headings, with the nearest explicit heading property winning;
2. file-level `P3_PROJECT` on the current Org-roam file;
3. current normalized `project.el` root through the machine-local root-to-hub mapping;
4. otherwise, no project context.

Heading lookup must therefore distinguish explicit heading/ancestor membership from file-level membership rather than asking only for the property at point. A descendant heading may explicitly override an ancestor's project, and an ancestor heading may intentionally establish project context for its whole subtree.

This precedence keeps command-level context consistent with the inheritance semantics used by the project TODO view. It also allows project commands to keep working after the user leaves a repository and enters a related Org-roam note under the separate Org-roam directory.

## Hub lifecycle

The primary hub command, conceptually `p3/project-note`, behaves differently depending on context.

When project context already resolves to a hub ID, it opens that hub after validating that the ID still resolves to a self-marked hub node.

When invoked from a filesystem project with no root mapping, it offers an explicit first-use association flow:

- select an existing Org-roam file node as the hub; or
- create a new ordinary Org-roam file node as the hub.

Selecting an existing node is explicit user choice, never title/name inference. An existing node may become a hub only when it is currently unassociated or already self-marked as a hub. A node already associated with a different project is not silently converted into another hub; the user must first explicitly change that membership through the association workflow.

The selected hub must have a resolvable Org ID. Establishing a new durable root-to-hub mapping is transactional with respect to the hub metadata:

1. if an existing unassociated note must be promoted to a hub and its live buffer was already modified before the operation, stop and ask the user to save or otherwise resolve those edits first;
2. write `P3_PROJECT=<its-own-ID>` to the hub note;
3. save that metadata successfully so the on-disk note is durably self-marked;
4. only then record the normalized root-to-hub association.

An already self-marked hub does not require a note save merely to add another root mapping. Creating a new hub follows the same ordering: normal Org-roam capture creates and saves the node with an Org ID and self-marking `P3_PROJECT`, and only after that durable metadata exists is the root mapping recorded.

The root mapping must never be persisted first and left pointing at hub metadata that existed only in an unsaved buffer. If hub establishment fails before the mapping step, no root association is created. A successfully saved self-marked hub with no mapping is harmless and can be associated explicitly later.

If a stored hub ID no longer resolves to a live self-marked Org-roam hub, the command reports a stale association and requires explicit repair or reassociation. It must not silently manufacture a replacement hub.

## Note and heading association

One user-facing association command supports association, reassociation, and disassociation without requiring manual property editing.

Target scope is deterministic:

- when point is inside an Org heading, the current heading is the default target;
- outside a heading, the current Org-roam file node is the target;
- a universal prefix argument targets the whole file even when point is inside a heading.

When the target has no explicit `P3_PROJECT`, the command associates it with a hub. The current resolved project is offered as the default when available; otherwise the user explicitly selects from self-marked hub nodes.

When the target already has an explicit `P3_PROJECT`, the command offers explicit change or remove behavior. Changing to a different hub requires confirmation. Removing membership deletes only the selected scope's explicit property.

Removing an explicit heading-level association does not mean "force this subtree to have no project." After removal, normal inheritance applies again: a nearer ancestor heading or the file-level project may become effective. V1 does not introduce a special no-project sentinel to suppress inherited membership.

Disassociating a file node must not remove explicit heading-level project properties inside that file.

For ordinary note/heading association, if the relevant Org file is already visiting a modified live buffer, the command mutates that buffer. It must never rewrite the file behind the buffer or save unrelated edits implicitly. Hub establishment is the deliberate exception because a durable root mapping must not point to unsaved hub metadata.

Unsaved ordinary association changes are immediately authoritative for context resolved from the live buffer. Org-roam database-backed selectors may not reflect those unsaved changes until the file is saved and Org-roam updates its database; this lag is accepted rather than adding live-buffer/database reconciliation machinery.

## Project-aware capture

A project-new-note command resolves the active hub and invokes normal Org-roam capture with project metadata injected into the new file node.

The resulting note remains an ordinary flat Org-roam node. Its file-level property drawer contains its own Org ID plus `P3_PROJECT=<hub-id>`.

The feature does not create project-specific directories, filenames, tag conventions, or a second capture engine.

If there is no project context, project-new-note fails clearly and directs the user to establish/open the project hub first. It does not guess a project or start an implicit identity-creation flow.

## Project note discovery

A project-find-note command resolves the active hub and uses normal Org-roam node completion filtered to file nodes whose file-level `P3_PROJECT` equals the hub ID.

The result includes the hub itself and other explicitly associated file nodes.

A general-purpose note that merely contains a project-associated heading is not considered a project-scoped file and does not appear in this selector.

No manually maintained hub index is required.

## Project TODO view

A project-todos command provides an ordinary Org Agenda TODO view across the Org-roam corpus for the resolved hub ID.

The query must use native Org property matching and Agenda behavior. During generation of the project view:

- the agenda corpus is the unique Org-roam file set;
- `P3_PROJECT` is the only property selectively inherited for the query;
- unfinished TODOs matching the active hub ID are included;
- the nearest explicit heading-level `P3_PROJECT` overrides more distant ancestor/file membership;
- temporary agenda/query state is dynamically scoped and restored after generation.

The resulting buffer remains a normal Org Agenda surface, preserving TODO state changes, scheduling/deadlines, priorities, and source navigation.

The project Agenda buffer stores the resolved hub ID in a dedicated buffer-local variable. A named refresh/reinvoke function reads that buffer-local value and regenerates the same project-scoped view under the same temporary bindings. Do not rely on a lambda closure capturing `hub-id`: `p3-org-roam.el` intentionally retains dynamic binding, so refresh state must be explicit. Refresh therefore remains project-aware without leaving `org-agenda-files`, `org-use-property-inheritance`, or related global state modified between operations.

The existing global/tag-based Org-roam agenda command remains independent and unchanged in semantics.

## User-facing surface

The feature remains conceptually limited to five operations:

```text
project-note        open/create/repair the current project's hub
project-find-note   choose among file nodes explicitly belonging to the project
project-new-note    capture a new file node already associated with the project
project-associate   associate/reassociate/disassociate a note or heading
project-todos       show unfinished project TODOs in native Org Agenda
```

Exact Lisp names and keybindings follow repository naming conventions during implementation. No dashboard, project browser, custom task editor, or parallel graph UI is added.

## Persistence

The root-to-hub association variable is registered with the existing `savehist` configuration from the Org-roam configuration boundary so it survives Emacs restarts on the same machine.

Persistence requirements:

- state is machine-local;
- paths are normalized before storage;
- a new root mapping is added only after required hub metadata has been saved durably;
- no credentials or sensitive contents are involved;
- no new state file format or migration system is introduced;
- stale hub IDs are detected when resolved, not automatically repaired.

The design does not persist derived note lists, TODO results, Org-roam query caches, or duplicated project metadata outside Org itself.

## Failure behavior

The implementation favors visible failure over implicit identity repair.

- Missing filesystem project root: fail clearly.
- Root already mapped to a different hub: require explicit reassociation.
- Stored hub ID missing from Org-roam or no longer self-marked: report stale association and require repair/reassociation.
- File/heading already associated with another hub: require explicit change/reassociation.
- Existing node proposed as a new hub while associated with another project: reject until membership is explicitly changed.
- Existing unassociated node proposed as a hub while its live buffer already has unsaved edits: require the user to save or resolve those edits before hub promotion.
- Failure to save required hub metadata: do not create the root mapping.
- Ordinary link/backlink/tag/title/name similarity: never creates membership.
- Modified live note buffer during ordinary note/heading association: mutate the live buffer; never rewrite behind it or save unrelated edits.
- Unsaved ordinary association metadata may remain absent from database-backed selectors until save/index; do not add reconciliation state to compensate.
- Missing Org-roam database/package state: surface an actionable command error without corrupting mappings or note metadata.

## Code boundaries

### `lisp/p3-org-roam.el`

Owns:

- root-to-hub association data and lookup/mutation helpers;
- hub recognition, resolution, and stale-association checks;
- context precedence including nearest ancestor-heading membership;
- file/heading membership helpers;
- project hub/open workflow;
- project-aware capture behavior;
- filtered project-node discovery;
- native Agenda project TODO query and named buffer-local refresh behavior.

The existing dynamic-binding contract in this file is preserved. Long-lived callback state such as Agenda refresh context must therefore live in explicit buffer-local/state variables rather than lexical closures.

### `lisp/p3-config-org-roam.el`

Owns only declarative wiring:

- command declarations;
- capture/package integration where required;
- registration of the association variable with existing `savehist` state;
- keybindings for the small project-aware surface.

### `lisp/p3-project.el`

Remains unchanged. The Org-roam integration reuses its existing root and normalization APIs and does not move literate project state into the shared filesystem-project foundation.

### Tests

Extend the focused Org-roam test boundary rather than building an integration-test framework.

## Testing strategy

Implementation proceeds test-first. Behavioral coverage includes:

- normalized root-to-hub association and lookup;
- persistence variable registration without introducing a new state store;
- one root cannot silently map to multiple hubs;
- one hub may be explicitly mapped from multiple roots;
- hub recognition requires `ID == P3_PROJECT` at file scope;
- context precedence: nearest heading/ancestor override, file, filesystem mapping, none;
- descendant headings inherit ancestor project context unless they explicitly override it;
- stale/non-self-marked hub association detection;
- explicit existing-node hub selection and new-hub creation semantics;
- rejection of converting a note already associated with another project into a hub implicitly;
- hub promotion refusing pre-existing unsaved edits when durable metadata must change;
- root mapping being added only after required hub metadata is saved successfully;
- file-level association, reassociation, and disassociation;
- heading-level association and override behavior;
- removing a heading override exposing normal ancestor/file inheritance rather than creating no-project state;
- deterministic heading/file target scope including prefix behavior;
- file disassociation preserving explicit heading associations;
- ordinary association mutating a modified live buffer without saving unrelated edits;
- accepted database lag for unsaved ordinary association changes;
- project-aware capture injecting the correct hub ID;
- no-context project capture failing without guessing;
- project node filtering excluding general notes with only associated headings;
- project TODO query using only `P3_PROJECT` inheritance;
- Agenda/query globals restored after invocation;
- Agenda refresh using explicit buffer-local hub state and re-establishing project scope under dynamic binding;
- existing tag-based Org-roam listing, search, capture, and agenda behavior remaining green.

Tests should stub Org-roam/project APIs and temporary files/buffers where practical rather than depending on the developer's real Org-roam database or filesystem projects.

## Non-goals

This issue does not add:

- a new project abstraction;
- a notes or task database;
- multi-project membership for one file/heading;
- a special no-project sentinel for suppressing inherited project membership;
- backlinks or tags as project membership;
- project-specific Org-roam directories;
- automatic project inference from names, paths, or Git remotes;
- live-buffer/Org-roam-database reconciliation for unsaved association metadata;
- a dashboard or custom Agenda replacement;
- meeting-specific storage machinery;
- worktree lifecycle management;
- Forge/GitHub integration;
- project task execution/build commands;
- background synchronization or monitoring.

Recurring meeting series remain ordinary project-associated Org-roam notes with dated headings unless the user intentionally creates separate nodes for particular meetings.

## Success criteria

The implementation is complete when:

1. a filesystem project can be explicitly mapped to one durable Org-roam hub by hub ID, with required hub metadata saved before the mapping is recorded;
2. the mapping survives Emacs restart through existing machine-local persistence;
3. project context works both from source repositories and associated Org-roam notes, including inherited ancestor-heading context;
4. whole notes and individual headings can be explicitly associated without hidden inference;
5. new project notes inherit membership automatically through normal Org-roam capture;
6. project file nodes can be found through normal Org-roam completion;
7. unfinished project TODOs aggregate through native Org Agenda with scoped `P3_PROJECT` inheritance and dynamic-binding-safe project-aware refresh;
8. global/tag-based Org-roam behavior remains independent;
9. stale/conflicting identities require explicit repair instead of silent replacement; and
10. the implementation adds no second project, notes, task, or persistence framework.
