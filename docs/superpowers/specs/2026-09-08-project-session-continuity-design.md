# Project and Session Continuity Design

**Issue:** #29

## Goal

Make returning to a project feel continuous without introducing a second project model or a session-management framework.

The intended workflow is:

- `project.el` remains the only filesystem project identity layer;
- each frame has at most one project tab per normalized project root;
- switching projects reuses that tab when it exists in the selected frame and otherwise creates it;
- an existing project tab keeps the window layout exactly as it was left;
- a new project tab starts in coherent project-root context before project-file selection begins;
- after switching, `consult-project-buffer` immediately exposes the project's live buffers and recent files;
- recent-file history survives Emacs restarts;
- reopening a file restores point where appropriate;
- restarting Emacs does **not** recreate old project tabs or window layouts.

This is intentionally lean continuity rather than full session restoration.

## Current state

The repository already has the needed foundations:

- `p3-project.el` provides canonical `project.el` root discovery;
- `p3-config-project.el` exposes the native project prefix map;
- `p3-config-workspace.el` owns window/navigation behavior;
- `C-x b` is `consult-buffer`;
- `init.el` already records an already-open file as recent after a successful `consult-buffer` switch.

What is missing is persistent recent-file state, cursor restoration, and a project-tab integration layer.

## Identity model

A project workspace is identified only by the normalized `project.el` root.

The tab name is presentation state, not identity. Renaming a tab must not create a second project or break reuse.

Normalization must make equivalent spellings of the same local root compare equal. The implementation should use the smallest reliable normalization needed for local project roots and must not invent a persistent project registry.

Tab Bar is frame-local. Project-tab uniqueness therefore applies within each frame. Separate frames may independently contain a workspace for the same normalized project root; enforcing process-wide uniqueness would require cross-frame coordination that this design deliberately avoids.

A running Emacs session may contain ordinary non-project tabs. They remain outside this model.

## Project switch behavior

The normal project-switch command should become a direct continuity action rather than a dispatch menu.

Conceptually:

```text
choose project
    -> normalize project root
    -> find existing tab for that root in the selected frame
       -> switch to it, preserving its layout
       OR
       -> create a new project tab rooted in that project
    -> invoke consult-project-buffer for that project
```

The selected project becomes the current project context before `consult-project-buffer` runs. A newly created tab must already have a buffer/default directory rooted in the selected project so canceling the Consult prompt does not leave a tab that claims one project while displaying another project's context.

If the project already has a tab, switching must not rearrange, reopen, or otherwise reconstruct the tab's windows. `consult-project-buffer` appears only as the minibuffer selection surface.

All ordinary project commands remain available through the native project prefix map even though project switching itself becomes resume-oriented.

## Tab ownership and metadata

Project-tab behavior belongs to the existing project/workspace boundary, not to a new subsystem.

A project tab needs enough tab-local metadata to associate it with a normalized project root. That metadata is runtime presentation/session state only.

The implementation must not maintain a separate durable list of projects or serialize project-tab metadata across Emacs restarts.

If duplicate tabs in one frame claim the same normalized root, the code should converge on one canonical project tab rather than allow two parallel workspaces for the same project in that frame. Reconciliation should prefer preserving an existing useful project tab over creating another one.

## Recent files and `C-x b`

Enable native `recentf-mode` so file recency persists across Emacs restarts.

`C-x b` remains the global `consult-buffer` command. It should continue to combine:

- live buffers, ordered by Consult's normal buffer behavior;
- recent files that are not already represented by live buffers;
- other existing Consult sources such as bookmarks/registers.

Do not make `C-x b` project-only and do not build a custom MRU list.

Recent files should retain `recentf`'s recency ordering. A file that is already open should not appear again as a duplicate recent-file candidate.

Preserve the existing Consult-to-`recentf` behavior in `init.el` unless an equivalent native mechanism is demonstrated. In particular, switching back to an already-open file through Consult should continue to refresh its practical recency so that, after the buffer is later closed, the file still appears near the top of recent files.

## Project-scoped re-entry

`consult-project-buffer` is the project re-entry surface.

After a project switch it should show only the selected project's:

- live project buffers;
- recent project files;
- project root candidate supplied by Consult.

This uses Consult's existing project/recent-file filtering rather than a custom project recent-file database.

## Persistence across Emacs restarts

Enable native `save-place-mode` so reopening a file restores point where appropriate.

Across restarts, persist only lightweight file-oriented continuity:

- `recentf` history;
- `save-place` positions.

Do **not** automatically restore:

- project tabs;
- window splits/layouts;
- live subprocesses;
- ESS/R sessions;
- terminals;
- Python shells;
- Magit, Help, compilation, or other transient buffers.

