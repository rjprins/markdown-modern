# Changelog

All notable changes to markdown-modern are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Fixed

- A table whose delimiter row has spaces around the dashes, such as
  `| --- | --- |`, no longer shows that row as a row of `---` cells. It now
  draws as the line under the header, as `|---|---|` already did.

## [2.2.0] - 2026-11-16

### Changed

- Text keeps a reading width, like the content column of a Markdown renderer.
  Paragraphs, tables and code blocks wrap at `markdown-modern-text-width`
  columns (now 80) instead of at the window edge. The width is measured in the
  buffer's font, as in writeroom-mode, and follows text scaling. Set it to `nil`
  for the full window width. Line numbers and another package's left margin
  come on top, and the horizontal-scroll view (`C-c C-v t`) uses the whole
  window. markdown-modern leaves the margins alone while
  `visual-fill-column-mode` or `olivetti-mode` is on, or when another package
  has set the right margin.
- New windows such as `*Help*` or Magit still open beside a wide
  markdown-modern window. Emacs splits side by side only when the text area is
  at least `split-width-threshold` columns wide, so markdown-modern advises
  `window-splittable-p` to count its reading margin as width. Set
  `markdown-modern-advise-window-splittable-p` to `nil` to leave
  `window-splittable-p` alone.
- Paragraphs show their lines as written by default, so line commands such as
  `C-k` act on what you see and nothing changes while you type.
  `markdown-modern-join-paragraph-lines` now defaults to `nil`; set it to `t`
  to show single newlines as spaces again.

### Fixed

- `TAB` on a heading folds it again, and `S-TAB` folds the whole buffer.
  `TAB` on a list item nests it. Both inserted spaces instead, because the
  check for a heading or list item looked only at the innermost syntax node.
  A `#` line in a code block no longer counts as a heading when folding.
- `C-c <up>` and `C-c <down>` move a whole list item, with its nested items
  and continuation lines, past the whole item next to it. They moved single
  lines, which could split items and orphan nested ones. An item no longer
  moves into the next list.
- `C-c <left>` and `C-c <right>` change the level of an item together with
  its nested items and continuation lines. The first item of a list is not
  nested, since there is no item above to nest it under.
- `M-RET` adds the new item after the whole item at point, so it no longer
  lands between an item's first line and the rest of its text, or between
  an item and its nested items. It keeps `)` after a number, continues a
  numbered list from a continuation line, and keeps a loose list loose.
- The `C-c '` editor edits a copy of the code in a buffer of its own, as
  `org-mode` does, and writes it back when you finish. It was an indirect
  buffer narrowed to the block, which caused several problems:
  - A line typed at the end of the editor joined the closing fence and left
    the block unclosed.
  - Indentation saw the whole Markdown file, so `RET` could move a line to
    the left edge.
  - Code in a list item or quote lost the item's indentation or the `>`.
  - Aborting marked the file modified, and closing the editor left its window
    behind.
  Now aborting, or killing the editor buffer, leaves the block as it was.
  Finishing changes the file only if the code changed, and point goes to
  the same place in the code. The editor buffer is named
  `*MdM-Edit:LANGUAGE*`.
- Rendering a shell code block no longer shows "Setting up indent for shell
  type" in the echo area.
- Text whose parse changes because of an edit elsewhere is drawn again. After
  `TAB` added an empty row to a table, the next table stayed raw text even
  once the row had content. Tree-sitter reads a row of empty cells as the
  line under a table header, so until you type in it, the tables below show
  as text.
- Tables fit the window again after it is split or resized. They kept the
  old width, so a wide table wrapped into a broken box until point entered
  it.
- The later source lines of a list item start where its text starts. They
  showed their indentation in the proportional font, so they started left
  or right of the item's first line.
- Horizontal rules span the text and never wrap. They were 40 line
  characters, which wrapped onto a second line at a large text size or in a
  narrow window. A terminal still shows characters, as many as fit.
- Math with a script inside a script, such as `e^{-x^2}`, no longer shows a
  stray `^`.
- Bold text keeps the styles around and inside it: `~~struck **bold**~~` is
  struck through, `***bold italic***` is italic, and code inside bold keeps
  its colour. The bold face inherited `default`, which overrode them.
- Indented code blocks (four spaces deep) show as code, in the code font
  and with the code background. They showed as plain text.
- An escaped pipe (`\|`) in a table cell stays in the cell, in the drawn
  table and in the row you edit. It split the cell in two.
