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
  (when-let ((elem (markdown-modern-ts--element-at (point))))
    (markdown-modern-node-type elem)))

(defun markdown-modern-in-heading-p ()
  "Return non-nil if point is in a heading."
  (eq (markdown-modern-element-at-point) 'heading))

(defun markdown-modern-in-code-block-p ()
  "Return non-nil if point is in a code block."
  (memq (markdown-modern-element-at-point) '(code-block code-block-indented)))

(defun markdown-modern-in-list-p ()
  "Return non-nil if point is in a list or list item."
  (memq (markdown-modern-element-at-point) '(list list-item)))

(defun markdown-modern-in-table-p ()
  "Return non-nil if point is in a table."
  (memq (markdown-modern-element-at-point) '(table table-header table-row table-cell)))

(defun markdown-modern-in-blockquote-p ()
  "Return non-nil if point is in a blockquote."
  (eq (markdown-modern-element-at-point) 'blockquote))

(defun markdown-modern-in-link-p ()
  "Return non-nil if point is in a link."
  (memq (markdown-modern-element-at-point) '(link link-ref link-ref-collapsed)))

;;; Heading Utilities

(defun markdown-modern-heading-level-at-point ()
  "Return the heading level at point, or nil if not in a heading."
  (or
   ;; Try tree-sitter first
   (when-let ((elem (ignore-errors (markdown-modern-ts--element-at (point)))))
     (when (eq (markdown-modern-node-type elem) 'heading)
       (markdown-modern-node-level elem)))
   ;; Fallback to regex
   (save-excursion
     (beginning-of-line)
     (when (looking-at "^\\(#\\{1,6\\}\\) ")
       (length (match-string 1))))))

(defun markdown-modern-current-heading ()
  "Return the nearest heading above point."
  (save-excursion
    (when (re-search-backward "^#+[ \t]+" nil t)
      (markdown-modern-ts--element-at (point)))))

(defun markdown-modern-heading-bounds ()
  "Return (START . END) bounds of current heading, or nil."
  (when-let ((elem (markdown-modern-ts--element-at (point))))
    (when (eq (markdown-modern-node-type elem) 'heading)
      (cons (markdown-modern-node-start elem)
            (markdown-modern-node-end elem)))))

;;; List Utilities

(defun markdown-modern-list-item-bounds ()
  "Return (START . END) bounds of current list item, or nil."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^\\([ \t]*\\)\\([-*+]\\|[0-9]+[.)]\\)[ \t]+")
      (let ((start (point))
            (indent (length (match-string 1))))
        ;; Find end of list item (next item at same or lower indent, or blank line)
        (forward-line 1)
        (while (and (not (eobp))
                    (not (looking-at "^[ \t]*$"))
                    (or (looking-at "^[ \t]+[^-*+0-9]")  ; continuation
                        (and (looking-at "^\\([ \t]*\\)[-*+0-9]")
                             (> (length (match-string 1)) indent))))
          (forward-line 1))
        (cons start (point))))))

(defun markdown-modern-list-level-at-point ()
  "Return the nesting level of list item at point (0-based)."
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^\\([ \t]*\\)[-*+0-9]")
      (/ (length (match-string 1)) 2))))

(defun markdown-modern-list-marker-at-point ()
  "Return the list marker type at point (:unordered, :ordered, :task)."
  (save-excursion
    (beginning-of-line)
    (cond
     ((looking-at "^[ \t]*[-*+][ \t]+\\[[ xX]\\]") :task)
     ((looking-at "^[ \t]*[-*+][ \t]+") :unordered)
     ((looking-at "^[ \t]*[0-9]+[.)][ \t]+") :ordered)
     (t nil))))

;;; Table Utilities

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
  (when-let ((elem (markdown-modern-ts--element-at (point))))
    (cons (markdown-modern-node-start elem)
          (markdown-modern-node-end elem))))

(defun markdown-modern-bounds-of-block-at-point ()
  "Return bounds of markdown block at point as (START . END)."
  (when-let ((block (markdown-modern-ts--containing-block (point))))
    (cons (markdown-modern-node-start block)
          (markdown-modern-node-end block))))

;; Register as thing-at-point types
(put 'markdown-modern-element 'bounds-of-thing-at-point
     #'markdown-modern-bounds-of-element-at-point)
(put 'markdown-modern-block 'bounds-of-thing-at-point
     #'markdown-modern-bounds-of-block-at-point)

(provide 'markdown-modern-elements)
;;; markdown-modern-elements.el ends here
