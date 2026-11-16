;;; markdown-modern-elements.el --- Element handlers for markdown-modern -*- lexical-binding: t; -*-

;; Copyright (C) 2026 markdown-modern contributors

;; This file is part of markdown-modern.

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

;; Element handlers for markdown-modern.
;; Provides insertion, manipulation, and detection for markdown elements.

;;; Code:

(require 'cl-lib)
(require 'treesit)

;; Functions defined in other markdown-modern files
(declare-function markdown-modern-ts--containing-block "markdown-modern-ts")
(declare-function markdown-modern-ts--element-at "markdown-modern-ts")
(declare-function markdown-modern-node-type "markdown-modern-ts")
(declare-function markdown-modern-node-level "markdown-modern-ts")
(declare-function markdown-modern-node-start "markdown-modern-ts")
(declare-function markdown-modern-node-end "markdown-modern-ts")

;;; Element Detection

(defun markdown-modern-element-at-point ()
  "Return the type of markdown element at point."
  (when-let* ((elem (markdown-modern-ts--element-at (point))))
    (markdown-modern-node-type elem)))

(defvar markdown-modern-ts--parser)
(declare-function markdown-modern-ts--map-node-type "markdown-modern-ts")
(declare-function markdown-modern-ts--inline-elements-in "markdown-modern-ts")

(defun markdown-modern--node-types-around (parser &optional pos)
  "Return the types of the PARSER nodes around POS, innermost first.
POS defaults to point.  At the end of a line, look at its last character,
so that point after the text still counts as inside it.  Types are mapped
as in `markdown-modern-ts--node-type-map'."
  (when parser
    (let* ((pos (or pos (point)))
           (pos (if (and (> pos (point-min))
                         (save-excursion
                           (goto-char pos)
                           (and (eolp) (not (bolp)))))
                    (1- pos)
                  pos))
           (node (treesit-node-on pos (min (1+ pos) (point-max)) parser t))
           (types nil))
      (while node
        (push (markdown-modern-ts--map-node-type (treesit-node-type node)) types)
        (setq node (treesit-node-parent node)))
      (nreverse types))))

(defun markdown-modern--inside-block-p (types)
  "Return non-nil if point is inside a block of one of TYPES.
The innermost syntax node at point is usually a marker or inline text, so
look at all the blocks that contain it."
  (cl-some (lambda (type) (memq type types))
           (markdown-modern--node-types-around markdown-modern-ts--parser)))

(defun markdown-modern-in-heading-p ()
  "Return non-nil if point is in a heading."
  (markdown-modern--inside-block-p '(heading)))

(defun markdown-modern-in-code-block-p ()
  "Return non-nil if point is in a code block."
  (markdown-modern--inside-block-p '(code-block code-block-indented)))

(defun markdown-modern-in-list-p ()
  "Return non-nil if point is in the text of a list item.
Point in a code block, HTML block or table inside an item is in that
block, not in the list."
  (memq (cl-find-if (lambda (type)
                      (memq type '(list list-item code-block code-block-indented
                                        html-block table)))
                    (markdown-modern--node-types-around markdown-modern-ts--parser))
        '(list list-item)))

(defun markdown-modern-in-table-p ()
  "Return non-nil if point is in a table."
  (or (markdown-modern--inside-block-p
       '(table table-header table-row table-cell))
      (markdown-modern--table-row-below-separator-p)))

(defun markdown-modern-in-blockquote-p ()
  "Return non-nil if point is in a blockquote."
  (markdown-modern--inside-block-p '(blockquote)))

(defun markdown-modern-in-link-p ()
  "Return non-nil if point is in a link."
  (when-let* ((block (markdown-modern-ts--containing-block (point))))
    (let ((pos (point)))
      (cl-some (lambda (elem)
                 (and (memq (markdown-modern-node-type elem)
                            '(link link-ref link-ref-collapsed))
                      (<= (markdown-modern-node-start elem) pos)
                      (< pos (markdown-modern-node-end elem))))
               (markdown-modern-ts--inline-elements-in
                (markdown-modern-node-start block)
                (markdown-modern-node-end block))))))

;;; Heading Utilities

(defun markdown-modern-heading-level-at-point ()
  "Return the heading level at point, or nil if not in a heading."
  (when-let* ((elem (markdown-modern-ts--containing-block (point))))
    (when (eq (markdown-modern-node-type elem) 'heading)
      (markdown-modern-node-level elem))))

(defun markdown-modern-current-heading ()
  "Return the nearest heading above point."
  (save-excursion
    (when (re-search-backward "^#+[ \t]+" nil t)
      (markdown-modern-ts--element-at (point)))))

(defun markdown-modern-heading-bounds ()
  "Return (START . END) bounds of current heading, or nil."
  (when-let* ((elem (markdown-modern-ts--element-at (point))))
    (when (eq (markdown-modern-node-type elem) 'heading)
      (cons (markdown-modern-node-start elem)
            (markdown-modern-node-end elem)))))

;;; Table Utilities

(defun markdown-modern--table-row-line-p ()
  "Return non-nil if the current line is a table row."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "[ \t]*|")))

(defun markdown-modern--table-separator-line-p ()
  "Return non-nil if the current line is a table separator row."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "[ \t]*|?[-:| \t]*-[-:| \t]*$")))

(defun markdown-modern--table-row-below-separator-p ()
  "Return non-nil if the current line is a table row below a separator row.
The Markdown grammar does not parse a body row whose cells are all empty,
so this text check finds those rows too."
  (save-excursion
    (when (markdown-modern--table-row-line-p)
      (let ((found nil))
        (while (and (not found)
                    (zerop (forward-line -1))
                    (markdown-modern--table-row-line-p))
          (setq found (markdown-modern--table-separator-line-p)))
        found))))

(defun markdown-modern-table-bounds ()
  "Return (START . END) bounds of current table, or nil."
  (when (markdown-modern-in-table-p)
    (save-excursion
      (let (start end)
        ;; Find start
        (while (and (not (bobp))
                    (looking-at "^|"))
          (setq start (point))
          (forward-line -1))
        (unless start (setq start (point)))
        ;; Find end
        (goto-char start)
        (while (and (not (eobp))
                    (looking-at "^|"))
          (forward-line 1))
        (setq end (point))
        (cons start end)))))

(defun markdown-modern-table-cell-bounds ()
  "Return (START . END) bounds of current table cell, or nil."
  (when (markdown-modern-in-table-p)
    (save-excursion
      (let ((pos (point)))
        (beginning-of-line)
        (let ((_line-start (point))
              (cell-start nil)
              (cell-end nil))
          ;; Find cell boundaries
          (while (and (< (point) pos)
                      (re-search-forward "|" (line-end-position) t))
            (setq cell-start (point)))
          (when cell-start
            (if (re-search-forward "|" (line-end-position) t)
                (setq cell-end (1- (point)))
              (setq cell-end (line-end-position)))
            (cons cell-start cell-end)))))))

(defun markdown-modern-table-column-at-point ()
  "Return 0-based column index of current table cell."
  (when (markdown-modern-in-table-p)
    (save-excursion
      (let ((pos (point))
            (col 0))
        (beginning-of-line)
        (while (and (< (point) pos)
                    (search-forward "|" (line-end-position) t))
          (when (<= (point) pos)
            (setq col (1+ col))))
        (1- col)))))

;;; Code Block Utilities

(defun markdown-modern-code-block-bounds ()
  "Return (START . END) bounds of current code block, or nil."
  (when (markdown-modern-in-code-block-p)
    (save-excursion
      (let ((start nil) (end nil))
        ;; Find opening fence
        (when (re-search-backward "^```\\|^~~~" nil t)
          (setq start (point))
          ;; Find closing fence
          (forward-line 1)
          (when (re-search-forward "^```\\|^~~~" nil t)
            (setq end (line-end-position))
            (cons start end)))))))

