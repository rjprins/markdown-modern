# Changelog

All notable changes to markdown-modern are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

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
