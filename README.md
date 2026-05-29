# mark-graf

Modern WYSIWYG-style markdown editing for Emacs 30+.

mark-graf brings a seamless live preview experience to Emacs, combining inline WYSIWYG rendering with the text-property-based approach of [org-modern](https://github.com/minad/org-modern). Unlike traditional markdown modes that display raw syntax or require split-pane previews, mark-graf renders markdown content inline while maintaining full editability.

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

### From MELPA (recommended)

```elisp
(use-package mark-graf
  :ensure t)
```

### Manual Installation

1. Clone this repository
2. Add to your `load-path`:

```elisp
(add-to-list 'load-path "/path/to/mark-graf/lisp")
(require 'mark-graf)
```

## Usage

Enable mark-graf for markdown files by adding to your init file:

```elisp
(add-to-list 'auto-mode-alist '("\\.md\\'" . mark-graf-mode))
```

Or activate manually with `M-x mark-graf-mode` in any markdown buffer.

### Quick Start

| Key | Command | Description |
|-----|---------|-------------|
| `C-c C-s b` | `mark-graf-insert-bold` | Insert/toggle **bold** |
| `C-c C-s i` | `mark-graf-insert-italic` | Insert/toggle *italic* |
| `C-c C-s c` | `mark-graf-insert-code` | Insert/toggle `code` |
| `C-c C-t 2` | `mark-graf-insert-heading-2` | Insert ## heading |
| `C-c C-l` | `mark-graf-insert-link` | Insert link |
| `C-c C-i` | `mark-graf-insert-image` | Insert image |
| `C-c C-e h` | `mark-graf-export-html` | Export to HTML |

### Editing Model

mark-graf has a single view mode. Markdown is always rendered inline; when the
cursor enters the scope of a markup element, that element's raw markup is
revealed so you can edit it in place, and re-rendered once the cursor leaves:

- On a heading line, the `#` markers appear.
- Inside (or right next to) emphasis, a code span, or a link, that element's
  delimiters appear.
- Inside a fenced code block or table, the raw block is shown.

Plain prose is never disturbed, so moving the cursor through ordinary text does
no work. There is no source/rendered toggle to manage.

You can also reveal the element at point on demand with
`mark-graf-toggle-element-at-point` (`C-c C-v e`).

### Navigation

| Key | Command | Description |
|-----|---------|-------------|
| `C-c C-n` | `mark-graf-next-heading` | Next heading |
| `C-c C-p` | `mark-graf-prev-heading` | Previous heading |
| `C-c C-u` | `mark-graf-up-heading` | Parent heading |
| `TAB` | Context-sensitive | Cycle visibility / table nav |

### Lists

| Key | Command | Description |
|-----|---------|-------------|
| `M-RET` | `mark-graf-insert-list-item` | New list item |
| `C-c <up/down>` | Move item | Reorder list items |
| `C-c <left/right>` | Promote/demote | Change indentation |
| `C-c C-x C-b` | `mark-graf-toggle-checkbox` | Toggle task checkbox |

### Tables

| Key | Command | Description |
|-----|---------|-------------|
| `C-c \|` | `mark-graf-insert-table` | Insert new table |
| `TAB` | `mark-graf-table-next-cell` | Next cell |
| `S-TAB` | `mark-graf-table-prev-cell` | Previous cell |

### Export

```elisp
;; Built-in HTML export (no dependencies)
M-x mark-graf-export-html

;; Preview in browser
M-x mark-graf-preview-html

;; Export via Pandoc (requires pandoc)
M-x mark-graf-export-pdf
M-x mark-graf-export-docx
```

## Customization

All options available under `M-x customize-group RET mark-graf`:

### Appearance

```elisp
;; Heading sizes
(setq mark-graf-heading-scale '(1.8 1.5 1.3 1.1 1.05 1.0))

;; Use variable-pitch for headings
(setq mark-graf-heading-use-variable-pitch t)

;; Image dimensions
(setq mark-graf-image-max-width 800)
(setq mark-graf-image-max-height 600)
```

### Media

```elisp
;; Cache directory
(setq mark-graf-cache-directory "~/.cache/mark-graf")
```

### Example Configuration

```elisp
(use-package mark-graf
  :ensure t
  :mode ("\\.md\\'" "\\.markdown\\'")
  :custom
  (mark-graf-heading-scale '(1.8 1.5 1.3 1.1 1.05 1.0))
  (mark-graf-heading-use-variable-pitch t)
  (mark-graf-image-max-width 800)
  :hook
  (mark-graf-mode . visual-line-mode)
  :config
  (set-face-attribute 'mark-graf-heading-1 nil :foreground "#2aa198"))
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

### Export (C-c C-e prefix)

| Key | Command |
|-----|---------|
| `C-c C-e h` | Export to HTML |
| `C-c C-e p` | Export to PDF (Pandoc) |
| `C-c C-e d` | Export to DOCX (Pandoc) |
| `C-c C-c p` | Preview in browser |

## Comparison with Alternatives

| Feature | mark-graf | markdown-mode | org-mode |
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

Inspired by:
- [org-modern](https://github.com/minad/org-modern) - Modern org-mode styling
- [markdown-mode](https://jblevins.org/projects/markdown-mode/) - The standard Emacs markdown mode
