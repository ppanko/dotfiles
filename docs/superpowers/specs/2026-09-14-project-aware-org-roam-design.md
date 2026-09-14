# Project-aware Org-roam workflow design

## Goal

Connect the existing `project.el` workspace model to Org-roam so each logical software/data project can have a durable literate context without turning Org-roam into a project-folder hierarchy or creating a second project/task database.

The durable logical identity is the Org ID of a project hub note. Filesystem projects remain identified by normalized `project.el` roots. A small machine-local association connects those two domains.

This design implements GitHub issue #25 as one focused feature. It deliberately reuses existing project, Org-roam, Org Agenda, and persistence mechanisms.

## Existing boundaries

The current repository already has the right owners:

- `lisp/p3-project.el` owns filesystem project identity and normalized roots through `p3/project-root` and `p3/project-normalize-root`.
- `lisp/p3-org-roam.el` owns reusable Org-roam workflow behavior.
- `lisp/p3-config-org-roam.el` owns package wiring, capture configuration, and keybindings.
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

A heading inside a general-purpose note may instead carry an explicit heading-level `P3_PROJECT` property. File and heading membership are singular in v1.

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

1. explicit `P3_PROJECT` on the current Org heading;
2. file-level `P3_PROJECT` on the current Org-roam file;
3. current normalized `project.el` root through the machine-local root-to-hub mapping;
4. otherwise, no project context.

Heading lookup must distinguish an explicit heading property from inherited file membership so a heading can intentionally override the surrounding file's project.

This precedence allows project commands to keep working after the user leaves a repository and enters a related Org-roam note under the separate Org-roam directory.

## Hub lifecycle

The primary hub command, conceptually `p3/project-note`, behaves differently depending on context.

When project context already resolves to a hub ID, it opens that hub.

When invoked from a filesystem project with no root mapping, it offers an explicit first-use association flow:

- select an existing Org-roam file node as the hub; or
- create a new ordinary Org-roam file node as the hub.

Selecting an existing node is explicit user choice, never title/name inference. The selected hub must have a resolvable Org ID, and its file-level `P3_PROJECT` is set to that same ID if needed. Creating a hub likewise creates a normal Org-roam file node, ensures it has an Org ID, sets `P3_PROJECT` to that ID, and records the normalized root-to-hub association.

If a stored hub ID no longer resolves to a live Org-roam node, the command reports a stale association and requires explicit repair or reassociation. It must not silently manufacture a replacement hub.

## Note and heading association

A single small user-facing association workflow supports explicit association, reassociation, and disassociation.

The target is either:

- the current Org heading; or
- the current Org-roam file node.

The interaction may use point/prefix conventions or a small scope prompt, but it must make the scope unambiguous before mutation.

Association writes `P3_PROJECT=<hub-id>` at the selected scope. Reassociation from a different existing project requires explicit confirmation. Disassociation removes only the selected scope's property.

Disassociating a file node must not remove explicit heading-level project properties inside that file.

If the relevant Org file is already visiting a modified live buffer, the command mutates that buffer or refuses safely. It must never rewrite the file behind the buffer or save unrelated edits implicitly.

## Project-aware capture

A project-new-note command resolves the active hub and invokes normal Org-roam capture with project metadata injected into the new file node.

The resulting note remains an ordinary flat Org-roam node. Its file-level property drawer contains its own Org ID plus `P3_PROJECT=<hub-id>`.

The feature does not create project-specific directories, filenames, tag conventions, or a second capture engine.

If there is no project context, the command fails clearly or routes through the explicit hub association/creation flow. It must not guess a project from names or links.

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
- direct heading-level `P3_PROJECT` overrides file-level membership;
- temporary agenda/query state is dynamically scoped and restored after generation.

The resulting buffer remains a normal Org Agenda surface, preserving TODO state changes, scheduling/deadlines, priorities, source navigation, and refresh.

Agenda refresh must re-establish the same project-scoped query without leaving `org-agenda-files`, `org-use-property-inheritance`, or related global state modified after the operation. A buffer-local redo/reinvoke mechanism is acceptable if needed to preserve native refresh behavior.

The existing global/tag-based Org-roam agenda command remains independent and unchanged in semantics.

## User-facing surface

The feature should remain conceptually limited to five operations:

```text
project-note        open/create/repair the current project's hub
project-find-note   choose among file nodes explicitly belonging to the project
project-new-note    capture a new file node already associated with the project
project-associate   associate/reassociate/disassociate a note or heading
project-todos       show unfinished project TODOs in native Org Agenda
```

