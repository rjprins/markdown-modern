;;; mark-graf.el --- Modern WYSIWYG-style markdown editing -*- lexical-binding: t; -*-

;; Copyright (C) 2026 mark-graf contributors

;; Author: Marc Ansset <info@ansset.com>
;; Version: 1.0.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: markdown, wp, text
;; URL: https://github.com/hyperZphere/mark-graf

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

;; mark-graf is a modern WYSIWYG-style markdown editing mode for Emacs 30+.
;; It provides inline WYSIWYG rendering using the text-property-based
;; approach of org-modern.
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
;;   (require 'mark-graf)
;;   ;; Automatically activates for .md files
;;
;; Customization:
;;   M-x customize-group RET mark-graf RET

;;; Code:

(require 'treesit)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; Load submodules
(require 'mark-graf-ts)
(require 'mark-graf-mermaid)
(require 'mark-graf-render)
(require 'mark-graf-elements)
(require 'mark-graf-commands)
(require 'mark-graf-export)

;;; Customization Groups

(defgroup mark-graf nil
  "Modern WYSIWYG-style markdown editing."
  :group 'text
  :group 'wp
  :prefix "mark-graf-")

(defgroup mark-graf-faces nil
  "Faces for mark-graf rendering."
  :group 'mark-graf
  :group 'faces)

(defgroup mark-graf-performance nil
  "Performance tuning for mark-graf."
  :group 'mark-graf)

(defgroup mark-graf-code nil
  "Code block settings for mark-graf."
  :group 'mark-graf)

(defgroup mark-graf-media nil
  "Image and media settings for mark-graf."
  :group 'mark-graf)

(defgroup mark-graf-math nil
  "Math rendering settings for mark-graf."
  :group 'mark-graf)

(defgroup mark-graf-export nil
  "Export settings for mark-graf."
  :group 'mark-graf)

;;; Customization Variables

(defcustom mark-graf-heading-scale '(1.8 1.5 1.3 1.1 1.05 1.0)
  "Height scale factors for heading levels 1-6."
  :type '(list number number number number number number)
  :group 'mark-graf-faces)

(defcustom mark-graf-heading-use-variable-pitch t
  "Whether headings should use variable-pitch font."
  :type 'boolean
  :group 'mark-graf-faces)

(defcustom mark-graf-display-images t
  "Whether to display images inline."
  :type 'boolean
  :group 'mark-graf-media)

(defcustom mark-graf-image-max-width 600
  "Maximum width in pixels for inline images."
  :type 'integer
  :group 'mark-graf-media)

(defcustom mark-graf-image-max-height 400
  "Maximum height in pixels for inline images."
  :type 'integer
  :group 'mark-graf-media)

(defcustom mark-graf-text-width 90
  "Maximum width in characters for rendered text content.
Content will be visually constrained to this width.
Set to nil to use the full window width."
  :type '(choice (integer :tag "Character width")
                 (const :tag "Full window width" nil))
  :group 'mark-graf)

(defcustom mark-graf-left-margin 4
  "Left margin width in characters.
This creates whitespace on the left side of the buffer for better readability."
  :type 'integer
  :group 'mark-graf)

(defcustom mark-graf-code-block-syntax-highlight t
  "Whether to apply syntax highlighting to code blocks.
When enabled, code blocks use Emacs font-lock for the specified language."
  :type 'boolean
  :group 'mark-graf-code)

(defcustom mark-graf-code-block-full-width t
  "Whether code block backgrounds extend to the window edge.
When enabled, the background color extends to the right margin."
  :type 'boolean
  :group 'mark-graf-code)

;;; Faces

(defface mark-graf-default
  '((t :inherit default))
  "Default face for mark-graf content."
  :group 'mark-graf-faces)

(defface mark-graf-heading-1
  '((t :height 1.8 :weight bold :inherit default))
  "Face for level 1 headings."
  :group 'mark-graf-faces)

(defface mark-graf-heading-2
  '((t :height 1.5 :weight bold :inherit default))
  "Face for level 2 headings."
  :group 'mark-graf-faces)

(defface mark-graf-heading-3
  '((t :height 1.3 :weight bold :inherit default))
  "Face for level 3 headings."
  :group 'mark-graf-faces)

(defface mark-graf-heading-4
  '((t :height 1.1 :weight bold :inherit default))
  "Face for level 4 headings."
  :group 'mark-graf-faces)

(defface mark-graf-heading-5
  '((t :height 1.05 :weight bold :inherit default))
  "Face for level 5 headings."
  :group 'mark-graf-faces)

(defface mark-graf-heading-6
  '((t :height 1.0 :weight bold :inherit default))
  "Face for level 6 headings."
  :group 'mark-graf-faces)

(defface mark-graf-bold
  '((t :weight bold :inherit default))
  "Face for bold/strong text."
  :group 'mark-graf-faces)

(defface mark-graf-italic
  '((t :slant italic))
  "Face for italic/emphasis text."
  :group 'mark-graf-faces)

(defface mark-graf-bold-italic
  '((t :weight bold :slant italic))
  "Face for bold italic text."
  :group 'mark-graf-faces)

(defface mark-graf-strikethrough
  '((t :strike-through t))
  "Face for strikethrough text."
  :group 'mark-graf-faces)

(defface mark-graf-inline-code
  '((((background light))
     :foreground "#c7254e")
    (((background dark))
     :foreground "#e06c75"))
  "Face for inline code spans.
Uses distinct color only, no background to keep clean appearance."
  :group 'mark-graf-faces)

(defface mark-graf-code-block
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
  :group 'mark-graf-faces)

(defface mark-graf-code-block-language
  '((((background light))
     :height 0.85
     :foreground "#666666"
     :slant italic)
    (((background dark))
     :height 0.85
     :foreground "#7a7a8a"
     :slant italic))
  "Face for code block language label."
  :group 'mark-graf-faces)

(defface mark-graf-link
  '((t :underline t :inherit link))
  "Face for link text."
  :group 'mark-graf-faces)

(defface mark-graf-link-url
  '((t :foreground "#888888" :height 0.9))
  "Face for link URLs when displayed."
  :group 'mark-graf-faces)

(defface mark-graf-image-alt
  '((t :foreground "#888888" :slant italic))
  "Face for image alt text placeholders."
  :group 'mark-graf-faces)

(defface mark-graf-blockquote
  '((((background light))
     :foreground "#555555"
     :slant italic)
    (((background dark))
     :foreground "#999999"
     :slant italic))
  "Face for blockquote text.
No background is used to avoid issues with visual-line-mode wrapping."
  :group 'mark-graf-faces)

(defface mark-graf-blockquote-marker
  '((t :foreground "#5588cc" :weight bold))
  "Face for blockquote left border marker."
  :group 'mark-graf-faces)

(defface mark-graf-list-bullet
  '((t :foreground "#5588cc"))
  "Face for list bullet characters."
  :group 'mark-graf-faces)

(defface mark-graf-list-number
  '((t :foreground "#5588cc" :weight bold))
  "Face for ordered list numbers."
  :group 'mark-graf-faces)

(defface mark-graf-task-unchecked
  '((t :foreground "#888888"))
  "Face for unchecked task checkboxes."
  :group 'mark-graf-faces)

(defface mark-graf-task-checked
  '((t :foreground "#22aa22"))
  "Face for checked task checkboxes."
  :group 'mark-graf-faces)

(defface mark-graf-task-done-text
  '((t :strike-through t :foreground "#888888"))
  "Face for completed task text."
  :group 'mark-graf-faces)

(defface mark-graf-table
  '((((background light))
     :inherit default
     :background "#e0e0f0")
    (((background dark))
     :inherit default
     :background "#2a2a45"))
  "Face for table data rows."
  :group 'mark-graf-faces)

(defface mark-graf-table-header
  '((((background light))
     :inherit mark-graf-table
     :weight bold)
    (((background dark))
     :inherit mark-graf-table
     :weight bold))
  "Face for table header cells (same background as table, bold text)."
  :group 'mark-graf-faces)

(defface mark-graf-table-border
  '((((background light))
     :inherit default
     :foreground "#888888"
     :background "#d8d8e0")
    (((background dark))
     :inherit default
     :foreground "#666666"
     :background "#202038"))
  "Face for table separator row."
  :group 'mark-graf-faces)

(defface mark-graf-table-cell
  '((t :inherit mark-graf-default))
  "Face for table cell content."
  :group 'mark-graf-faces)

(defface mark-graf-hr
  '((t :foreground "#cccccc"))
  "Face for horizontal rules."
  :group 'mark-graf-faces)

(defface mark-graf-footnote-ref
  '((t :height 0.8 :foreground "#5588cc" :underline t))
  "Face for footnote references."
  :group 'mark-graf-faces)

(defface mark-graf-math
  '((t :foreground "#aa5588"))
  "Face for math expressions."
  :group 'mark-graf-faces)

(defface mark-graf-delimiter
  '((t :foreground "#888888"))
  "Face for visible markdown delimiters."
  :group 'mark-graf-faces)

;; Force-update face attributes that defface won't change on reload
(dolist (face '(mark-graf-table mark-graf-table-border))
  (set-face-attribute face nil :extend nil))
;; Force-update math face in case it was previously defined differently
(set-face-attribute 'mark-graf-math nil
                    :foreground "#aa5588"
                    :inherit nil)

;;; Internal Variables

(defvar-local mark-graf--rendering-enabled t
  "Whether rendering is currently enabled in this buffer.")

(defvar-local mark-graf--revealed-region nil
  "Cons (START . END) of the markup element currently revealed at point.
Nil when point is in plain prose with no markup to reveal.  This is the
single source of truth shared between point-motion reveal and jit-lock.")

(defvar-local mark-graf--code-edit-buffer nil
  "Indirect buffer currently editing a code block, or nil.")

;;; Mode Definition

(defvar mark-graf-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Style insertion (C-c C-s prefix)
    (define-key map (kbd "C-c C-s b") #'mark-graf-insert-bold)
    (define-key map (kbd "C-c C-s i") #'mark-graf-insert-italic)
    (define-key map (kbd "C-c C-s c") #'mark-graf-insert-code)
    (define-key map (kbd "C-c C-s s") #'mark-graf-insert-strike)
    (define-key map (kbd "C-c C-s q") #'mark-graf-insert-blockquote)
    (define-key map (kbd "C-c C-s p") #'mark-graf-insert-code-block)
    (define-key map (kbd "C-c C-s k") #'mark-graf-insert-kbd)

    ;; Headings (C-c C-t prefix)
    (define-key map (kbd "C-c C-t h") #'mark-graf-insert-heading)
    (define-key map (kbd "C-c C-t 1") #'mark-graf-insert-heading-1)
    (define-key map (kbd "C-c C-t 2") #'mark-graf-insert-heading-2)
    (define-key map (kbd "C-c C-t 3") #'mark-graf-insert-heading-3)
    (define-key map (kbd "C-c C-t 4") #'mark-graf-insert-heading-4)
    (define-key map (kbd "C-c C-t 5") #'mark-graf-insert-heading-5)
    (define-key map (kbd "C-c C-t 6") #'mark-graf-insert-heading-6)
    (define-key map (kbd "C-c C-t !") #'mark-graf-promote-heading)
    (define-key map (kbd "C-c C-t @") #'mark-graf-demote-heading)

    ;; Links and images
    (define-key map (kbd "C-c C-l") #'mark-graf-insert-link)
    (define-key map (kbd "C-c C-i") #'mark-graf-insert-image)
    (define-key map (kbd "C-c C-x C-i") #'mark-graf-toggle-images)

    ;; Follow link at point
    (define-key map (kbd "C-c C-o") #'mark-graf-follow-link-at-point)

    ;; Navigation
    (define-key map (kbd "C-c C-n") #'mark-graf-next-heading)
    (define-key map (kbd "C-c C-p") #'mark-graf-prev-heading)
    (define-key map (kbd "C-c C-f") #'mark-graf-next-heading-same-level)
    (define-key map (kbd "C-c C-b") #'mark-graf-prev-heading-same-level)
    (define-key map (kbd "C-c C-u") #'mark-graf-up-heading)
    (define-key map (kbd "TAB") #'mark-graf-tab)
    (define-key map (kbd "<backtab>") #'mark-graf-backtab)

    ;; Lists
    (define-key map (kbd "M-RET") #'mark-graf-insert-list-item)
    (define-key map (kbd "C-c <up>") #'mark-graf-move-item-up)
    (define-key map (kbd "C-c <down>") #'mark-graf-move-item-down)
    (define-key map (kbd "C-c <left>") #'mark-graf-promote-item)
    (define-key map (kbd "C-c <right>") #'mark-graf-demote-item)
    (define-key map (kbd "C-c C-x C-b") #'mark-graf-toggle-checkbox)

    ;; Tables
    (define-key map (kbd "C-c |") #'mark-graf-insert-table)
    (define-key map (kbd "C-c C-c ^") #'mark-graf-table-sort)

    ;; Reveal raw markdown for the element at point on demand
    (define-key map (kbd "C-c C-v e") #'mark-graf-toggle-element-at-point)
    (define-key map (kbd "C-c C-x C-v") #'mark-graf-toggle-element-at-point)

    ;; Toggle horizontal-scroll view (for tables wider than the window)
    (define-key map (kbd "C-c C-v t") #'mark-graf-toggle-truncate-lines)

    ;; Code block editing
    (define-key map (kbd "C-c '") #'mark-graf-edit-code-block)

    ;; Export
    (define-key map (kbd "C-c C-e h") #'mark-graf-export-html)
    (define-key map (kbd "C-c C-e p") #'mark-graf-export-pdf)
    (define-key map (kbd "C-c C-e d") #'mark-graf-export-docx)
    (define-key map (kbd "C-c C-c p") #'mark-graf-preview-html)

    map)
  "Keymap for `mark-graf-mode'.")

(defun mark-graf--setup-buffer ()
  "Set up the current buffer for mark-graf-mode."
  (condition-case err
      (progn
        ;; Disable font-lock and remove any face properties left by
        ;; a previous major mode (e.g. markdown-mode)
        (font-lock-mode -1)
        (with-silent-modifications
          (remove-text-properties (point-min) (point-max) '(face nil)))

        ;; Ensure tree-sitter is available
        (mark-graf-ts--ensure-grammar)

        ;; Initialize parser
        (mark-graf-ts--init)

        ;; NB: do not force `display-line-numbers-mode' (or other UI minor
        ;; modes) here -- respect the user's global configuration.

        ;; Set up left indentation using line-prefix
        (let ((indent-str (propertize (make-string mark-graf-left-margin ?\s)
                                      'face 'default)))
          (setq-local line-prefix indent-str)
          (setq-local wrap-prefix indent-str))

        ;; Set up text width for readable line lengths
        (when mark-graf-text-width
          (setq-local fill-column mark-graf-text-width)
          (visual-line-mode 1)
          ;; Use visual-fill-column if available for proper width limiting
          (if (fboundp 'visual-fill-column-mode)
              (progn
                (setq-local visual-fill-column-width mark-graf-text-width)
                (setq-local visual-fill-column-center-text nil)
                (visual-fill-column-mode 1))
            ;; Fallback: use window margins to constrain width
            (mark-graf--apply-text-width)
            (add-hook 'window-size-change-functions #'mark-graf--on-window-size-change)))

        ;; Initialize rendering
        (mark-graf-render--init)

        ;; Set up hooks.  Rendering itself is driven by jit-lock, which renders
        ;; only the visible region (and re-renders on scroll/edit).  The
        ;; post-command hook reveals the markup of the element under point, and
        ;; the after-change hook invalidates the edited block for jit-lock.
        (jit-lock-register #'mark-graf--jit-fontify)
        (add-hook 'post-command-hook #'mark-graf--update-reveal nil t)
        (add-hook 'after-change-functions #'mark-graf--after-change nil t)
        ;; Clean up when switching to another major mode
        (add-hook 'change-major-mode-hook #'mark-graf--teardown-buffer nil t)

        ;; Set up imenu
        (setq-local imenu-create-index-function #'mark-graf-imenu-create-index))
    (error
     (message "mark-graf: Setup error (%s)" (error-message-string err)))))

(defun mark-graf--apply-text-width ()
  "Apply text width constraint using window margins."
  (when (and mark-graf-text-width (get-buffer-window))
    (let* ((win (get-buffer-window))
           (width (window-total-width win))
           (text-width (+ mark-graf-text-width mark-graf-left-margin))
           (right-margin (max 0 (- width text-width))))
      (set-window-margins win mark-graf-left-margin right-margin))))

(defun mark-graf--on-window-size-change (frame)
  "Update text width when window size changes."
  (dolist (win (window-list frame))
    (with-current-buffer (window-buffer win)
      (when (derived-mode-p 'mark-graf-mode)
        (mark-graf--apply-text-width)))))

(defun mark-graf--teardown-buffer ()
  "Clean up mark-graf-mode resources from buffer."
  ;; Stop jit-lock rendering and remove hooks
  (jit-lock-unregister #'mark-graf--jit-fontify)
  (remove-hook 'post-command-hook #'mark-graf--update-reveal t)
  (remove-hook 'after-change-functions #'mark-graf--after-change t)
  (remove-hook 'change-major-mode-hook #'mark-graf--teardown-buffer t)
  (remove-hook 'window-size-change-functions #'mark-graf--on-window-size-change)

  ;; Reset state
  (setq mark-graf--revealed-region nil)
  (when (and mark-graf--code-edit-buffer
             (buffer-live-p mark-graf--code-edit-buffer))
    (kill-buffer mark-graf--code-edit-buffer))
  (setq mark-graf--code-edit-buffer nil)

  ;; Disable visual modes
  (visual-line-mode -1)
  (when (fboundp 'visual-fill-column-mode)
    (visual-fill-column-mode -1))

  ;; Reset line prefix
  (setq-local line-prefix nil)
  (setq-local wrap-prefix nil)

  ;; Reset window margins
  (when (get-buffer-window)
    (set-window-margins (get-buffer-window) nil nil))

  ;; Clear overlays
  (mark-graf-render--clear-all))

;;;###autoload
(define-derived-mode mark-graf-mode text-mode "MG"
  "Major mode for editing Markdown with inline WYSIWYG rendering.

mark-graf renders markdown content inline using text properties and overlays,
providing a seamless reading/writing experience.

\\{mark-graf-mode-map}"
  :group 'mark-graf
  :syntax-table nil

  ;; Mode setup
  (mark-graf--setup-buffer)

  ;; Mode line
  (setq mode-name
        '(:eval (if mark-graf--rendering-enabled "MG" "MG[src]"))))

;; Auto-mode disabled by default - users can enable with:
;; (add-to-list 'auto-mode-alist '("\\.md\\'" . mark-graf-mode))
;; Or call M-x mark-graf-mode manually in a markdown buffer

(defconst mark-graf--modules
  '(mark-graf-ts mark-graf-mermaid mark-graf-render
    mark-graf-elements mark-graf-commands mark-graf-export mark-graf)
  "mark-graf source modules, in load order.")

;;;###autoload
(defun mark-graf-reload ()
  "Reload mark-graf source from `load-path' and re-render open buffers.
Picks up the latest edits to the package without restarting Emacs: each
module file is re-loaded (newest source wins via `load-prefer-newer'), then
`mark-graf-mode' is re-applied to every live mark-graf buffer so the new
code and overlays take effect."
  (interactive)
  (let ((buffers (seq-filter
                  (lambda (b) (buffer-local-value 'mark-graf--rendering-enabled b))
                  (seq-filter (lambda (b)
                                (provided-mode-derived-p
                                 (buffer-local-value 'major-mode b) 'mark-graf-mode))
                              (buffer-list)))))
    (dolist (m mark-graf--modules)
      (load (symbol-name m) nil 'nomessage))
    (dolist (b buffers)
      (with-current-buffer b (mark-graf-mode)))
    (message "mark-graf: reloaded %d modules, re-rendered %d buffer(s)"
             (length mark-graf--modules) (length buffers))))

;;;###autoload
(defun mark-graf-toggle-truncate-lines ()
  "Toggle between wrapped reading and horizontal-scroll view.
Tables render at their natural width and are never truncated; when one is
wider than the window, turn this on to read it by scrolling horizontally
\(\\[scroll-left] / \\[scroll-right], or just move point) instead of having
long lines wrap.  Toggling off restores `visual-line-mode' wrapping (and
`visual-fill-column-mode' if present)."
  (interactive)
  (if truncate-lines
      (progn
        (setq truncate-lines nil)
        (visual-line-mode 1)
        (when (and (fboundp 'visual-fill-column-mode) mark-graf-text-width)
          (visual-fill-column-mode 1))
        (message "mark-graf: line wrapping on"))
    (when (and (fboundp 'visual-fill-column-mode)
               (bound-and-true-p visual-fill-column-mode))
      (visual-fill-column-mode -1))
    (visual-line-mode -1)
    (setq truncate-lines t)
    (setq-local auto-hscroll-mode 'current-line)
    (message "mark-graf: horizontal scroll on (lines no longer wrap)")))

;;; Fenced Code Block Helpers

(defun mark-graf--fenced-code-block-at (pos)
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

(defun mark-graf--fenced-code-block-content-at (pos)
  "Return plist describing the fenced code block at POS, or nil.
Plist keys: :block-start :block-end :content-start :content-end :language."
  (when-let ((block (mark-graf--fenced-code-block-at pos)))
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
;; Rendering is driven by `jit-lock': it calls `mark-graf--jit-fontify' over
;; the visible region (and on scroll/edit), so only on-screen text is rendered.
;; A single piece of state, `mark-graf--revealed-region', tracks the markup
;; element under point.  On cursor movement `mark-graf--update-reveal' shows the
;; raw markup of that element (so it can be edited) and re-hides the previous
;; one.  `mark-graf--jit-fontify' consults the same variable so the revealed
;; element stays revealed across re-renders.

(defun mark-graf--extend-region-to-blocks (start end)
  "Expand START..END outward to whole containing-block bounds, clamped to buffer.
Ensures jit-lock never renders a partial table, fenced block, or list.
Uses tree-sitter `mark-graf-ts--containing-block-bounds' when available,
otherwise a regex paragraph/fence heuristic."
  (if mark-graf-ts--use-tree-sitter
      (let ((b (mark-graf-ts--containing-block-bounds start end)))
        (cons (max (point-min) (min start (car b)))
              (min (point-max) (max end (cdr b)))))
    (mark-graf--fallback-extend-region start end)))

(defun mark-graf--fallback-extend-region (start end)
  "Regex fallback for `mark-graf--extend-region-to-blocks'.
Expands to the enclosing fenced code block and the surrounding
blank-line-delimited paragraph window."
  (save-excursion
    ;; If START or END is inside a fenced code block, cover the whole fence.
    (let ((fb (or (mark-graf--fenced-code-block-at start)
                  (mark-graf--fenced-code-block-at end))))
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

(defun mark-graf--jit-fontify (start end)
  "Render mark-graf overlays for the block(s) spanning START..END.
This is the `jit-lock' fontify function.  It widens to whole-block bounds,
renders, then re-reveals the element under point so the revealed markup
survives scroll/edit re-renders.  Returns a `jit-lock-bounds' cons reporting
the true rendered extent."
  (when mark-graf--rendering-enabled
    (let* ((b (mark-graf--extend-region-to-blocks start end))
           (bstart (car b))
           (bend (cdr b)))
      (mark-graf-render--render-region bstart bend)
      ;; Keep the element under point revealed across re-renders.
      (when (and mark-graf--revealed-region
                 (< (car mark-graf--revealed-region) bend)
                 (> (cdr mark-graf--revealed-region) bstart))
        (mark-graf-render--clear-region
         (max bstart (car mark-graf--revealed-region))
         (min bend (cdr mark-graf--revealed-region))))
      `(jit-lock-bounds ,bstart . ,bend))))

(defun mark-graf--inline-element-at (pos start end)
  "Return (S . E) of the smallest inline markup element at POS within START..END.
Returns nil if POS is not within any inline markup.  Boundary-inclusive, so
POS immediately before or after the markup counts as inside it."
  (let ((best nil)
        (best-size nil))
    (dolist (el (ignore-errors (mark-graf-ts--inline-elements-in start end)))
      (let ((s (mark-graf-node-start el))
            (e (mark-graf-node-end el)))
        (when (and s e (>= pos s) (<= pos e))
          (let ((size (- e s)))
            (when (or (null best-size) (< size best-size))
              (setq best (cons s e)
                    best-size size))))))
    best))

(defconst mark-graf--reveal-block-types
  '(heading code-block code-block-indented blockquote table hr html-block)
  "Block-level element types whose whole extent is revealed at point.")

(defconst mark-graf--reveal-inline-types
  '(emphasis strong strikethrough code-span link link-ref link-ref-collapsed
    link-shortcut image autolink autolink-email)
  "Inline markup element types that are revealed individually at point.")

(defun mark-graf--markup-element-at (pos)
  "Return (START . END) of the smallest markup element whose scope contains POS.
Return nil when POS is in plain prose with no markup to reveal.  Inline markup
\(emphasis, code span, link, ...) takes priority over its containing block;
block-level markup (heading, code block, table, ...) is revealed whole.
Works with both the tree-sitter and regex-fallback parsers."
  (if mark-graf-ts--use-tree-sitter
      (mark-graf--markup-element-at-ts pos)
    (mark-graf--markup-element-at-fallback pos)))

(defun mark-graf--markup-element-at-ts (pos)
  "Tree-sitter implementation of `mark-graf--markup-element-at' for POS."
  (when-let ((block (mark-graf-ts--containing-block pos)))
    (let ((btype (mark-graf-node-type block))
          (bstart (mark-graf-node-start block))
          (bend (mark-graf-node-end block)))
      (cond
       ;; Prose containers: reveal the innermost inline markup at point.
       ((memq btype '(paragraph list-item))
        (mark-graf--inline-element-at pos bstart bend))
       ;; Block-level markup: reveal the entire block.
       ((memq btype mark-graf--reveal-block-types)
        (cons bstart bend))
       (t nil)))))

(defun mark-graf--markup-element-at-fallback (pos)
  "Regex-fallback implementation of `mark-graf--markup-element-at' for POS.
Parses the block window around POS and returns the smallest markup element
\(inline or block) containing POS, boundary-inclusive."
  (let* ((b (mark-graf--fallback-extend-region pos pos))
         (els (ignore-errors
                (mark-graf-ts--fallback-parse-region (car b) (cdr b))))
         (best nil)
         (best-size nil))
    (dolist (el els)
      (let ((type (mark-graf-node-type el))
            (s (mark-graf-node-start el))
            (e (mark-graf-node-end el)))
        (when (and s e (>= pos s) (<= pos e)
                   (or (memq type mark-graf--reveal-inline-types)
                       (memq type mark-graf--reveal-block-types)))
          (let ((size (- e s)))
            (when (or (null best-size) (< size best-size))
              (setq best (cons s e)
                    best-size size))))))
    best))

(defun mark-graf--update-reveal ()
  "Reveal the markup of the element at point and re-hide the previous one.
Run from `post-command-hook'.  Cheap when point stays within the same element
or in plain prose: it only touches overlays when the element under point
actually changes."
  (when mark-graf--rendering-enabled
    (let ((new (mark-graf--markup-element-at (point)))
          (old mark-graf--revealed-region))
      (unless (equal new old)
        ;; Hide the previously revealed element by cleanly re-rendering its
        ;; containing block (clear + re-render avoids duplicate overlays).
        (when old
          (let ((b (mark-graf--extend-region-to-blocks (car old) (cdr old))))
            (mark-graf-render--render-region (car b) (cdr b))))
        (setq mark-graf--revealed-region new)
        ;; Reveal the new element: drop its overlays so raw markup shows.
        (when new
          (mark-graf-render--clear-region (car new) (cdr new)))))))

;;; Core Functions

(defun mark-graf--after-change (start end _old-len)
  "Invalidate the block containing START..END so jit-lock re-renders it.
This does no rendering itself: it only marks the affected block stale, so the
heavy work happens lazily in `mark-graf--jit-fontify' on the next redisplay.
Block widening ensures multi-line edits (closing a fence, adding a table row)
re-render the whole construct, not just the changed line."
  (when mark-graf--rendering-enabled
    (let ((b (mark-graf--extend-region-to-blocks (min start end) (max start end))))
      (if (fboundp 'jit-lock-refontify)
          (jit-lock-refontify (car b) (cdr b))
        (with-silent-modifications
          (put-text-property (car b) (cdr b) 'fontified nil))))))

;;; Imenu Support

(defun mark-graf-imenu-create-index ()
  "Create Imenu index for current markdown buffer."
  (let ((headings '()))
    (mark-graf-ts--walk-headings
     (lambda (node)
       (let* ((level (mark-graf-node-level node))
              (text (mark-graf-ts--heading-text node))
              (prefix (make-string level ?*)))
         (push (cons (format "%s %s" prefix text)
                     (mark-graf-node-start node))
               headings))))
    (nreverse headings)))

(provide 'mark-graf)
;;; mark-graf.el ends here