On first return to a project after restarting Emacs, create a fresh project tab and use `consult-project-buffer` to expose the project's persistent recent files. Reopening one of those files restores its saved position.

This design deliberately does not use `desktop.el`. Full desktop restoration was rejected because startup should remain clean; per-project lazy desktop snapshots were rejected because they would require a custom project-keyed session layer.

## Workspace history

Use native Tab Bar as the workspace surface.

`tab-bar-history-mode` should replace `winner-mode` as the window-configuration history mechanism so the configuration does not maintain two overlapping history systems once project tabs are authoritative for workspaces.

This replacement must preserve practical window undo/redo behavior within the active tab.

## Ownership

Keep implementation within existing owners:

- `lisp/p3-project.el` — reusable normalized-root and project-tab identity/reuse behavior;
- `lisp/p3-config-project.el` — project-switch wiring and project command integration;
- `lisp/p3-config-workspace.el` — Tab Bar and tab-history configuration;
- `lisp/p3-config-base.el` — global `recentf-mode` and `save-place-mode` persistence settings;
- `init.el` — retain or narrowly adjust the existing Consult -> `recentf` advice only if needed to preserve already-open-file recency.

Do not create a new workspace/session module unless implementation reveals a real ownership problem that cannot fit these existing boundaries.

## Failure and stale-state behavior

Continuity must never make startup or project switching fragile.

- A missing project root must not create a fake project tab or replacement identity.
- Canceling project-buffer selection after creating a tab must leave that tab in coherent selected-project context.
- A deleted recent file should be ignored/pruned through normal `recentf` behavior.
- A file that cannot be reopened should fail as an ordinary file-open operation, not as a workspace failure.
- Duplicate project tabs for one normalized root within a frame should be reconciled to one canonical tab.
- Non-project tabs must remain untouched.
- Missing or stale runtime tab metadata may be discarded without affecting `project.el` identity.
- No stale continuity state should prevent normal Emacs use.

## Non-goals

- No `desktop.el` session restore for v1.
- No per-project serialized window-layout snapshots.
- No custom session database.
- No project registry separate from `project.el`.
- No process-wide cross-frame workspace registry.
- No Projectile, Perspective, eyebrowse, Burly, activities, or other workspace framework.
- No project dashboard.
- No restoration of subprocess/transient buffers.
- No project-specific replacement for `recentf`.
- No change to Org-roam project identity; issue #25 remains independent.

## Testing

Tests should protect durable behavior rather than source spelling.

Cover at least:

- equivalent project-root spellings normalize to one workspace identity;
- a project root maps to at most one active project tab in a frame;
- switching to an existing project tab preserves its current window configuration;
- switching to a new project creates one project tab and establishes project context before Consult selection;
- canceling project re-entry leaves the new tab rooted in the selected project;
- project switching hands off to project-scoped Consult selection;
- non-project tabs are not absorbed into the project model;
- duplicate project-tab state within a frame is reconciled safely;
- `recentf-mode` and `save-place-mode` are enabled persistently;
- the existing already-open-buffer recency behavior remains effective;
- no desktop/session restoration occurs at startup;
- stale/missing project or recent-file state degrades without breaking startup or ordinary project commands.

Avoid tests that freeze exact helper names, tab display names, comments, or incidental implementation forms.

## Acceptance criteria

- `project.el` remains the sole filesystem project identity layer.
- Within each frame, one normalized project root maps to at most one active project tab.
- Separate frames may independently contain the same project without a cross-frame registry.
- Normal project switching reuses an existing project tab or creates one when absent.
- A newly created project tab has selected-project context before Consult selection, including when selection is canceled.
- Reusing a project tab does not alter its existing window layout.
- After switching, `consult-project-buffer` immediately presents that project's live buffers and recent files.
- `C-x b` remains global `consult-buffer` and includes persistent recent files without duplicate live-buffer entries.
- Switching to an already-open file through Consult continues to update practical recency.
- Recent-file history persists across Emacs restarts.
- Reopening a file restores its previous point where appropriate.
- Emacs startup does not restore old project tabs, window layouts, or subprocesses.
- First project use after restart creates a fresh tab and exposes prior project files through recent-file history.
- Native Tab Bar is the workspace surface and Tab Bar history replaces overlapping `winner-mode` window history.
- Missing files, missing roots, stale tab metadata, and duplicate tabs do not prevent normal Emacs use.
- Non-project tabs remain possible.
- No custom session database, serialized per-project layout store, duplicate project model, cross-frame registry, or third-party workspace framework is introduced.