- A backslash escape such as `\*` shows as `*`, and a backslash that ends a
  line for a hard break is hidden. Point next to one shows the backslash.
- In a list nested four spaces deep, the first item under each parent shows a
  bullet instead of a raw `-`, and its wrapped text lines up.
- Bullets follow the nesting level however deep it is indented, so a
  second-level item nested four spaces deep shows `○`, not `■`.
- HTML export keeps the document's structure. A code block inside a list item
  no longer turns the rest of the page into escaped text. `~~~` fences and
  indented code export as code, and indented lines inside a fence stay in the
  code block. Nested lists, nested quotes and a list inside a quote export as
  nested HTML.
- HTML export honours backslash escapes and hard line breaks (two trailing
  spaces or a trailing backslash). Math is exported as written, without
  emphasis inside, and underscores inside words stay as they are. Two
  emphasis spans in one paragraph stay two spans, and nested emphasis exports
  as nested HTML.
- HTML export escapes `<` and `&` in text and keeps raw HTML such as
  `<details>` and `<kbd>`. Link titles, reference links, autolinks and table
  column alignment export too. Link addresses are kept as written, without
  math or emphasis inside, and emphasis does not pair across a link.

### Removed

- `markdown-modern-list-item-bounds`, `markdown-modern-list-level-at-point`
  and `markdown-modern-list-marker-at-point`. The list commands no longer use
  them; they find items in the parse tree.
- `markdown-modern-manage-text-width`. The reading width is now always on and
  no longer sets `fill-column` or turns on `visual-fill-column-mode`.

## [2.1.0] - 2026-11-01

Thanks to Hemant Kumar ([@gnufied](https://github.com/gnufied)) for local file
links and the `C-c '` and link click fixes. Thanks to Samuel Michael Vanie
([@SamuelVanie](https://github.com/SamuelVanie)) for the Mermaid changes.

### Added

- A diagram viewer. Click a Mermaid diagram, or press `C-c C-v d` in its source,
  to zoom and pan it. Press `f` to fit it to the window and `q` to go back.
- Local links open files of any type in Emacs, relative to the Markdown file.
  Line fragments such as `#L352` and `#L352-L365` go to that line. `M-,` goes
  back to the Markdown buffer. A missing file reports an error.
- Reference links render. `[text][label]`, `[text][]` and `[label]` show as
  links when the label is defined, and open with a click or `C-c C-o`.
  Definition lines such as `[label]: url` are dimmed.

### Changed

- A Mermaid diagram that uses a feature the renderer cannot draw, such as a
  subgraph or a composite state, shows its source instead of a partial diagram.
  An empty diagram shows its source too.

### Fixed

- Mermaid flowcharts keep chained edges (`A --> B --> C`) and statements
  separated by `;`. Circle and subroutine shapes, all line styles and all four
  directions work. A label given after a node's first use is no longer lost.
- Mermaid sequence diagrams draw a participant with an alias only once. Notes
  go where the source puts them, and `autonumber` works.
- Mermaid state diagrams keep transition labels out of state names, and start
  and end markers are no longer mixed up. Long transitions and loops get their
  own space. State descriptions and `direction` work.
- Mermaid class diagrams use the right arrow for each relationship. ER diagrams
  support all four cardinalities, dashed links and entities without links.
- Mermaid blocks work with `~~~` and longer fences, and with a `%%` comment
  before the diagram type. Diagrams pick up new colors after a theme change.
- Nested list items show their bullet, number or checkbox again. Since 2.0.0
  only the first level had one.
- Bold italic text such as `***both***`, and bold inside italic, no longer
  disappears.
- A line break right before or after inline code now joins like any other
  line break in a paragraph.
- Wrapped list item text lines up with the text, not the marker, also when
  the item goes on over several source lines. Numbered items line up in
  proportional fonts too.
- Text after list bullets and task checkboxes starts at the same position, also
  on wrapped lines, with fallback fonts and after a text size change.
- `C-c '` could open an empty edit buffer when Tree-sitter skipped the code
  block's content node. It now shows the block's contents.
- Clicking a link label no longer reveals its markup before the link opens.
  A click in another window follows the link in that window's buffer.

## [2.0.0] - 2026-10-09

This release requires Tree-sitter. After upgrading from 1.x, run
`M-x markdown-modern-install-grammars` once.

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
- `markdown-modern-join-paragraph-lines` set to `nil` shows paragraphs with
  their lines as written. It also works as a file-local variable.
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
  with a `↵` where they will join, so a new list item stays on its own line.
  The file's text does not change.

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
