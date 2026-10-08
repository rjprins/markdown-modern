# Changelog

All notable changes to markdown-modern are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- `M-x markdown-modern-install-grammars` installs missing `markdown` and
  `markdown-inline` grammars. Setup errors identify missing grammars or
  Tree-sitter support, and opening a buffer does not download anything.
- The installer builds version 0.4.1 of both grammars. This version works with
  Tree-sitter libraries older than 0.25, and Emacs 31's `markdown-ts-mode` uses
  it too. Monthly and manual CI runs also test the newest upstream grammars.
- A README comparison explains this fork's changes from mark-graf.
- `markdown-modern-paragraph-reveal-delay` shows the source lines of the
  paragraph the cursor rests in, after that many seconds.
- `TAB` in the last cell of a table adds an empty row and moves into it.

### Changed

- Buffer editing and rendering now require Tree-sitter and both Markdown
  grammars. The regex fallback and internal opt-in switch were removed.
  Remove `markdown-modern-ts--use-tree-sitter` from existing configurations.
  Built-in HTML export keeps its separate text conversion.
- CI and test runners use Tree-sitter throughout, including code-span,
  math and fence-boundary regression coverage.

### Fixed

- `TAB` and `S-TAB` stop in empty table cells and skip escaped pipes.
  They also work in a row whose cells are all empty.
- Code-block editing keeps the source buffer's parsers alive and tracks edit
  boundaries as text grows, so abort restores the original content.
- Ordinary paragraph newlines now render as spaces, so
  source-wrapped prose flows to the window width. Explicit hard breaks and
  block boundaries stay visible. A paragraph you edit shows its source lines,
  so a new list item stays on its own line. The file's text does not change.

## [1.1.0] - 2026-10-05

### Added

- CI checks Emacs 30.1 and 31.1 with both parser paths on pushes, pull requests
  and a monthly schedule. Fresh Git and tarball installs are checked too.
- `make test-package` checks the release tarball in a temporary Emacs setup.
- `make melpa` builds the recipe with MELPA's `package-build` tool.
- Tree-sitter setup instructions and a script to refresh the README screenshot.
- Reveal-at-point now covers line-leading markers: a list bullet, an ordered
  marker, or a blockquote marker under or adjacent to point shows its raw
  source (`- `, `1. `, `> `) for editing, then re-renders on leave.
- Task checkboxes are now interactive widgets instead of revealed markup. Point
  on a checkbox keeps the rendered `☐`/`☑`; `SPC` toggles it, and
  `Backspace`/`Delete` on it removes the whole checkbox at once, leaving a plain
  list item.
- Obsidian-style in-place table editing. Entering a table no longer un-renders
  the whole box to raw pipes: every row stays a rendered grid except the row
  under point, which becomes editable while keeping its `│` borders pixel-aligned
  to the box above and below. The alignment re-flows live as you type (no change
  to the file's text), so a cell grows and shrinks without the borders jumping.

### Changed

- Release tarballs get their version and dependencies from the package header.
  They include the package descriptor, license, changelog and README images.
- Package lint runs on all libraries and fails the build on errors. Its tools
  are installed under `.build/` rather than in the user's Emacs setup.
- Tables no longer have a background colour; only the grid lines are tinted
  (grey foreground). The `markdown-modern-table`, `-table-header` and
  `-table-border` faces lost their `:background`.
- Revealed heading markers (`#`) now appear at the heading's size rather than
  the default size.
- List bullets now render in a fixed-pitch slot, so the rendered glyph (`●`) and
  the raw marker it replaces (`-`, `*`, `+`) are the same width. Revealing an
  unordered list marker at point no longer shifts the item's content sideways.
- Tables are now always sized to fit the window width, so a wide table no longer
  soft-wraps into a garbled block under `visual-line-mode`. Columns are narrowed
  to fit down to `markdown-modern-table-min-column-width`, after which cell
  content wraps onto multiple lines rather than being elided, so nothing is lost.
  `markdown-modern-table-max-cell-lines` caps how tall a cell may grow (ellipsis
  past that). Prose continues to wrap as before. Set
  `markdown-modern-table-max-width` to pin a fixed width instead. Multi-line
  cells respect `markdown-modern-left-margin`: the table inherits the margin
  uniformly so wrapped continuation lines stay aligned with the first line
  (rather than the buffer's `wrap-prefix` indenting only the continuations).
- New `markdown-modern-table-ascii-punctuation` (default nil). Some fonts draw
  glyphs like the em-dash from a proportional fallback font wider than one
  monospace cell, which misaligns the rendered table box. Enable this to fold
  such glyphs to ASCII (`—`→`--`, `→`→`->`, `…`→`...`, configurable via
  `markdown-modern-table-glyph-substitutions`) inside table cells only; the
  buffer text, the row being edited, and prose are untouched.

### Fixed

- All test commands now cover the eight suites, including the 17 LaTeX tests.
- The Mermaid image-cache test also runs on headless builds without SVG support.
- Git installs on Emacs 30 no longer try to byte-compile development helpers.
- Byte compilation no longer warns about obsolete `when-let` and `if-let`
  forms on Emacs 31.
- Rendering and reveal-at-point work again on Emacs 31 with the tree-sitter
  parser. Emacs 31 changed `treesit-node-at` so that, given a language symbol,
  it falls back to the buffer's first parser regardless of language; here that
  is the inline parser, so block lookups found no headings, lists, or tables.
  Elements then rendered partially or not at all, and nothing was revealed at
  point. Node lookups now go through the block parser object.

## [1.0.1] - 2026-05-30

### Fixed

- Code-block syntax highlighting is now actually applied. The `highlight-code`
  routine and the `markdown-modern-code-block-syntax-highlight` option existed
  but were never called by the renderer, and the highlight overlays were being
  created in a throwaway temp buffer rather than the source buffer. Both are
  fixed, so fenced code blocks are now highlighted using the language's major
  mode, layered over the code-block background.

## [1.0.0] - 2026-05-30

Initial release as **markdown-modern**, a fork of
[mark-graf](https://github.com/hyperZphere/mark-graf) by Marc Ansset,
re-architected on `jit-lock`.

### Added / Changed

- Viewport-driven rendering via `jit-lock` — only the visible region is
  rendered, so open/scroll cost is independent of file size.
- Single-mode reveal-at-point: the raw markup of the element under the cursor is
  shown for editing while its styling is preserved; no source/rendered toggle.
- Tables render at natural width, with a horizontal-scroll toggle
  (`markdown-modern-toggle-truncate-lines`) for tables wider than the window.
- `markdown-modern-visual-line` and `markdown-modern-variable-pitch` settings
  (default on); width management is opt-in via `markdown-modern-manage-text-width`.
- Tree-sitter parser path (opt-in) with a regex fallback; works either way.
- Inline markup rendered inside headings; code/table faces inherit `fixed-pitch`.
- ERT test suite and a rendering benchmark (`make bench`).