Exact Lisp names and keybindings may follow repository naming conventions during implementation. No dashboard, project browser, custom task editor, or parallel graph UI is added.

## Persistence

The root-to-hub association variable is registered with the existing `savehist` configuration so it survives Emacs restarts on the same machine.

Persistence requirements:

- state is machine-local;
- paths are normalized before storage;
- no credentials or sensitive contents are involved;
- no new state file format or migration system is introduced;
- stale hub IDs are detected when resolved, not automatically repaired.

The design does not require persistence of derived note lists, TODO results, Org-roam query caches, or duplicated project metadata outside Org itself.

## Failure behavior

The implementation favors visible failure over implicit identity repair.

- Missing filesystem project root: fail clearly.
- Root already mapped to a different hub: require explicit reassociation.
- Stored hub ID missing from Org-roam: report stale association and require repair/reassociation.
- File/heading already associated with another hub: require explicit reassociation.
- Ordinary link/backlink/tag/title/name similarity: never creates membership.
- Modified live note buffer: mutate live buffer or refuse; never rewrite behind it.
- Missing Org-roam database/package state: surface an actionable command error without corrupting mappings or note metadata.

## Code boundaries

### `lisp/p3-org-roam.el`

Owns:

- root-to-hub association data and lookup/mutation helpers;
- hub resolution and stale-association checks;
- context precedence;
- file/heading membership helpers;
- project hub/open workflow;
- project-aware capture behavior;
- filtered project-node discovery;
- native Agenda project TODO query.

The existing dynamic-binding contract in this file is preserved unless implementation demonstrates a concrete need to change it.

### `lisp/p3-config-org-roam.el`

Owns only declarative wiring:

- command declarations;
- capture/package integration where required;
- `savehist` registration if wiring belongs at configuration level;
- keybindings for the small project-aware surface.

### `lisp/p3-project.el`

Remains unchanged unless a minimal reusable filesystem identity helper is demonstrably missing. Org-roam project association must not be moved into the shared project foundation merely for convenience.

### Tests

Extend the focused Org-roam test boundary rather than building an integration-test framework.

## Testing strategy

Implementation proceeds test-first. Behavioral coverage should include:

- normalized root-to-hub association and lookup;
- persistence variable registration without introducing a new state store;
- one root cannot silently map to multiple hubs;
- one hub may be explicitly mapped from multiple roots;
- context precedence: heading, file, filesystem mapping, none;
- stale hub association detection;
- explicit existing-node hub selection and new-hub creation semantics;
- file-level association, reassociation, and disassociation;
- heading-level association and override behavior;
- file disassociation preserving explicit heading associations;
- live modified buffer safety;
- project-aware capture injecting the correct hub ID;
- project node filtering excluding general notes with only associated headings;
- project TODO query using only `P3_PROJECT` inheritance;
- Agenda/query globals restored after invocation;
- Agenda refresh re-establishing project scope;
- existing tag-based Org-roam listing, search, capture, and agenda behavior remaining green.

Tests should stub Org-roam/project APIs and temporary files/buffers where practical rather than depending on the developer's real Org-roam database or filesystem projects.

## Non-goals

This issue does not add:

- a new project abstraction;
- a notes or task database;
- multi-project membership for one file/heading;
- backlinks or tags as project membership;
- project-specific Org-roam directories;
- automatic project inference from names, paths, or Git remotes;
- a dashboard or custom Agenda replacement;
- meeting-specific storage machinery;
- worktree lifecycle management;
- Forge/GitHub integration;
- project task execution/build commands;
- background synchronization or monitoring.

Recurring meeting series remain ordinary project-associated Org-roam notes with dated headings unless the user intentionally creates separate nodes for particular meetings.

## Success criteria

The implementation is complete when:

1. a filesystem project can be explicitly mapped to one durable Org-roam hub by hub ID;
2. the mapping survives Emacs restart through existing machine-local persistence;
3. project context works both from source repositories and associated Org-roam notes;
4. whole notes and individual headings can be explicitly associated without hidden inference;
5. new project notes inherit membership automatically through normal Org-roam capture;
6. project file nodes can be found through normal Org-roam completion;
7. unfinished project TODOs aggregate through native Org Agenda with scoped `P3_PROJECT` inheritance;
8. global/tag-based Org-roam behavior remains independent;
9. stale/conflicting identities require explicit repair instead of silent replacement; and
10. the implementation adds no second project, notes, task, or persistence framework.
