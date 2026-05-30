# markdown-modern

Modern visual styling for Markdown buffers in Emacs.

markdown-modern renders Markdown inline — headings, emphasis, code, tables, images — using text properties and overlays, in the spirit of [org-modern](https://github.com/minad/org-modern). It reveals the raw markup of the element under the cursor for editing, rather than showing raw syntax or a split-pane preview.

markdown-modern is a fork of [mark-graf](https://github.com/hyperZphere/mark-graf) by Marc Ansset.

## Features

- **Inline WYSIWYG rendering** - Headings, bold, italic, code, links, images rendered in-place
- **Reveal-at-point editing** - The raw markup of the element under the cursor is shown for in-place editing, then re-rendered when you move away
- **Fast, viewport-driven rendering** - Powered by `jit-lock`, so only on-screen content is rendered
- **Full GFM support** - Tables, task lists, fenced code blocks, strikethrough
- **Syntax highlighting** - Code blocks highlighted using native Emacs modes
- **Image display** - Inline images with automatic scaling
- **Mermaid diagrams** - Render diagrams inline using built-in Elisp SVG renderer
- **LaTeX math** - Styled math expressions
- **Built-in HTML export** - No external dependencies required
- **Pandoc integration** - Export to PDF, DOCX, and more (optional)
- **markdown-mode compatible** - Familiar keybindings for easy adoption

## Requirements

- Emacs 30.1 or later

### Optional Dependencies

- `pandoc` - For PDF/DOCX export

## Installation

markdown-modern is not on MELPA; install it directly from this repository.

### With `package-vc-install` (Emacs 29+, recommended)

```
M-x package-vc-install RET https://github.com/rjprins/markdown-modern RET
```

Or in your init file:

```elisp
(package-vc-install "https://github.com/rjprins/markdown-modern")
```

With `use-package` (Emacs 30+):

```elisp
(use-package markdown-modern
  :vc (:url "https://github.com/rjprins/markdown-modern"))
```

### Manual

```elisp
(add-to-list 'load-path "/path/to/markdown-modern/lisp")
(require 'markdown-modern)
```

## Usage

Enable markdown-modern for markdown files by adding to your init file:

```elisp
(add-to-list 'auto-mode-alist '("\\.md\\'" . markdown-modern-mode))
```

Or activate manually with `M-x markdown-modern-mode` in any markdown buffer.

### Quick Start

| Key | Command | Description |
|-----|---------|-------------|
| `C-c C-s b` | `markdown-modern-insert-bold` | Insert/toggle **bold** |
| `C-c C-s i` | `markdown-modern-insert-italic` | Insert/toggle *italic* |
| `C-c C-s c` | `markdown-modern-insert-code` | Insert/toggle `code` |
| `C-c C-t 2` | `markdown-modern-insert-heading-2` | Insert ## heading |
| `C-c C-l` | `markdown-modern-insert-link` | Insert link |
| `C-c C-i` | `markdown-modern-insert-image` | Insert image |
| `C-c C-e h` | `markdown-modern-export-html` | Export to HTML |

### Editing Model

markdown-modern has a single view mode. Markdown is always rendered inline; when the
cursor enters the scope of a markup element, that element's raw markup is
revealed so you can edit it in place, and re-rendered once the cursor leaves:

- On a heading line, the `#` markers appear.
- Inside (or right next to) emphasis, a code span, or a link, that element's
  delimiters appear.
- Inside a fenced code block or table, the raw block is shown.

Plain prose is never disturbed, so moving the cursor through ordinary text does
no work. There is no source/rendered toggle to manage.

You can also reveal the element at point on demand with
`markdown-modern-toggle-element-at-point` (`C-c C-v e`).

### Navigation

| Key | Command | Description |
|-----|---------|-------------|
| `C-c C-n` | `markdown-modern-next-heading` | Next heading |
| `C-c C-p` | `markdown-modern-prev-heading` | Previous heading |
| `C-c C-u` | `markdown-modern-up-heading` | Parent heading |
| `TAB` | Context-sensitive | Cycle visibility / table nav |

### Lists

| Key | Command | Description |
|-----|---------|-------------|
| `M-RET` | `markdown-modern-insert-list-item` | New list item |
| `C-c <up/down>` | Move item | Reorder list items |
| `C-c <left/right>` | Promote/demote | Change indentation |
| `C-c C-x C-b` | `markdown-modern-toggle-checkbox` | Toggle task checkbox |

### Tables

| Key | Command | Description |
|-----|---------|-------------|
| `C-c \|` | `markdown-modern-insert-table` | Insert new table |
| `TAB` | `markdown-modern-table-next-cell` | Next cell |
| `S-TAB` | `markdown-modern-table-prev-cell` | Previous cell |

### Export

```elisp
;; Built-in HTML export (no dependencies)
M-x markdown-modern-export-html

;; Preview in browser
M-x markdown-modern-preview-html

;; Export via Pandoc (requires pandoc)
M-x markdown-modern-export-pdf
M-x markdown-modern-export-docx
```

## Customization

All options available under `M-x customize-group RET markdown-modern`:

### Appearance

```elisp
;; Heading sizes
(setq markdown-modern-heading-scale '(1.8 1.5 1.3 1.1 1.05 1.0))

;; Use variable-pitch for headings
(setq markdown-modern-heading-use-variable-pitch t)

;; Image dimensions
(setq markdown-modern-image-max-width 800)
(setq markdown-modern-image-max-height 600)
```

### Media

```elisp
;; Cache directory
(setq markdown-modern-cache-directory "~/.cache/markdown-modern")
```

### Example Configuration

```elisp
(use-package markdown-modern
  :ensure t
  :mode ("\\.md\\'" "\\.markdown\\'")
  :custom
  (markdown-modern-heading-scale '(1.8 1.5 1.3 1.1 1.05 1.0))
  (markdown-modern-heading-use-variable-pitch t)
  (markdown-modern-image-max-width 800)
  :hook
  (markdown-modern-mode . visual-line-mode)
  :config
  (set-face-attribute 'markdown-modern-heading-1 nil :foreground "#2aa198"))
```

## Keybinding Reference

### Style Insertion (C-c C-s prefix)

| Key | Command |
|-----|---------|
| `C-c C-s b` | Bold |
| `C-c C-s i` | Italic |
| `C-c C-s c` | Inline code |
| `C-c C-s s` | Strikethrough |
| `C-c C-s q` | Blockquote |
| `C-c C-s p` | Code block |
| `C-c C-s k` | `<kbd>` tag |

### Headings (C-c C-t prefix)

| Key | Command |
|-----|---------|
| `C-c C-t h` | Insert heading (prompts for level) |
| `C-c C-t 1-6` | Insert heading level 1-6 |
| `C-c C-t !` | Promote heading |
| `C-c C-t @` | Demote heading |

### Reveal (C-c C-v prefix)

| Key | Command |
|-----|---------|
| `C-c C-v e` | Reveal raw markup for the element at point |
| `C-c C-v t` | Toggle horizontal-scroll view (for tables wider than the window) |

### Export (C-c C-e prefix)

| Key | Command |
|-----|---------|
| `C-c C-e h` | Export to HTML |
| `C-c C-e p` | Export to PDF (Pandoc) |
| `C-c C-e d` | Export to DOCX (Pandoc) |
| `C-c C-c p` | Preview in browser |

## Comparison with Alternatives

| Feature | markdown-modern | markdown-mode | org-mode |
|---------|-----------|---------------|----------|
| Inline WYSIWYG | Yes | No (split pane) | Partial |
| Pure Emacs | Yes | Yes | Yes |
| Dependencies | None | Optional | None |
| Standard Markdown | Yes | Yes | No (org syntax) |
| Customizable | Full Elisp | Full Elisp | Full Elisp |

## Known Limitations

- Setext-style headings (underlines) are not supported
- Math rendering requires external tools for SVG output
- Some complex nested structures may not render perfectly

## License

GPL-3.0-or-later

## Credits

markdown-modern is a fork of [mark-graf](https://github.com/hyperZphere/mark-graf) by Marc Ansset; thanks for the original work.

Inspired by:
- [org-modern](https://github.com/minad/org-modern) - Modern org-mode styling
- [markdown-mode](https://jblevins.org/projects/markdown-mode/) - The standard Emacs markdown mode
