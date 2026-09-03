;;; markdown-modern.el --- Modern visual styling for Markdown buffers -*- lexical-binding: t; -*-

;; Copyright (C) 2026 markdown-modern contributors

;; Author: Marc Ansset <info@ansset.com>
;; Maintainer: Rutger Prins <rutgerprins@gmail.com>
;; Version: 1.0.1
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

;; Load submodules
(require 'markdown-modern-ts)
(require 'markdown-modern-mermaid)
(require 'markdown-modern-render)
(require 'markdown-modern-elements)
(require 'markdown-modern-commands)
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

(defcustom markdown-modern-text-width 90
  "Maximum width in characters for rendered text content.
Only takes effect when `markdown-modern-manage-text-width' is non-nil.
Set to nil to use the full window width."
  :type '(choice (integer :tag "Character width")
                 (const :tag "Full window width" nil))
  :group 'markdown-modern)

(defcustom markdown-modern-manage-text-width nil
  "Whether markdown-modern constrains the visual text width itself.
When non-nil, `markdown-modern-mode' sets `fill-column' to
`markdown-modern-text-width' and turns on `visual-line-mode' (and
`visual-fill-column-mode' if available) to constrain reading width.  When nil
\(the default), markdown-modern does not touch `fill-column', leaving width to
your own configuration.  Line wrapping is controlled separately by
`markdown-modern-visual-line'."
  :type 'boolean
  :group 'markdown-modern)

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
  '((t :weight bold :inherit default))
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
Inherits `fixed-pitch' so the bullet glyph is the same width as the raw
marker it replaces (no shift when the marker is revealed)."
  :group 'markdown-modern-faces)

(defface markdown-modern-list-number
  '((t :foreground "#5588cc" :weight bold))
  "Face for ordered list numbers."
  :group 'markdown-modern-faces)

(defface markdown-modern-task-unchecked
  '((t :foreground "#888888"))
  "Face for unchecked task checkboxes."
  :group 'markdown-modern-faces)

(defface markdown-modern-task-checked
  '((t :foreground "#22aa22"))
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

    ;; Code block editing
    (define-key map (kbd "C-c '") #'markdown-modern-edit-code-block)

    ;; Export
    (define-key map (kbd "C-c C-e h") #'markdown-modern-export-html)
    (define-key map (kbd "C-c C-e p") #'markdown-modern-export-pdf)
    (define-key map (kbd "C-c C-e d") #'markdown-modern-export-docx)
    (define-key map (kbd "C-c C-c p") #'markdown-modern-preview-html)

    map)
  "Keymap for `markdown-modern-mode'.")

(defun markdown-modern--setup-buffer ()
  "Set up the current buffer for markdown-modern-mode."
  (condition-case err
      (progn
        ;; Disable font-lock and remove any face properties left by
        ;; a previous major mode (e.g. markdown-mode)
        (font-lock-mode -1)
        (with-silent-modifications
          (remove-text-properties (point-min) (point-max) '(face nil)))

        ;; Ensure tree-sitter is available
        (markdown-modern-ts--ensure-grammar)

        ;; Initialize parser
        (markdown-modern-ts--init)

        ;; NB: do not force `display-line-numbers-mode' (or other UI minor
        ;; modes) here -- respect the user's global configuration.

        ;; Set up left indentation using line-prefix
        (let ((indent-str (propertize (make-string markdown-modern-left-margin ?\s)
                                      'face 'default)))
          (setq-local line-prefix indent-str)
          (setq-local wrap-prefix indent-str))

        ;; Constrain reading width only when explicitly opted in -- otherwise
        ;; leave `fill-column' and line wrapping to the user's configuration.
        (when (and markdown-modern-manage-text-width markdown-modern-text-width)
          (setq-local fill-column markdown-modern-text-width)
          (visual-line-mode 1)
          ;; Use visual-fill-column if available for proper width limiting
          (if (fboundp 'visual-fill-column-mode)
              (progn
                (setq-local visual-fill-column-width markdown-modern-text-width)
                (setq-local visual-fill-column-center-text nil)
                (visual-fill-column-mode 1))
            ;; Fallback: use window margins to constrain width
            (markdown-modern--apply-text-width)
            (add-hook 'window-size-change-functions #'markdown-modern--on-window-size-change)))

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
        (add-hook 'after-change-functions #'markdown-modern--after-change nil t)
        ;; Clean up when switching to another major mode
        (add-hook 'change-major-mode-hook #'markdown-modern--teardown-buffer nil t)

        ;; Set up imenu
        (setq-local imenu-create-index-function #'markdown-modern-imenu-create-index))
    (error
     (message "markdown-modern: Setup error (%s)" (error-message-string err)))))

(defun markdown-modern--apply-text-width ()
  "Apply text width constraint using window margins."
  (when (and markdown-modern-text-width (get-buffer-window))
    (let* ((win (get-buffer-window))
           (width (window-total-width win))
           (text-width (+ markdown-modern-text-width markdown-modern-left-margin))
           (right-margin (max 0 (- width text-width))))
      (set-window-margins win markdown-modern-left-margin right-margin))))

(defun markdown-modern--on-window-size-change (frame)
  "Update text width for the windows of FRAME on a size change."
  (dolist (win (window-list frame))
    (with-current-buffer (window-buffer win)
      (when (derived-mode-p 'markdown-modern-mode)
        (markdown-modern--apply-text-width)))))

(defun markdown-modern--teardown-buffer ()
  "Clean up markdown-modern-mode resources from buffer."
  ;; Stop jit-lock rendering and remove hooks
  (jit-lock-unregister #'markdown-modern--jit-fontify)
  (remove-hook 'post-command-hook #'markdown-modern--update-reveal t)
  (remove-hook 'after-change-functions #'markdown-modern--after-change t)
  (remove-hook 'change-major-mode-hook #'markdown-modern--teardown-buffer t)
  (remove-hook 'window-size-change-functions #'markdown-modern--on-window-size-change)

  ;; Reset state
  (setq markdown-modern--revealed-region nil)
  (when (and markdown-modern--code-edit-buffer
             (buffer-live-p markdown-modern--code-edit-buffer))
    (kill-buffer markdown-modern--code-edit-buffer))
  (setq markdown-modern--code-edit-buffer nil)

  ;; Disable only the visual modes markdown-modern turned on (see setup), so we
  ;; don't clobber settings the user manages elsewhere.
  (when (or markdown-modern-manage-text-width markdown-modern-visual-line)
    (visual-line-mode -1))
  (when (and markdown-modern-manage-text-width (fboundp 'visual-fill-column-mode))
    (visual-fill-column-mode -1))
  (when markdown-modern-variable-pitch
    (variable-pitch-mode -1))

  ;; Reset line prefix
  (setq-local line-prefix nil)
  (setq-local wrap-prefix nil)

  ;; Reset window margins
  (when (get-buffer-window)
    (set-window-margins (get-buffer-window) nil nil))

  ;; Clear overlays
  (markdown-modern-render--clear-all))

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
    markdown-modern-elements markdown-modern-commands markdown-modern-export markdown-modern)
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
    (message "markdown-modern: horizontal scroll on (lines no longer wrap)")))

;;; Fenced Code Block Helpers

(defun markdown-modern--fenced-code-block-at (pos)
  "Return (START . END) if POS is inside a fenced code block, nil otherwise.
Scans from buffer start, matching opening/closing fence pairs via regex."
  (save-match-data
    (save-excursion
      (goto-char (point-min))
      (let ((fence-re "^[ \t]*\\(```\\|~~~\\)"))
        (catch 'found
          (while (re-search-forward fence-re nil t)
            (let ((open-start (line-beginning-position))
                  (fence-char (match-string 1)))
              (forward-line 1)
              (let ((close-re (concat "^[ \t]*" (regexp-quote fence-char) "[ \t]*$")))
                (if (re-search-forward close-re nil t)
                    (let ((close-end (line-end-position)))
                      ;; Include trailing newline if present
                      (when (< close-end (point-max))
                        (setq close-end (1+ close-end)))
                      (when (and (>= pos open-start) (<= pos close-end))
                        (throw 'found (cons open-start close-end))))
                  ;; No closing fence found, skip to end
                  (goto-char (point-max))))))
          nil)))))

(defun markdown-modern--fenced-code-block-content-at (pos)
  "Return plist describing the fenced code block at POS, or nil.
Plist keys: :block-start :block-end :content-start :content-end :language."
  (when-let ((block (markdown-modern--fenced-code-block-at pos)))
    (save-match-data
      (save-excursion
        (goto-char (car block))
        (when (looking-at "^[ \t]*\\(```\\|~~~\\)\\([a-zA-Z0-9_+-]*\\)?[ \t]*\r?$")
          (let* ((language (match-string-no-properties 2))
                 (content-start (1+ (line-end-position)))
                 (content-end (save-excursion
                                (goto-char (cdr block))
                                (if (re-search-backward
                                     "^[ \t]*\\(```\\|~~~\\)[ \t]*\r?$"
                                     content-start t)
                                    (match-beginning 0)
                                  (cdr block)))))
            (list :block-start (car block)
                  :block-end (cdr block)
                  :content-start content-start
                  :content-end content-end
                  :language (if (and language (not (string-empty-p language)))
                                language
                              nil))))))))

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
  "Expand START..END outward to whole containing-block bounds, clamped to buffer.
Ensures jit-lock never renders a partial table, fenced block, or list.
Uses tree-sitter `markdown-modern-ts--containing-block-bounds' when available,
otherwise a regex paragraph/fence heuristic."
  (if markdown-modern-ts--use-tree-sitter
      (let ((b (markdown-modern-ts--containing-block-bounds start end)))
        (cons (max (point-min) (min start (car b)))
              (min (point-max) (max end (cdr b)))))
    (markdown-modern--fallback-extend-region start end)))

(defun markdown-modern--fallback-extend-region (start end)
  "Regex fallback for `markdown-modern--extend-region-to-blocks' over START..END.
Expands to the enclosing fenced code block and the surrounding
blank-line-delimited paragraph window."
  (save-excursion
    ;; If START or END is inside a fenced code block, cover the whole fence.
    (let ((fb (or (markdown-modern--fenced-code-block-at start)
                  (markdown-modern--fenced-code-block-at end))))
      (when fb
        (setq start (min start (car fb))
              end (max end (cdr fb)))))
    (let (rstart rend)
      ;; Backward to the first content line of the paragraph.
      (goto-char start)
      (forward-line 0)
      (while (and (not (bobp)) (not (looking-at-p "^[ \t]*$")))
        (forward-line -1))
      (when (looking-at-p "^[ \t]*$") (forward-line 1))
      (setq rstart (point))
      ;; Forward to the blank line (or eob) after the paragraph.
      (goto-char end)
      (forward-line 0)
      (while (and (not (eobp)) (not (looking-at-p "^[ \t]*$")))
        (forward-line 1))
      (setq rend (point))
      (cons (max (point-min) (min rstart start))
            (min (point-max) (max rend end))))))

(defun markdown-modern--jit-fontify (start end)
  "Render markdown-modern overlays for the block(s) spanning START..END.
This is the `jit-lock' fontify function.  It widens to whole-block bounds,
renders, then re-reveals the element under point so the revealed markup
survives scroll/edit re-renders.  Returns a `jit-lock-bounds' cons reporting
the true rendered extent."
  (when markdown-modern--rendering-enabled
    (let* ((b (markdown-modern--extend-region-to-blocks start end))
           (bstart (car b))
           (bend (cdr b)))
      (markdown-modern-render--render-region bstart bend)
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
POS immediately before or after the markup counts as inside it."
  (let ((best nil)
        (best-size nil))
    (dolist (el (ignore-errors (markdown-modern-ts--inline-elements-in start end)))
      (let ((s (markdown-modern-node-start el))
            (e (markdown-modern-node-end el)))
        (when (and s e (>= pos s) (<= pos e))
          (let ((size (- e s)))
            (when (or (null best-size) (< size best-size))
              (setq best (cons s e)
                    best-size size))))))
    best))

(defconst markdown-modern--reveal-block-types
  '(heading code-block code-block-indented blockquote table hr html-block)
  "Block-level element types whose whole extent is revealed at point.")

(defconst markdown-modern--reveal-inline-types
  '(emphasis strong strikethrough code-span link link-ref link-ref-collapsed
    link-shortcut image autolink autolink-email)
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
       (when-let ((node (markdown-modern-ts--node-at p)))
         (let ((n node) (hit nil) (depth 0))
           (while (and n (not hit) (< depth 3))
             (when (member (treesit-node-type n) markdown-modern--marker-node-types)
               (setq hit (cons (treesit-node-start n) (treesit-node-end n))))
             (setq n (treesit-node-parent n)
                   depth (1+ depth)))
           hit))))
   (list pos (1- pos))))

(defun markdown-modern--marker-at-fallback (pos)
  "Return (START . END) of a list/blockquote marker at or adjacent to POS.
Regex-fallback implementation."
  (save-excursion
    (goto-char pos)
    (beginning-of-line)
    (when (looking-at
           "[ \t]*\\(>+[ \t]?\\|[-*+][ \t]+\\|[0-9]+[.)][ \t]+\\)")
      (let ((ms (match-beginning 1)) (me (match-end 1)))
        ;; On or just after the list bullet / blockquote marker.
        (when (and (>= pos ms) (<= pos me))
          (cons ms me))))))

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
    (if markdown-modern-ts--use-tree-sitter
        (markdown-modern--marker-at-ts pos)
      (markdown-modern--marker-at-fallback pos))))

(defun markdown-modern--markup-element-at (pos)
  "Return (START . END) of the smallest markup element containing POS.
Return nil when POS is in plain prose with no markup to reveal.  A line-leading
marker (list bullet, blockquote marker) under or adjacent to POS takes priority;
then inline markup (emphasis, code span, link, ...); then a block-level element
\(heading, code block, table, ...) revealed whole.  Task checkboxes are not
revealed; they are interactive widgets (see `markdown-modern--marker-at').
Works with both the tree-sitter and regex-fallback parsers."
  (or (markdown-modern--marker-at pos)
      (if markdown-modern-ts--use-tree-sitter
          (markdown-modern--markup-element-at-ts pos)
        (markdown-modern--markup-element-at-fallback pos))))

(defun markdown-modern--markup-element-at-ts (pos)
  "Tree-sitter implementation of `markdown-modern--markup-element-at' for POS."
  (when-let ((block (markdown-modern-ts--containing-block pos)))
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

(defun markdown-modern--markup-element-at-fallback (pos)
  "Regex-fallback implementation of `markdown-modern--markup-element-at' for POS.
Parses the block window around POS and returns the smallest markup element
\(inline or block) containing POS, boundary-inclusive."
  (let* ((b (markdown-modern--fallback-extend-region pos pos))
         (els (ignore-errors
                (markdown-modern-ts--fallback-parse-region (car b) (cdr b))))
         (best nil)
         (best-size nil)
         (best-type nil))
    (dolist (el els)
      (let ((type (markdown-modern-node-type el))
            (s (markdown-modern-node-start el))
            (e (markdown-modern-node-end el)))
        (when (and s e (>= pos s) (<= pos e)
                   (or (memq type markdown-modern--reveal-inline-types)
                       (memq type markdown-modern--reveal-block-types)))
          (let ((size (- e s)))
            (when (or (null best-size) (< size best-size))
              (setq best (cons s e)
                    best-size size
                    best-type type))))))
    ;; Tables reveal at row granularity (see `markdown-modern--markup-element-at-ts').
    (when (and best (eq best-type 'table))
      (setq best (markdown-modern--table-row-at pos (car best) (cdr best))))
    best))

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
            (markdown-modern-render--reveal-markup (car new) (cdr new))))))))

;;; Core Functions

(defun markdown-modern--after-change (start end _old-len)
  "Invalidate the block containing START..END so jit-lock re-renders it.
This does no rendering itself: it only marks the affected block stale, so the
heavy work happens lazily in `markdown-modern--jit-fontify' on the next
redisplay.  Block widening ensures multi-line edits (closing a fence, adding a
table row) re-render the whole construct, not just the changed line."
  (when markdown-modern--rendering-enabled
    (let ((b (markdown-modern--extend-region-to-blocks (min start end) (max start end))))
      (if (fboundp 'jit-lock-refontify)
          (jit-lock-refontify (car b) (cdr b))
        (with-silent-modifications
          (put-text-property (car b) (cdr b) 'fontified nil))))))

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

(provide 'markdown-modern)
;;; markdown-modern.el ends here
