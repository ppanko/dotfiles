# PPTX visual editor spike

This is a throwaway feasibility spike, not a supported part of the Emacs configuration yet.

The goal is deliberately narrow: open an existing PPTX, render a real slide inside Emacs, select ordinary top-level slide objects, move them with the mouse or arrow keys, and save a revised PPTX without rewriting the rest of the Office package.

## Why the bridge patches OOXML directly

A first prototype used `python-pptx` to save a modified deck. Although the rendered result was correct, that save rewrote many untouched package parts, including chart, master, and layout XML. That is too risky for arbitrary decks received from other people.

The bridge here instead reads PPTX geometry and changes only the target shape's `<a:off>` geometry in the target `ppt/slides/slideN.xml` member. Every other ZIP member is copied byte-for-byte.

The proof test used a deck containing text, an embedded raster image, a native chart object, and other shapes, then passed it through LibreOffice before editing. Moving the picture changed only `ppt/slides/slide1.xml`; all other package members were byte-identical. A before/after LibreOffice render changed only the region occupied by the moved picture.

## Requirements

- Emacs with SVG image support
- Python 3 (stdlib only; no `python-pptx` dependency)
- LibreOffice / `soffice`
- Poppler `pdftoppm`

## Try it

From this branch, evaluate:

```elisp
(load-file "~/path/to/dotfiles/spikes/pptx-editor/p3-pptx-spike.el")
```

Then run:

```text
M-x p3/pptx-spike-open
```

Choose a `.pptx` and slide number. The command makes a disposable working copy; it never edits the source file directly.

Controls:

- click: select a shape
- drag: move a shape and rerender the actual PPTX
- arrow keys: nudge the selected shape by 0.05 inch
- `g`: rerender
- `s`: save the edited working copy as a new PPTX
- `q`: quit and delete the temporary working directory

## Scope of this spike

Recognized top-level object types are ordinary shapes/text boxes (`sp`), pictures (`pic`), charts and other graphic frames (`graphicFrame`), and connectors (`cxnSp`). The spike does not attempt to edit SmartArt internals, grouped-object internals, animations, embedded Office objects, or arbitrary PowerPoint behavior.

The Python bridge has been exercised against LibreOffice in the spike environment. The Emacs file is included in the repository's byte-compile gate on this branch so the PR can validate it with a real Emacs runtime before this experiment is promoted further.
