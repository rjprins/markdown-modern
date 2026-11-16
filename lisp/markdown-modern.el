;;; markdown-modern.el --- Modern visual styling for Markdown buffers -*- lexical-binding: t; -*-

;; Copyright (C) 2026 markdown-modern contributors

;; Author: Marc Ansset <info@ansset.com>
;; Maintainer: Rutger Prins <rutgerprins@gmail.com>
;; Version: 2.1.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: markdown, wp, text
;; URL: https://github.com/rjprins/markdown-modern

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; markdown-modern provides modern visual styling for Markdown buffers in
;; Emacs 30+.  It renders Markdown inline using text properties and overlays,
;; in the spirit of org-modern, and reveals the raw markup of the element
;; under the cursor for editing.
;;
;; markdown-modern is a fork of mark-graf by Marc Ansset
;; (https://github.com/hyperZphere/mark-graf).
;;
;; Features:
;; - Inline rendering of markdown using text properties and overlays,
;;   driven by `jit-lock' so only the visible region is rendered
;; - Reveal-at-point: the raw markup of the element under the cursor
;;   (heading markers, emphasis/code delimiters, fences, ...) is shown for
;;   in-place editing, and re-rendered when the cursor leaves
;; - Full GFM support including tables, task lists, and fenced code blocks
;; - Image and diagram rendering
;; - Built-in HTML export with optional Pandoc integration
;;
;; Usage:
;;   (require 'markdown-modern)
;;   ;; Automatically activates for .md files
;;
;; Customization:
;;   M-x customize-group RET markdown-modern RET

;;; Code:

(require 'treesit)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'outline)

;; Load submodules
(require 'markdown-modern-ts)
(require 'markdown-modern-mermaid)
(require 'markdown-modern-render)
(require 'markdown-modern-elements)
(require 'markdown-modern-commands)
(require 'markdown-modern-diagram)
(require 'markdown-modern-export)

;;; Customization Groups

(defgroup markdown-modern nil
  "Modern WYSIWYG-style markdown editing."
  :group 'text
  :group 'wp
  :prefix "markdown-modern-")

(defgroup markdown-modern-faces nil
  "Faces for markdown-modern rendering."
  :group 'markdown-modern
  :group 'faces)

(defgroup markdown-modern-performance nil
  "Performance tuning for markdown-modern."
  :group 'markdown-modern)

(defgroup markdown-modern-code nil
  "Code block settings for markdown-modern."
  :group 'markdown-modern)

(defgroup markdown-modern-media nil
  "Image and media settings for markdown-modern."
  :group 'markdown-modern)

(defgroup markdown-modern-math nil
  "Math rendering settings for markdown-modern."
  :group 'markdown-modern)

(defgroup markdown-modern-export nil
  "Export settings for markdown-modern."
  :group 'markdown-modern)

;;; Customization Variables

(defcustom markdown-modern-heading-scale '(1.8 1.5 1.3 1.1 1.05 1.0)
  "Height scale factors for heading levels 1-6."
  :type '(list number number number number number number)
  :group 'markdown-modern-faces)

(defcustom markdown-modern-heading-use-variable-pitch t
  "Whether headings should use variable-pitch font."
  :type 'boolean
  :group 'markdown-modern-faces)

(defcustom markdown-modern-display-images t
  "Whether to display images inline."
  :type 'boolean
  :group 'markdown-modern-media)

(defcustom markdown-modern-image-max-width 600
  "Maximum width in pixels for inline images."
  :type 'integer
  :group 'markdown-modern-media)

(defcustom markdown-modern-image-max-height 400
  "Maximum height in pixels for inline images."
  :type 'integer
  :group 'markdown-modern-media)

(defcustom markdown-modern-text-width 80
  "Maximum width of the rendered text, in columns.
Like the content column of a Markdown renderer: text wraps at this width
instead of at the window edge, however wide the window is.  A column is the
average character width of the buffer's default font, so under
`variable-pitch-mode' it is a proportional character, as in `writeroom-mode'.
`markdown-modern-left-margin', line numbers and a left window margin come
on top.  The width follows text scaling.

markdown-modern makes room with a right window margin, and drops it while
lines are truncated.  It leaves the margins alone while
`visual-fill-column-mode' or `olivetti-mode' manages them, or when another
package has set the right margin.  To keep new windows opening beside a wide
markdown-modern window, see `markdown-modern-advise-window-splittable-p'.
Set to nil to use the full window width."
  :type '(choice (natnum :tag "Columns")
                 (const :tag "Full window width" nil))
  :safe (lambda (value) (or (null value) (natnump value)))
  :group 'markdown-modern)

(defvar markdown-modern--right-margins)

(defcustom markdown-modern-advise-window-splittable-p t
  "Whether markdown-modern windows still split side by side.
Emacs puts a new window, such as *Help* or Magit, beside the current one
only when that window's text area is at least `split-width-threshold'
columns wide.  The right margin that keeps `markdown-modern-text-width'
makes the text area narrower, so new windows would open below.

When non-nil, markdown-modern adds around advice to `window-splittable-p'
that counts its own margin as width, for markdown-modern windows only.
Set to nil to leave `window-splittable-p' alone; through Customize or
`setopt' that removes the advice at once."
  :type 'boolean
  :set (lambda (symbol value)
         (set-default-toplevel-value symbol value)
         (unless value
           (advice-remove 'window-splittable-p
                          #'markdown-modern--window-splittable-p)))
  :group 'markdown-modern)

(defun markdown-modern--window-splittable-p (orig window &optional horizontal)
  "Count the reading margin as width when Emacs asks if WINDOW can split.
Around advice for `window-splittable-p'; ORIG is the original function, and
WINDOW and HORIZONTAL its arguments.  Emacs splits side by side only when the
text area is at least `split-width-threshold' columns wide, and the reading
margin keeps it narrower.  For a markdown-modern window, ask without that
margin.  Other windows get the plain answer."
  (let ((margins (and horizontal (window-live-p window) (window-margins window))))
    (if (and markdown-modern-advise-window-splittable-p
             (cdr margins)
             (> (cdr margins) 0)
             (with-current-buffer (window-buffer window)
               (and (derived-mode-p 'markdown-modern-mode)
                    (memq (cdr margins) markdown-modern--right-margins))))
        (progn
          (set-window-margins window (car margins) 0)
          (unwind-protect (funcall orig window horizontal)
            (set-window-margins window (car margins) (cdr margins))))
      (funcall orig window horizontal))))

(make-obsolete-variable 'markdown-modern-manage-text-width
                        'markdown-modern-text-width "2.2.0")

(defcustom markdown-modern-visual-line t
  "Whether `markdown-modern-mode' enables `visual-line-mode'.
Provides soft word wrapping; set to nil to leave line wrapping to your own
configuration."
  :type 'boolean
  :group 'markdown-modern)

(defcustom markdown-modern-variable-pitch t
  "Whether `markdown-modern-mode' enables `variable-pitch-mode'.
Renders prose in a proportional font for a document-like appearance; code
spans, code blocks and tables stay monospaced via their faces.  Set to nil
to keep a fixed-pitch buffer."
  :type 'boolean
  :group 'markdown-modern)

(defcustom markdown-modern-join-paragraph-lines nil
  "Whether the source lines of a paragraph display joined.
Markdown treats a single newline inside a paragraph as a space.  When
non-nil, such newlines display as spaces, so a paragraph that the file wraps
at a fixed width flows to the reading width (`markdown-modern-text-width').
Explicit hard breaks and blank lines stay.  Editing a paragraph shows its
source lines again.  When nil (the default), paragraphs show their lines as
written, so line commands such as \\[kill-line] act on what you see.  After
changing this, run `markdown-modern-mode' again in open buffers."
  :type 'boolean
  :safe #'booleanp
  :group 'markdown-modern)

(defcustom markdown-modern-paragraph-reveal-delay nil
  "Seconds point rests in a paragraph before it shows its source lines.
With `markdown-modern-join-paragraph-lines', paragraphs show their source
line breaks as spaces, so prose fills the window.  Editing a paragraph shows
its source lines right away.  When this is a number, a paragraph also shows
them once point has rested in it for that many seconds.  When nil, only
editing shows them."
  :type '(choice (const :tag "Only when editing" nil)
                 (number :tag "Seconds"))
  :group 'markdown-modern)

(defcustom markdown-modern-left-margin 4
  "Left margin width in characters.
This creates whitespace on the left side of the buffer for better readability."
  :type 'integer
  :group 'markdown-modern)

(defcustom markdown-modern-code-block-syntax-highlight t
  "Whether to apply syntax highlighting to code blocks.
When enabled, code blocks use Emacs font-lock for the specified language."
  :type 'boolean
  :group 'markdown-modern-code)

(defcustom markdown-modern-code-block-full-width t
  "Whether code block backgrounds extend to the window edge.
When enabled, the background color extends to the right margin."
  :type 'boolean
  :group 'markdown-modern-code)

;;; Faces

(defface markdown-modern-default
  '((t :inherit default))
  "Default face for markdown-modern content."
  :group 'markdown-modern-faces)

(defface markdown-modern-heading-1
  '((t :height 1.8 :weight bold :inherit default))
  "Face for level 1 headings."
  :group 'markdown-modern-faces)

(defface markdown-modern-heading-2
  '((t :height 1.5 :weight bold :inherit default))
  "Face for level 2 headings."
  :group 'markdown-modern-faces)

(defface markdown-modern-heading-3
  '((t :height 1.3 :weight bold :inherit default))
  "Face for level 3 headings."
  :group 'markdown-modern-faces)

(defface markdown-modern-heading-4
  '((t :height 1.1 :weight bold :inherit default))
  "Face for level 4 headings."
  :group 'markdown-modern-faces)

(defface markdown-modern-heading-5
  '((t :height 1.05 :weight bold :inherit default))
  "Face for level 5 headings."
  :group 'markdown-modern-faces)

(defface markdown-modern-heading-6
  '((t :height 1.0 :weight bold :inherit default))
  "Face for level 6 headings."
  :group 'markdown-modern-faces)

(defface markdown-modern-bold
  '((t :weight bold))
  "Face for bold/strong text."
  :group 'markdown-modern-faces)

(defface markdown-modern-italic
  '((t :slant italic))
  "Face for italic/emphasis text."
  :group 'markdown-modern-faces)

(defface markdown-modern-bold-italic
  '((t :weight bold :slant italic))
  "Face for bold italic text."
  :group 'markdown-modern-faces)

(defface markdown-modern-strikethrough
  '((t :strike-through t))
  "Face for strikethrough text."
  :group 'markdown-modern-faces)

(defface markdown-modern-inline-code
  '((((background light))
     :inherit fixed-pitch
     :foreground "#c7254e")
    (((background dark))
     :inherit fixed-pitch
     :foreground "#e06c75"))
  "Face for inline code spans.
Uses distinct color only, no background to keep clean appearance.
Inherits `fixed-pitch' so code stays monospaced under `variable-pitch-mode'."
  :group 'markdown-modern-faces)

(defface markdown-modern-code-block
  '((((background light))
     :background "#f0f0f0"
     :foreground "#383a42"
     :inherit fixed-pitch
     :extend t)
    (((background dark))
     :background "#252530"
     :foreground "#abb2bf"
     :inherit fixed-pitch
     :extend t))
  "Face for code block content.
Includes foreground color to override markdown-mode's inline styling."
  :group 'markdown-modern-faces)

(defface markdown-modern-code-block-language
  '((((background light))
     :height 0.85
     :foreground "#666666"
     :slant italic)
    (((background dark))
     :height 0.85
     :foreground "#7a7a8a"
     :slant italic))
  "Face for code block language label."
  :group 'markdown-modern-faces)

(defface markdown-modern-link
  '((t :underline t :inherit link))
  "Face for link text."
  :group 'markdown-modern-faces)

(defface markdown-modern-link-url
  '((t :foreground "#888888" :height 0.9))
  "Face for link URLs when displayed."
  :group 'markdown-modern-faces)

(defface markdown-modern-image-alt
  '((t :foreground "#888888" :slant italic))
  "Face for image alt text placeholders."
  :group 'markdown-modern-faces)

(defface markdown-modern-blockquote
  '((((background light))
     :foreground "#555555"
     :slant italic)
    (((background dark))
     :foreground "#999999"
     :slant italic))
  "Face for blockquote text.
No background is used to avoid issues with `visual-line-mode' wrapping."
  :group 'markdown-modern-faces)

(defface markdown-modern-blockquote-marker
  '((t :foreground "#5588cc" :weight bold))
  "Face for blockquote left border marker."
  :group 'markdown-modern-faces)

(defface markdown-modern-list-bullet
  '((t :inherit fixed-pitch :foreground "#5588cc"))
  "Face for list bullet characters.
Uses `fixed-pitch' as the basis for the shared bullet and checkbox slot."
  :group 'markdown-modern-faces)

(defface markdown-modern-list-number
  '((t :foreground "#5588cc" :weight bold))
  "Face for ordered list numbers."
  :group 'markdown-modern-faces)

(defface markdown-modern-task-unchecked
  '((t :inherit fixed-pitch :foreground "#888888"))
  "Face for unchecked task checkboxes."
  :group 'markdown-modern-faces)

(defface markdown-modern-task-checked
  '((t :inherit fixed-pitch :foreground "#22aa22"))
  "Face for checked task checkboxes."
  :group 'markdown-modern-faces)

(defface markdown-modern-task-done-text
  '((t :strike-through t :foreground "#888888"))
  "Face for completed task text."
  :group 'markdown-modern-faces)

(defface markdown-modern-table
  '((t :inherit fixed-pitch))
  "Face for table data rows.
Inherits `fixed-pitch' so columns stay aligned under `variable-pitch-mode'."
  :group 'markdown-modern-faces)

(defface markdown-modern-table-header
  '((t :inherit markdown-modern-table :weight bold))
  "Face for table header cells (bold text)."
  :group 'markdown-modern-faces)

(defface markdown-modern-table-border
  '((((background light))
     :inherit fixed-pitch
     :foreground "#888888")
    (((background dark))
     :inherit fixed-pitch
     :foreground "#666666"))
  "Face for the table grid lines (borders and separator row)."
  :group 'markdown-modern-faces)

(defface markdown-modern-table-cell
  '((t :inherit fixed-pitch))
  "Face for table cell content."
  :group 'markdown-modern-faces)

(defface markdown-modern-hr
  '((t :foreground "#cccccc"))
  "Face for horizontal rules."
  :group 'markdown-modern-faces)

(defface markdown-modern-footnote-ref
  '((t :height 0.8 :foreground "#5588cc" :underline t))
  "Face for footnote references."
  :group 'markdown-modern-faces)

(defface markdown-modern-math
  '((t :foreground "#aa5588"))
  "Face for math expressions."
  :group 'markdown-modern-faces)

(defface markdown-modern-delimiter
  '((t :foreground "#888888"))
  "Face for visible markdown delimiters."
  :group 'markdown-modern-faces)

;; Force-update face attributes that defface won't change on reload (defface is
;; a no-op for an already-defined face), so reloads drop the old backgrounds.
(dolist (face '(markdown-modern-table markdown-modern-table-header
                markdown-modern-table-border))
  (set-face-attribute face nil :extend nil :background 'unspecified))
;; Force-update math face in case it was previously defined differently
(set-face-attribute 'markdown-modern-math nil
                    :foreground "#aa5588"
                    :inherit nil)

;;; Internal Variables

(defvar-local markdown-modern--rendering-enabled t
  "Whether rendering is currently enabled in this buffer.")

(defvar-local markdown-modern--chars-tick nil
  "Value of `buffer-chars-modified-tick' after the last command.")

(defvar markdown-modern--paragraph-timer nil
  "Idle timer that changes which paragraph shows its source lines.")

(defconst markdown-modern--paragraph-join-delay 0.5
  "Idle seconds before a paragraph that point left joins its lines again.")

(defvar-local markdown-modern--revealed-region nil
  "Cons (START . END) of the markup element currently revealed at point.
Nil when point is in plain prose with no markup to reveal.  This is the
single source of truth shared between point-motion reveal and jit-lock.")

(defvar-local markdown-modern--code-edit-buffer nil
  "Indirect buffer currently editing a code block, or nil.")

;;; Mode Definition

(defvar markdown-modern-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Style insertion (C-c C-s prefix)
    (define-key map (kbd "C-c C-s b") #'markdown-modern-insert-bold)
    (define-key map (kbd "C-c C-s i") #'markdown-modern-insert-italic)
    (define-key map (kbd "C-c C-s c") #'markdown-modern-insert-code)
    (define-key map (kbd "C-c C-s s") #'markdown-modern-insert-strike)
    (define-key map (kbd "C-c C-s q") #'markdown-modern-insert-blockquote)
    (define-key map (kbd "C-c C-s p") #'markdown-modern-insert-code-block)
    (define-key map (kbd "C-c C-s k") #'markdown-modern-insert-kbd)

    ;; Headings (C-c C-t prefix)
    (define-key map (kbd "C-c C-t h") #'markdown-modern-insert-heading)
    (define-key map (kbd "C-c C-t 1") #'markdown-modern-insert-heading-1)
    (define-key map (kbd "C-c C-t 2") #'markdown-modern-insert-heading-2)
    (define-key map (kbd "C-c C-t 3") #'markdown-modern-insert-heading-3)
    (define-key map (kbd "C-c C-t 4") #'markdown-modern-insert-heading-4)
    (define-key map (kbd "C-c C-t 5") #'markdown-modern-insert-heading-5)
    (define-key map (kbd "C-c C-t 6") #'markdown-modern-insert-heading-6)
    (define-key map (kbd "C-c C-t !") #'markdown-modern-promote-heading)
    (define-key map (kbd "C-c C-t @") #'markdown-modern-demote-heading)

    ;; Links and images
    (define-key map (kbd "C-c C-l") #'markdown-modern-insert-link)
    (define-key map (kbd "C-c C-i") #'markdown-modern-insert-image)
    (define-key map (kbd "C-c C-x C-i") #'markdown-modern-toggle-images)

    ;; Follow link at point
    (define-key map (kbd "C-c C-o") #'markdown-modern-follow-link-at-point)

    ;; Navigation
    (define-key map (kbd "C-c C-n") #'markdown-modern-next-heading)
    (define-key map (kbd "C-c C-p") #'markdown-modern-prev-heading)
    (define-key map (kbd "C-c C-f") #'markdown-modern-next-heading-same-level)
    (define-key map (kbd "C-c C-b") #'markdown-modern-prev-heading-same-level)
    (define-key map (kbd "C-c C-u") #'markdown-modern-up-heading)
    (define-key map (kbd "TAB") #'markdown-modern-tab)
    (define-key map (kbd "<backtab>") #'markdown-modern-backtab)

    ;; Lists
    (define-key map (kbd "M-RET") #'markdown-modern-insert-list-item)
    (define-key map (kbd "C-c <up>") #'markdown-modern-move-item-up)
    (define-key map (kbd "C-c <down>") #'markdown-modern-move-item-down)
    (define-key map (kbd "C-c <left>") #'markdown-modern-promote-item)
    (define-key map (kbd "C-c <right>") #'markdown-modern-demote-item)
    (define-key map (kbd "C-c C-x C-b") #'markdown-modern-toggle-checkbox)

    ;; Task checkboxes are widgets, not revealed markup: SPC toggles the
    ;; checkbox under point, and Backspace/Delete on it removes the whole
    ;; checkbox at once, leaving a plain list item.
    (define-key map (kbd "SPC") #'markdown-modern-space-or-toggle-checkbox)
    (define-key map (kbd "DEL") #'markdown-modern-checkbox-delete-backward)
    (define-key map (kbd "<backspace>") #'markdown-modern-checkbox-delete-backward)
    (define-key map (kbd "C-d") #'markdown-modern-checkbox-delete-forward)
    (define-key map (kbd "<deletechar>") #'markdown-modern-checkbox-delete-forward)

    ;; Tables
    (define-key map (kbd "C-c |") #'markdown-modern-insert-table)
    (define-key map (kbd "C-c C-c ^") #'markdown-modern-table-sort)

    ;; Reveal raw markdown for the element at point on demand
    (define-key map (kbd "C-c C-v e") #'markdown-modern-toggle-element-at-point)
    (define-key map (kbd "C-c C-x C-v") #'markdown-modern-toggle-element-at-point)

    ;; Toggle horizontal-scroll view (for tables wider than the window)
    (define-key map (kbd "C-c C-v t") #'markdown-modern-toggle-truncate-lines)

    ;; Focus a diagram, including from its revealed source.
    (define-key map (kbd "C-c C-v d") #'markdown-modern-focus-diagram)

    ;; Code block editing
    (define-key map (kbd "C-c '") #'markdown-modern-edit-code-block)

    ;; Export
    (define-key map (kbd "C-c C-e h") #'markdown-modern-export-html)
    (define-key map (kbd "C-c C-e p") #'markdown-modern-export-pdf)
    (define-key map (kbd "C-c C-e d") #'markdown-modern-export-docx)
    (define-key map (kbd "C-c C-c p") #'markdown-modern-preview-html)

    map)
  "Keymap for `markdown-modern-mode'.")

;;; Folding

(defconst markdown-modern--outline-heading-regexp "#\\{1,6\\}\\(?:[ \t]\\|$\\)"
  "Regexp for the start of an ATX heading line, without the line start.")

(defun markdown-modern--outline-heading-p (pos)
  "Return non-nil if POS is in an ATX heading in the parse tree.
A line that starts with `#' inside a code block is not a heading."
  (when-let* ((parser markdown-modern-ts--parser)
              (node (treesit-node-on pos (min (1+ pos) (point-max)) parser t)))
    (treesit-parent-until
     node (lambda (n) (equal (treesit-node-type n) "atx_heading")) t)))

(defun markdown-modern--outline-search (&optional bound move backward looking-at)
  "Find the next heading for outline, skipping `#' lines in code blocks.
This is the `outline-search-function'.  BOUND, MOVE, BACKWARD and
LOOKING-AT are as described there."
  (let ((regexp (concat "^" markdown-modern--outline-heading-regexp)))
    (if looking-at
        (and (looking-at regexp)
             (markdown-modern--outline-heading-p (point)))
      (let ((start (point))
            (found nil))
        (while (and (not found)
                    (if backward
                        (re-search-backward regexp bound t)
                      (re-search-forward regexp bound t)))
          (when (markdown-modern--outline-heading-p (match-beginning 0))
            (setq found t)))
        (unless found
          (goto-char (if move
                         (or bound (if backward (point-min) (point-max)))
                       start)))
        found))))

(defun markdown-modern--outline-level ()
  "Return the level of the heading at point, for `outline-level'."
  (save-excursion
    (beginning-of-line)
    (if (looking-at "#+")
        (- (match-end 0) (match-beginning 0))
      1)))

(defun markdown-modern--setup-buffer ()
  "Set up the current buffer for markdown-modern-mode."
  (markdown-modern-ts--init)
  ;; Disable font-lock and remove any face properties left by
  ;; a previous major mode (e.g. markdown-mode)
  (font-lock-mode -1)
  (with-silent-modifications
    (remove-text-properties (point-min) (point-max) '(face nil)))

  ;; NB: do not force `display-line-numbers-mode' (or other UI minor
  ;; modes) here -- respect the user's global configuration.

  ;; Set up left indentation using line-prefix
  (let ((indent-str (propertize (make-string markdown-modern-left-margin ?\s)
                                'face 'default)))
    (setq-local line-prefix indent-str)
    (setq-local wrap-prefix indent-str))

  ;; Optional visual modes (enabled by default; configurable).
  (when markdown-modern-visual-line
    (visual-line-mode 1))
  (when markdown-modern-variable-pitch
    (variable-pitch-mode 1))

  ;; Initialize rendering
  (markdown-modern-render--init)

  ;; Set up hooks.  Rendering itself is driven by jit-lock, which renders
  ;; only the visible region (and re-renders on scroll/edit).  The
  ;; post-command hook reveals the markup of the element under point, and
  ;; the after-change hook invalidates the edited block for jit-lock.
  (jit-lock-register #'markdown-modern--jit-fontify)
  (add-hook 'post-command-hook #'markdown-modern--update-reveal nil t)
  (setq markdown-modern--chars-tick (buffer-chars-modified-tick))
  (add-hook 'after-change-functions #'markdown-modern--after-change nil t)
  ;; An edit can change how text far from it parses, as when a new table
  ;; row ends one table and starts another.  Re-render what changed.  Parse
  ;; first: the first parse changes everything and needs no notice.
  (treesit-parser-root-node markdown-modern-ts--parser)
  (treesit-parser-add-notifier markdown-modern-ts--parser
                               #'markdown-modern--after-reparse)
  (add-hook 'text-scale-mode-hook #'markdown-modern--on-text-scale nil t)
  ;; Keep the reading width in every window that shows the buffer.  The
  ;; buffer-local hooks get the window as argument.  Margins change only the
  ;; body size, so a second run computes the same margins and stops there.
  (add-hook 'window-size-change-functions #'markdown-modern--update-text-width nil t)
  (add-hook 'window-buffer-change-functions #'markdown-modern--update-text-width nil t)
  ;; Run after the margin is set, which changes the width tables fit.
  (add-hook 'window-size-change-functions #'markdown-modern--refit-tables 90 t)
  (when markdown-modern-advise-window-splittable-p
    (advice-add 'window-splittable-p :around
                #'markdown-modern--window-splittable-p))
  (markdown-modern--update-text-width-everywhere)
  ;; Clean up when switching to another major mode
  (add-hook 'change-major-mode-hook #'markdown-modern--teardown-buffer nil t)

  ;; Set up imenu
  (setq-local imenu-create-index-function #'markdown-modern-imenu-create-index)

  ;; Folding with outline: TAB on a heading, S-TAB for the buffer.
  (setq-local outline-regexp markdown-modern--outline-heading-regexp)
  (setq-local outline-search-function #'markdown-modern--outline-search)
  (setq-local outline-level #'markdown-modern--outline-level)
  (add-to-invisibility-spec '(outline . t)))

(defun markdown-modern--text-width-right-margin (available-px text-px char-px)
  "Return the right margin that leaves TEXT-PX of AVAILABLE-PX for the text.
AVAILABLE-PX is the pixel width of the text area and the right margin.
CHAR-PX is the frame's column width, the unit of window margins.  A window
narrower than TEXT-PX gets no margin."
  (max 0 (floor (- available-px text-px) (max 1 char-px))))

(defun markdown-modern--text-width-px (window)
  "Return the pixel width of WINDOW's text area at the reading width.
That is `markdown-modern-text-width' plus `markdown-modern-left-margin'
columns of the buffer's default font, plus the line numbers if shown.  Call
it with WINDOW's buffer current."
  (let ((font-px (if (eq (window-frame window) (selected-frame))
                     (default-font-width)
                   ;; Selecting the frame makes its selected window's buffer
                   ;; current, so measure in WINDOW's buffer again.
                   (let ((buffer (current-buffer)))
                     (with-selected-frame (window-frame window)
                       (with-current-buffer buffer (default-font-width)))))))
    (+ (* (+ markdown-modern-text-width markdown-modern-left-margin) font-px)
       (if display-line-numbers
           (with-selected-window window (line-number-display-width t))
         0))))

(defvar-local markdown-modern--right-margins nil
  "Right margins markdown-modern set in windows of this buffer, newest first.
A right margin that is not one of these belongs to another package.  A split
copies the margin into the new window, so the window alone cannot tell.")

(defun markdown-modern--own-right-margin-p (window)
  "Return non-nil if markdown-modern may set WINDOW's right margin.
That is when the margin is unset or one that markdown-modern set, and no
mode known to manage margins is on."
  (and (not (bound-and-true-p visual-fill-column-mode))
       (not (bound-and-true-p olivetti-mode))
       (let ((right (or (cdr (window-margins window)) 0)))
         (or (zerop right) (memq right markdown-modern--right-margins)))))

(defun markdown-modern--update-text-width (&optional window)
  "Set the right margin of WINDOW so its text keeps the reading width.
WINDOW defaults to the selected window.  See `markdown-modern-text-width'.
There is no margin while lines are truncated, so they scroll at full width."
  (let ((win (or window (selected-window))))
    (when (window-live-p win)
      (with-current-buffer (window-buffer win)
        (when (and markdown-modern-text-width
                   (derived-mode-p 'markdown-modern-mode)
                   (markdown-modern--own-right-margin-p win))
          ;; Right after a split, both windows keep the old margin, which can
          ;; be wider than the window.  The text area then measures 0, so
          ;; clear the margin to measure.
          (when (zerop (window-body-width win t))
            (set-window-margins win (car (window-margins win)) 0))
          (let* ((margins (window-margins win))
                 (right (or (cdr margins) 0))
                 (char-px (frame-char-width (window-frame win)))
                 (new-right
                  (if truncate-lines
                      0
                    (markdown-modern--text-width-right-margin
                     ;; The text area and the right margin; a left margin
                     ;; belongs to another package and does not count.
                     (+ (window-body-width win t) (* right char-px))
                     (markdown-modern--text-width-px win)
                     char-px))))
            (when (> new-right 0)
              ;; Draw the fringes at the window edge, not between the text
              ;; and the margin, where the right one would show as a bar.
              (unless (nth 2 (window-fringes win))
                (set-window-fringes win left-fringe-width right-fringe-width t))
              ;; Let a split shrink the margin; the hooks then refit both
              ;; windows.  Otherwise a wide margin makes the window too small
              ;; to split side by side.
              (set-window-parameter win 'min-margins '(0 . 0))
              (unless (memq new-right markdown-modern--right-margins)
                (setq markdown-modern--right-margins
                      (seq-take (cons new-right markdown-modern--right-margins)
                                16))))
            (unless (= new-right right)
              (set-window-margins win (car margins) new-right))))))))

(defun markdown-modern--refit-tables (&optional window)
  "Draw the tables again if WINDOW's size changed the width they fit.
WINDOW defaults to the selected window.  Tables are drawn to fit the width
of a window that shows the buffer, so a split or resize can leave them too
wide or too narrow."
  (let ((win (or window (selected-window))))
    (when (window-live-p win)
      (with-current-buffer (window-buffer win)
        (when (and (derived-mode-p 'markdown-modern-mode)
                   markdown-modern--rendering-enabled
                   markdown-modern-render--table-display-width
                   (not markdown-modern-table-max-width)
                   (/= markdown-modern-render--table-display-width
                       (markdown-modern-render--table-display-width)))
          (setq markdown-modern-render--table-display-width nil)
          (jit-lock-refontify))))))

(defun markdown-modern--update-text-width-everywhere ()
  "Update the reading width in every window that shows the current buffer."
  (dolist (win (get-buffer-window-list nil nil t))
    (markdown-modern--update-text-width win)))

(defun markdown-modern--on-text-scale ()
  "Refit the reading width and list marker padding after a text size change."
  (markdown-modern--update-text-width-everywhere)
  (jit-lock-refontify))

(defun markdown-modern--teardown-buffer ()
  "Clean up markdown-modern-mode resources from buffer."
  ;; Stop jit-lock rendering and remove hooks
  (jit-lock-unregister #'markdown-modern--jit-fontify)
  (remove-hook 'post-command-hook #'markdown-modern--update-reveal t)
  (remove-hook 'after-change-functions #'markdown-modern--after-change t)
  (remove-hook 'text-scale-mode-hook #'markdown-modern--on-text-scale t)
  (remove-hook 'change-major-mode-hook #'markdown-modern--teardown-buffer t)
  (remove-hook 'window-size-change-functions #'markdown-modern--update-text-width t)
  (remove-hook 'window-buffer-change-functions #'markdown-modern--update-text-width t)
  (remove-hook 'window-size-change-functions #'markdown-modern--refit-tables t)

  ;; Reset state
  (setq markdown-modern--revealed-region nil)
  (when (and markdown-modern--code-edit-buffer
             (buffer-live-p markdown-modern--code-edit-buffer))
    (kill-buffer markdown-modern--code-edit-buffer))
  (setq markdown-modern--code-edit-buffer nil)

  ;; Disable only the visual modes markdown-modern turned on (see setup), so we
  ;; don't clobber settings the user manages elsewhere.
  (when markdown-modern-visual-line
    (visual-line-mode -1))
  (when markdown-modern-variable-pitch
    (variable-pitch-mode -1))

  ;; Reset line prefix
  (setq-local line-prefix nil)
  (setq-local wrap-prefix nil)

  ;; Give back the right margins and fringe placement that the reading width
  ;; took, unless another mode manages them.
  (dolist (win (get-buffer-window-list nil nil t))
    (when (markdown-modern--own-right-margin-p win)
      (set-window-margins win (car (window-margins win)) right-margin-width)
      (set-window-fringes win left-fringe-width right-fringe-width
                          fringes-outside-margins)
      (set-window-parameter win 'min-margins nil)))

  ;; Clear overlays
  (markdown-modern-render--clear-all)
  (markdown-modern-ts--cleanup))

;;;###autoload
(define-derived-mode markdown-modern-mode text-mode "MdM"
  "Major mode that renders Markdown inline with modern visual styling.

markdown-modern renders Markdown content inline using text properties and
overlays, revealing the raw markup of the element under the cursor for editing.

\\{markdown-modern-mode-map}"
  :group 'markdown-modern
  :syntax-table nil

  ;; Mode setup
  (markdown-modern--setup-buffer)

  ;; Mode line
  (setq mode-name
        '(:eval (if markdown-modern--rendering-enabled "MdM" "MdM[src]"))))

;; Auto-mode disabled by default - users can enable with:
;; (add-to-list 'auto-mode-alist '("\\.md\\'" . markdown-modern-mode))
;; Or call M-x markdown-modern-mode manually in a markdown buffer

(defconst markdown-modern--modules
  '(markdown-modern-ts markdown-modern-mermaid markdown-modern-render
    markdown-modern-elements markdown-modern-commands markdown-modern-diagram
    markdown-modern-export markdown-modern)
  "List of markdown-modern source modules, in load order.")

;;;###autoload
(defun markdown-modern-reload ()
  "Reload markdown-modern source from `load-path' and re-render open buffers.
Picks up the latest edits to the package without restarting Emacs: each
module file is re-loaded (newest source wins via `load-prefer-newer'), then
`markdown-modern-mode' is re-applied to every live markdown-modern buffer so
the new code and overlays take effect."
  (interactive)
  (let ((buffers (seq-filter
                  (lambda (b) (buffer-local-value 'markdown-modern--rendering-enabled b))
                  (seq-filter (lambda (b)
                                (provided-mode-derived-p
                                 (buffer-local-value 'major-mode b) 'markdown-modern-mode))
                              (buffer-list)))))
    (dolist (m markdown-modern--modules)
      (load (symbol-name m) nil 'nomessage))
    (dolist (b buffers)
      (with-current-buffer b (markdown-modern-mode)))
    (message "markdown-modern: reloaded %d modules, re-rendered %d buffer(s)"
             (length markdown-modern--modules) (length buffers))))

(defvar-local markdown-modern--saved-wrap-state nil
  "Saved (VISUAL-LINE-MODE . VISUAL-FILL-COLUMN-MODE) before horizontal scroll.")

;;;###autoload
(defun markdown-modern-toggle-truncate-lines ()
  "Toggle between line wrapping and a horizontal-scroll view.
Long unwrapped lines (e.g. code) can then be read by scrolling horizontally
\(\\[scroll-left] / \\[scroll-right]) instead of soft-wrapping.  Tables are
already sized to fit the window (over-long cells are elided with `…'), so they
never wrap regardless; to read a wide table at its natural width, set
`markdown-modern-table-max-width' to a large number and turn this on to scroll.
This remembers and restores whatever wrapping minor modes were active, so it
does not impose `visual-line-mode' on a buffer that was not using it."
  (interactive)
  (if truncate-lines
      ;; Restore the wrapping state we saved when enabling truncation.
      (progn
        (setq truncate-lines nil)
        (when (car markdown-modern--saved-wrap-state) (visual-line-mode 1))
        (when (and (cdr markdown-modern--saved-wrap-state)
                   (fboundp 'visual-fill-column-mode))
          (visual-fill-column-mode 1))
        (markdown-modern--update-text-width-everywhere)
        (message "markdown-modern: line wrapping restored"))
    ;; Switch to horizontal scroll: truncation can't coexist with these.
    (setq markdown-modern--saved-wrap-state
          (cons (bound-and-true-p visual-line-mode)
                (bound-and-true-p visual-fill-column-mode)))
    (when (and (fboundp 'visual-fill-column-mode)
               (bound-and-true-p visual-fill-column-mode))
      (visual-fill-column-mode -1))
    (when (bound-and-true-p visual-line-mode) (visual-line-mode -1))
    (setq truncate-lines t)
    (setq-local auto-hscroll-mode 'current-line)
    (markdown-modern--update-text-width-everywhere)
    (message "markdown-modern: horizontal scroll on (lines no longer wrap)")))

;;; Fenced Code Block Helpers

(defun markdown-modern--fenced-code-block-at (pos)
  "Return (START . END) if POS is inside a fenced code block, nil otherwise."
  (when-let* ((block (markdown-modern-ts--containing-block pos)))
    (when (eq (markdown-modern-node-type block) 'code-block)
      (cons (markdown-modern-node-start block)
            (markdown-modern-node-end block)))))

(defun markdown-modern--fenced-code-block-content-at (pos)
  "Return plist describing the fenced code block at POS, or nil.
Plist keys: :block-start :block-end :content-start :content-end :language."
  (when-let* ((block (markdown-modern-ts--containing-block pos)))
    (when (eq (markdown-modern-node-type block) 'code-block)
      (let* ((node (markdown-modern-node-treesit-node block))
             ;; Sibling traversal can skip code_fence_content after the
             ;; grammar's zero-width block_continuation node.  Read the
             ;; parent's indexed children instead.
             (content (cl-find-if
                       (lambda (child)
                         (equal (treesit-node-type child) "code_fence_content"))
                       (treesit-node-children node)))
             (content-start (if content (treesit-node-start content)
                              (save-excursion
                                (goto-char (markdown-modern-node-start block))
                                (forward-line 1)
                                (point)))))
        (list :block-start (markdown-modern-node-start block)
              :block-end (markdown-modern-node-end block)
              :content-start content-start
              :content-end (if content (treesit-node-end content) content-start)
              :language (markdown-modern-node-language block))))))

;;; JIT Rendering and Reveal-at-Point
;;
;; Rendering is driven by `jit-lock': it calls `markdown-modern--jit-fontify' over
;; the visible region (and on scroll/edit), so only on-screen text is rendered.
;; A single piece of state, `markdown-modern--revealed-region', tracks the markup
;; element under point.  On cursor movement `markdown-modern--update-reveal' shows the
;; raw markup of that element (so it can be edited) and re-hides the previous
;; one.  `markdown-modern--jit-fontify' consults the same variable so the revealed
;; element stays revealed across re-renders.

(defun markdown-modern--table-row-region-p (region)
  "Return non-nil when REGION (a (START . END) cons) is a single table row.
A table row is a source line of the form `| ... |'.  The reveal logic treats
tables at row granularity: the table renderer keeps the rest of the box drawn
and renders the active row as an editable, aligned grid row, so its overlays
must NOT be stripped the way other revealed markup is."
  (and region
       (save-excursion
         (goto-char (car region))
         (beginning-of-line)
         (looking-at-p "^[ \t]*|.+|[ \t]*$"))))

(defun markdown-modern--table-row-at (pos start end)
  "Return (BOL . EOL) of the table row line at POS, clamped to START..END."
  (save-excursion
    (goto-char pos)
    (cons (max start (line-beginning-position))
          (min end (line-end-position)))))

(defun markdown-modern--extend-region-to-blocks (start end)
  "Expand START..END outward to whole containing-block bounds.
Clamp to the buffer and keep tables, fenced blocks and lists intact."
  (let ((bounds (markdown-modern-ts--containing-block-bounds start end)))
    (cons (max (point-min) (min start (car bounds)))
          (min (point-max) (max end (cdr bounds))))))

(defun markdown-modern--jit-fontify (start end)
  "Render markdown-modern overlays for the block(s) spanning START..END.
This is the `jit-lock' fontify function.  It widens to whole-block bounds,
renders, then re-reveals the element under point so the revealed markup
survives scroll/edit re-renders.  Returns a `jit-lock-bounds' cons reporting
the true rendered extent."
  (when markdown-modern--rendering-enabled
    (let* ((b (markdown-modern--extend-region-to-blocks start end))
           ;; Rendering can grow the region further, for example from one
           ;; list item to its whole list.
           (rendered (or (markdown-modern-render--render-region (car b) (cdr b))
                         b))
           (bstart (car rendered))
           (bend (cdr rendered)))
      ;; Keep the element under point revealed across re-renders (markup
      ;; visible, styling preserved).  A revealed table row is an exception: the
      ;; table renderer already drew it as an editable grid row during
      ;; `render-region' above, so stripping its display overlays here would
      ;; destroy that.
      (when (and markdown-modern--revealed-region
                 (< (car markdown-modern--revealed-region) bend)
                 (> (cdr markdown-modern--revealed-region) bstart)
                 (not (markdown-modern--table-row-region-p markdown-modern--revealed-region)))
        (markdown-modern-render--reveal-markup
         (max bstart (car markdown-modern--revealed-region))
         (min bend (cdr markdown-modern--revealed-region))))
      `(jit-lock-bounds ,bstart . ,bend))))

(defun markdown-modern--inline-element-at (pos start end)
  "Return (S . E) of the smallest inline markup element at POS within START..END.
Returns nil if POS is not within any inline markup.  Boundary-inclusive, so
POS immediately before or after the markup counts as inside it.  A
backslash escape or hard line break counts only when no other markup is at
POS: it is the smallest element wherever it is, and would keep the
delimiters of emphasis around or next to it hidden."
  (let ((best nil)
        (best-size nil)
        (backslash nil))
    (dolist (el (ignore-errors (markdown-modern-ts--inline-elements-in start end)))
      (let ((s (markdown-modern-node-start el))
            (e (markdown-modern-node-end el))
            (type (markdown-modern-node-type el)))
        (when (and s e (>= pos s) (<= pos e)
                   ;; A reference without a definition is plain text.
                   (or (not (memq type
                                  markdown-modern-render--reference-link-types))
                       (markdown-modern-render--reference-link-target el)))
          (if (memq type '(escape hard-break))
              (setq backslash (or backslash (cons s e)))
            (let ((size (- e s)))
              (when (or (null best-size) (< size best-size))
                (setq best (cons s e)
                      best-size size)))))))
    (or best backslash)))

(defconst markdown-modern--reveal-block-types
  '(heading code-block code-block-indented blockquote table hr html-block)
  "Block-level element types whose whole extent is revealed at point.")

(defconst markdown-modern--reveal-inline-types
  '(emphasis strong strikethrough code-span link link-ref link-ref-collapsed
    link-shortcut image autolink autolink-email escape hard-break)
  "Inline markup element types that are revealed individually at point.")

(defconst markdown-modern--marker-node-types
  '("list_marker_minus" "list_marker_plus" "list_marker_star"
    "list_marker_dot" "list_marker_parenthesis"
    "block_quote_marker")
  "Tree-sitter node types for line-leading markers revealed at point.
These render as glyphs (list bullets, blockquote bars); revealing them shows
the original source marker (`- ', `> ', ...) for editing.

Task checkboxes are deliberately excluded: a rendered checkbox is treated as a
toggle/remove widget (`markdown-modern-space-or-toggle-checkbox' and friends),
not as markup to reveal.  See `markdown-modern--marker-at'.")

(defun markdown-modern--marker-at-ts (pos)
  "Return (START . END) of a list/task/blockquote marker at or adjacent to POS.
Tree-sitter implementation."
  (cl-some
   (lambda (p)
     (when (and (> p 0) (<= p (point-max)))
       (when-let* ((node (markdown-modern-ts--node-at p)))
         (let ((n node) (hit nil) (depth 0))
           (while (and n (not hit) (< depth 3))
             (when (member (treesit-node-type n) markdown-modern--marker-node-types)
               (setq hit (cons (treesit-node-start n) (treesit-node-end n))))
             (setq n (treesit-node-parent n)
                   depth (1+ depth)))
           hit))))
   (list pos (1- pos))))

(defun markdown-modern--task-line-p (pos)
  "Return non-nil if the line containing POS is a task list item."
  (save-excursion
    (goto-char pos)
    (beginning-of-line)
    (looking-at "[ \t]*[-*+][ \t]+\\[[ xX]\\]")))

(defun markdown-modern--marker-at (pos)
  "Return (START . END) of a line-leading marker at or adjacent to POS, or nil.
Task list items are excluded entirely: a rendered checkbox is an interactive
toggle/remove widget, not markup to reveal, so neither the checkbox nor the
leading bullet of a task line is revealed at point."
  (unless (markdown-modern--task-line-p pos)
    (markdown-modern--marker-at-ts pos)))

(defun markdown-modern--markup-element-at (pos)
  "Return (START . END) of the smallest markup element containing POS.
Return nil when POS is in plain prose with no markup to reveal.  A line-leading
marker (list bullet, blockquote marker) under or adjacent to POS takes priority;
then inline markup (emphasis, code span, link, ...); then a block-level element
\(heading, code block, table, ...) revealed whole.  Task checkboxes are not
revealed; they are interactive widgets (see `markdown-modern--marker-at').
Uses the Markdown block and inline Tree-sitter grammars."
  (or (markdown-modern--marker-at pos)
      (markdown-modern--markup-element-at-ts pos)))

(defun markdown-modern--markup-element-at-ts (pos)
  "Tree-sitter implementation of `markdown-modern--markup-element-at' for POS."
  (when-let* ((block (markdown-modern-ts--containing-block pos)))
    (let ((btype (markdown-modern-node-type block))
          (bstart (markdown-modern-node-start block))
          (bend (markdown-modern-node-end block)))
      (cond
       ;; Prose containers: reveal the innermost inline markup at point.
       ((memq btype '(paragraph list-item))
        (markdown-modern--inline-element-at pos bstart bend))
       ;; Tables reveal at row granularity: return just the current row so the
       ;; renderer keeps the rest of the box and draws this row editable.
       ((eq btype 'table)
        (markdown-modern--table-row-at pos bstart bend))
       ;; Block-level markup: reveal the entire block.
       ((memq btype markdown-modern--reveal-block-types)
        (cons bstart bend))
       (t nil)))))

(defun markdown-modern--update-reveal ()
  "Reveal the markup of the element at point and re-hide the previous one.
Run from `post-command-hook'.  Cheap when point stays within the same element
or in plain prose: it only touches overlays when the element under point
actually changes."
  (when markdown-modern--rendering-enabled
    (let ((new (markdown-modern--markup-element-at (point)))
          (old markdown-modern--revealed-region))
      (unless (or (equal new old)
                  ;; Typing within the same table row only grows/shrinks its end
                  ;; bound; the active row is unchanged, and the jit re-render
                  ;; plus the live `:align-to' keep it aligned, so skip the
                  ;; reveal bookkeeping (avoids re-rendering the whole table on
                  ;; every keystroke).  The stale end bound is harmless: the
                  ;; renderer's overlap test still marks this row active.
                  (and old new
                       (= (car new) (car old))
                       (markdown-modern--table-row-region-p new)))
        ;; Publish the new revealed region first: the table renderer reads
        ;; `markdown-modern--revealed-region' to decide which row to draw as an
        ;; editable grid row, so it must be current before any re-render below.
        (setq markdown-modern--revealed-region new)
        ;; Hide the previously revealed element by cleanly re-rendering its
        ;; containing block (clear + re-render avoids duplicate overlays); for a
        ;; table this re-boxes the row we just left.
        (when old
          (let ((b (markdown-modern--extend-region-to-blocks (car old) (cdr old))))
            (markdown-modern-render--render-region (car b) (cdr b))))
        ;; Reveal the new element.  A table row is drawn by the table renderer
        ;; itself (an aligned, editable grid row), so re-render its block instead
        ;; of stripping display overlays the way `reveal-markup' does.  Other
        ;; markup keeps its raw source shown while the styling is preserved
        ;; (heading stays big, emphasis stays emphasised, ...).
        (when new
          (if (markdown-modern--table-row-region-p new)
              (let ((b (markdown-modern--extend-region-to-blocks (car new) (cdr new))))
                (markdown-modern-render--render-region (car b) (cdr b)))
            (markdown-modern-render--reveal-markup (car new) (cdr new))))))
    (markdown-modern--update-paragraph)))

(defun markdown-modern--paragraph-settled-p ()
  "Return non-nil if the right paragraph shows its source lines for point."
  (if markdown-modern-paragraph-reveal-delay
      (markdown-modern-render--same-overlays-p
       (markdown-modern-render--soft-breaks-around (point))
       markdown-modern-render--active-soft-breaks)
    (or (null markdown-modern-render--unfolded)
        (markdown-modern-render--unfolded-at-p (point)))))

(defun markdown-modern--update-paragraph ()
  "Choose the paragraph that shows its source lines after a command.
An edit shows the source lines of the paragraph at point right away.  Motion
never changes them: an idle timer does that once you pause.  Motion commands
use the layout on screen, so the layout must not change under them."
  (let ((tick (buffer-chars-modified-tick)))
    (cond
     ((and markdown-modern--chars-tick
           (/= tick markdown-modern--chars-tick))
      (markdown-modern-render--unfold-paragraph (point)))
     ((and (not (markdown-modern--paragraph-settled-p))
           (not (memq markdown-modern--paragraph-timer timer-idle-list)))
      (setq markdown-modern--paragraph-timer
            (run-with-idle-timer (or markdown-modern-paragraph-reveal-delay
                                     markdown-modern--paragraph-join-delay)
                                 nil #'markdown-modern--paragraph-idle))))
    (setq markdown-modern--chars-tick tick)))

(defun markdown-modern--paragraph-settle ()
  "Show the source lines of the paragraph that point rests in, if any.
Without `markdown-modern-paragraph-reveal-delay', only the paragraph you
edited shows its source lines, until point leaves it."
  (unless (markdown-modern--paragraph-settled-p)
    (markdown-modern-render--unfold-paragraph
     (and markdown-modern-paragraph-reveal-delay (point)))))

(defun markdown-modern--paragraph-idle ()
  "Settle the paragraph that shows its source lines in the selected window."
  (with-current-buffer (window-buffer)
    (when (and (derived-mode-p 'markdown-modern-mode)
               markdown-modern--rendering-enabled)
      (markdown-modern--paragraph-settle))))

;;; Core Functions

(defun markdown-modern--after-change (start end _old-len)
  "Invalidate the block containing START..END so jit-lock re-renders it.
This does no rendering itself: it only marks the affected block stale, so the
heavy work happens lazily in `markdown-modern--jit-fontify' on the next
redisplay.  Block widening ensures multi-line edits (closing a fence, adding a
table row) re-render the whole construct, not just the changed line.  The
block that ends on the line above is included too: an edit can end it, as
when the edited line becomes a list item."
  (when markdown-modern--rendering-enabled
    (let* ((above (save-excursion
                    (goto-char (min start end))
                    (forward-line 0)
                    (max (point-min) (1- (point)))))
           (b (if (markdown-modern-render--link-definitions-changed-p)
                  ;; Links elsewhere in the buffer may now resolve differently.
                  (cons (point-min) (point-max))
                (markdown-modern--extend-region-to-blocks above (max start end)))))
      (if (fboundp 'jit-lock-refontify)
          (jit-lock-refontify (car b) (cdr b))
        (with-silent-modifications
          (put-text-property (car b) (cdr b) 'fontified nil))))))

(defun markdown-modern--after-reparse (ranges parser)
  "Mark the blocks around RANGES for re-rendering.
RANGES are the ranges where the parse tree of PARSER changed.  This is a
tree-sitter notifier: the after-change hook renders only the block around
an edit again, but an edit can also change how distant text parses."
  (let ((buffer (treesit-parser-buffer parser)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when markdown-modern--rendering-enabled
          (dolist (range ranges)
            (let* ((start (max (point-min) (min (car range) (point-max))))
                   (end (max start (min (cdr range) (point-max))))
                   (b (markdown-modern--extend-region-to-blocks start end)))
              (jit-lock-refontify (car b) (cdr b)))))))))

;;; Imenu Support

(defun markdown-modern-imenu-create-index ()
  "Create Imenu index for current markdown buffer."
  (let ((headings '()))
    (markdown-modern-ts--walk-headings
     (lambda (node)
       (let* ((level (markdown-modern-node-level node))
              (text (markdown-modern-ts--heading-text node))
              (prefix (make-string level ?*)))
         (push (cons (format "%s %s" prefix text)
                     (markdown-modern-node-start node))
               headings))))
    (nreverse headings)))

(defun markdown-modern-unload-function ()
  "Remove the `window-splittable-p' advice when markdown-modern is unloaded.
Return nil so that `unload-feature' goes on with the normal unloading."
  (advice-remove 'window-splittable-p #'markdown-modern--window-splittable-p)
  nil)

(provide 'markdown-modern)
;;; markdown-modern.el ends here
