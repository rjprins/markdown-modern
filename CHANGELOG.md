# Changelog

All notable changes to markdown-modern are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/).

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