(defun markdown-modern-code-block-language ()
  "Return the language of the current code block, or nil."
  (when (markdown-modern-in-code-block-p)
    (save-excursion
      (when (re-search-backward "^```\\([a-zA-Z0-9_+-]*\\)\\|^~~~\\([a-zA-Z0-9_+-]*\\)" nil t)
        (or (match-string 1) (match-string 2))))))

;;; Blockquote Utilities

(defun markdown-modern-blockquote-level-at-point ()
  "Return the nesting level of blockquote at point (1-based)."
  (save-excursion
    (beginning-of-line)
    (if (looking-at "^\\(>+\\)")
        (length (match-string 1))
      0)))

;;; Element Insertion Helpers

(defun markdown-modern--wrap-region-or-insert (open close)
  "Wrap region with OPEN and CLOSE, or insert both at point."
  (if (use-region-p)
      (let ((start (region-beginning))
            (end (region-end)))
        (save-excursion
          (goto-char end)
          (insert close)
          (goto-char start)
          (insert open)))
    (insert open close)
    (backward-char (length close))))

(defun markdown-modern--toggle-markup (open close)
  "Toggle markup OPEN/CLOSE around current word or region."
  (if (use-region-p)
      (let* ((start (region-beginning))
             (end (region-end))
             (text (buffer-substring-no-properties start end)))
        (if (and (string-prefix-p open text)
                 (string-suffix-p close text))
            ;; Remove markup
            (progn
              (delete-region start end)
              (insert (substring text (length open) (- (length text) (length close)))))
          ;; Add markup
          (delete-region start end)
          (insert open text close)))
    ;; No region - check if we're inside markup
    (let ((word-bounds (bounds-of-thing-at-point 'word)))
      (if word-bounds
          (let* ((start (car word-bounds))
                 (end (cdr word-bounds))
                 (check-start (max (point-min) (- start (length open))))
                 (check-end (min (point-max) (+ end (length close))))
                 (text (buffer-substring-no-properties check-start check-end)))
            (if (and (string-prefix-p open text)
                     (string-suffix-p close text))
                ;; Remove markup
                (progn
                  (delete-region check-start check-end)
                  (insert (substring text (length open) (- (length text) (length close)))))
              ;; Add markup around word
              (save-excursion
                (goto-char end)
                (insert close)
                (goto-char start)
                (insert open))))
        ;; No word at point - just insert
        (insert open close)
        (backward-char (length close))))))

(defun markdown-modern--ensure-blank-line-before ()
  "Ensure there's a blank line before point."
  (unless (or (bobp)
              (save-excursion
                (forward-line -1)
                (looking-at "^[ \t]*$")))
    (insert "\n")))

(defun markdown-modern--ensure-blank-line-after ()
  "Ensure there's a blank line after point."
  (unless (or (eobp)
              (save-excursion
                (forward-line 1)
                (looking-at "^[ \t]*$")))
    (save-excursion (insert "\n"))))

(defun markdown-modern--at-line-start-p ()
  "Return non-nil if point is at the start of a line (ignoring whitespace)."
  (save-excursion
    (skip-chars-backward " \t")
    (bolp)))

;;; Text Object Functions (for integration with evil-mode etc.)

(defun markdown-modern-bounds-of-element-at-point ()
  "Return bounds of markdown element at point as (START . END)."
  (when-let* ((elem (markdown-modern-ts--element-at (point))))
    (cons (markdown-modern-node-start elem)
          (markdown-modern-node-end elem))))

(defun markdown-modern-bounds-of-block-at-point ()
  "Return bounds of markdown block at point as (START . END)."
  (when-let* ((block (markdown-modern-ts--containing-block (point))))
    (cons (markdown-modern-node-start block)
          (markdown-modern-node-end block))))

;; Register as thing-at-point types
(put 'markdown-modern-element 'bounds-of-thing-at-point
     #'markdown-modern-bounds-of-element-at-point)
(put 'markdown-modern-block 'bounds-of-thing-at-point
     #'markdown-modern-bounds-of-block-at-point)

(provide 'markdown-modern-elements)
;;; markdown-modern-elements.el ends here
