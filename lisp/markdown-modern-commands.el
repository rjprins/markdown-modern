;;; markdown-modern-commands.el --- Commands for markdown-modern -*- lexical-binding: t; -*-

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

;; Interactive commands for markdown-modern-mode.
;; Includes insertion, navigation, and manipulation commands.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'treesit)

;; Functions defined in other markdown-modern files
(declare-function markdown-modern-in-heading-p "markdown-modern-elements")
(declare-function markdown-modern-in-table-p "markdown-modern-elements")
(declare-function markdown-modern--table-row-line-p "markdown-modern-elements")
(declare-function markdown-modern--table-separator-line-p "markdown-modern-elements")
(declare-function markdown-modern-in-list-p "markdown-modern-elements")
(declare-function markdown-modern--block-node-at "markdown-modern-elements")
(declare-function markdown-modern-table-bounds "markdown-modern-elements")
(declare-function markdown-modern-table-column-at-point "markdown-modern-elements")
(declare-function markdown-modern-heading-level-at-point "markdown-modern-elements")
(declare-function markdown-modern--at-line-start-p "markdown-modern-elements")
(declare-function markdown-modern--ensure-blank-line-before "markdown-modern-elements")
(declare-function markdown-modern--toggle-markup "markdown-modern-elements")
(declare-function markdown-modern--wrap-region-or-insert "markdown-modern-elements")

;; Variables defined in markdown-modern.el
(defvar markdown-modern-display-images)
(defvar markdown-modern--rendering-enabled)
(defvar markdown-modern--full-render-done-p)
(defvar markdown-modern--code-edit-buffer)
(defvar markdown-modern-ts--parser)

;; Functions defined in markdown-modern.el
(declare-function markdown-modern--fenced-code-block-content-at "markdown-modern")

;; Functions defined in markdown-modern-render.el
(declare-function markdown-modern-render--render-region "markdown-modern-render")
(declare-function markdown-modern-render--unescaped-pipes "markdown-modern-render")
(declare-function markdown-modern-render--clear-all "markdown-modern-render")
(declare-function markdown-modern-render--unrender-region "markdown-modern-render")
(declare-function markdown-modern-render--language-to-mode "markdown-modern-render")
(declare-function markdown-modern-render--follow-link "markdown-modern-render")
(declare-function markdown-modern-render--link-definition "markdown-modern-render")

;; Functions defined in markdown-modern-ts.el
(declare-function markdown-modern-ts--element-at "markdown-modern-ts")
(declare-function markdown-modern-node-start "markdown-modern-ts")
(declare-function markdown-modern-node-end "markdown-modern-ts")

;; Functions from outline.el (may not be loaded)
(declare-function outline-cycle "outline")
(declare-function outline-cycle-buffer "outline")

;;; Style Insertion Commands

;;;###autoload
(defun markdown-modern-insert-bold ()
  "Insert bold markers or toggle bold on region/word."
  (interactive)
  (markdown-modern--toggle-markup "**" "**"))

;;;###autoload
(defun markdown-modern-insert-italic ()
  "Insert italic markers or toggle italic on region/word."
  (interactive)
  (markdown-modern--toggle-markup "*" "*"))

;;;###autoload
(defun markdown-modern-insert-code ()
  "Insert inline code markers or toggle on region/word."
  (interactive)
  (markdown-modern--toggle-markup "`" "`"))

;;;###autoload
(defun markdown-modern-insert-strike ()
  "Insert strikethrough markers or toggle on region/word."
  (interactive)
  (markdown-modern--toggle-markup "~~" "~~"))

;;;###autoload
(defun markdown-modern-insert-kbd ()
  "Insert <kbd> tags or wrap region."
  (interactive)
  (markdown-modern--wrap-region-or-insert "<kbd>" "</kbd>"))

;;;###autoload
(defun markdown-modern-insert-blockquote ()
  "Insert blockquote markers on current line or region."
  (interactive)
  (if (use-region-p)
      (let ((start (region-beginning))
            (end (region-end)))
        (save-excursion
          (goto-char start)
          (while (< (point) end)
            (unless (looking-at "^>")
              (insert "> ")
              (setq end (+ end 2)))
            (forward-line 1))))
    (beginning-of-line)
    (if (looking-at "^>+ ?")
        ;; Add another level - preserve relative position
        (save-excursion
          (insert ">"))
      ;; Start new blockquote - move point after markers
      (insert "> "))))

;;;###autoload
(defun markdown-modern-insert-code-block (&optional language)
  "Insert a fenced code block with optional LANGUAGE."
  (interactive
   (list (read-string "Language (optional): ")))
  (markdown-modern--ensure-blank-line-before)
  (let ((lang (or language "")))
    (insert (format "```%s\n\n```" lang))
    (forward-line -1)))

;;; Heading Commands

;;;###autoload
(defun markdown-modern-insert-heading (&optional level)
  "Insert a heading at LEVEL, or prompt for one when not specified."
  (interactive
   (list (read-number "Heading level (1-6): " 2)))
  (let ((lvl (max 1 (min 6 (or level 2)))))
    (if (markdown-modern--at-line-start-p)
        (progn
          (beginning-of-line)
          ;; Remove existing heading markers if any
          (when (looking-at "^#+ *")
            (delete-region (match-beginning 0) (match-end 0)))
          (insert (make-string lvl ?#) " "))
      ;; Not at line start - insert new line
      (end-of-line)
      (insert "\n\n" (make-string lvl ?#) " "))))

;;;###autoload
(defun markdown-modern-insert-heading-1 ()
  "Insert a level 1 heading."
  (interactive)
  (markdown-modern-insert-heading 1))

;;;###autoload
(defun markdown-modern-insert-heading-2 ()
  "Insert a level 2 heading."
  (interactive)
  (markdown-modern-insert-heading 2))

;;;###autoload
(defun markdown-modern-insert-heading-3 ()
  "Insert a level 3 heading."
  (interactive)
  (markdown-modern-insert-heading 3))

;;;###autoload
(defun markdown-modern-insert-heading-4 ()
  "Insert a level 4 heading."
  (interactive)
  (markdown-modern-insert-heading 4))

;;;###autoload
(defun markdown-modern-insert-heading-5 ()
  "Insert a level 5 heading."
  (interactive)
  (markdown-modern-insert-heading 5))

;;;###autoload
(defun markdown-modern-insert-heading-6 ()
  "Insert a level 6 heading."
  (interactive)
  (markdown-modern-insert-heading 6))

;;;###autoload
(defun markdown-modern-promote-heading ()
  "Promote current heading (decrease level, e.g., ## -> #)."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^\\(#\\{2,6\\}\\) +")
      (delete-char 1))))

;;;###autoload
(defun markdown-modern-demote-heading ()
  "Demote current heading (increase level, e.g., # -> ##)."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (when (looking-at "^\\(#\\{1,5\\}\\) +")
      (goto-char (match-end 1))
      (insert "#"))))

;;; Link and Image Commands

;;;###autoload
(defun markdown-modern-insert-link (&optional url text)
  "Insert a markdown link with URL and TEXT."
  (interactive
   (let* ((default-text (if (use-region-p)
                            (buffer-substring-no-properties
                             (region-beginning) (region-end))
                          ""))
          (text (read-string "Link text: " default-text))
          (url (read-string "URL: ")))
     (list url text)))
  (when (use-region-p)
    (delete-region (region-beginning) (region-end)))
  (insert (format "[%s](%s)" (or text "link") (or url "")))
  (when (string-empty-p (or url ""))
    (backward-char 1)))

;;;###autoload
(defun markdown-modern-insert-image (&optional path alt)
  "Insert a markdown image with PATH and ALT text."
  (interactive
   (let* ((default-path (read-file-name "Image file: " nil nil nil nil
                                        (lambda (f)
                                          (or (file-directory-p f)
                                              (string-match-p
                                               "\\.\\(png\\|jpe?g\\|gif\\|svg\\|webp\\)$"
                                               f)))))
          (alt (read-string "Alt text: ")))
     (list default-path alt)))
  (let ((relative-path (if (and buffer-file-name
                                (file-name-absolute-p path))
                           (file-relative-name path
                                              (file-name-directory buffer-file-name))
                         path)))
    (insert (format "![%s](%s)" (or alt "") relative-path))))

;;;###autoload
(defun markdown-modern-toggle-images ()
  "Toggle display of inline images in buffer."
  (interactive)
  (setq markdown-modern-display-images (not markdown-modern-display-images))
  (markdown-modern-render--render-region (point-min) (point-max))
  (message "Image display %s" (if markdown-modern-display-images "enabled" "disabled")))

;;; Navigation Commands

;;;###autoload
(defun markdown-modern-next-heading ()
  "Move to next heading."
  (interactive)
  (let ((pos (point)))
    (end-of-line)
    (if (re-search-forward "^#+ " nil t)
        (beginning-of-line)
      (goto-char pos)
      (message "No more headings"))))

;;;###autoload
(defun markdown-modern-prev-heading ()
  "Move to previous heading."
  (interactive)
  (let ((pos (point)))
    ;; Search backward from current position - re-search-backward finds
    ;; matches starting strictly before point
    (if (re-search-backward "^#\\{1,6\\} " nil t)
        (beginning-of-line)
      (goto-char pos)
      (message "No previous heading"))))

;;;###autoload
(defun markdown-modern-next-heading-same-level ()
  "Move to next heading at the same level."
  (interactive)
  (let ((level (markdown-modern-heading-level-at-point)))
    (if level
        (let ((pattern (format "^%s " (make-string level ?#)))
              (pos (point)))
          (end-of-line)
          (if (re-search-forward pattern nil t)
              (beginning-of-line)
            (goto-char pos)
            (message "No more headings at level %d" level)))
      (markdown-modern-next-heading))))

;;;###autoload
(defun markdown-modern-prev-heading-same-level ()
  "Move to previous heading at the same level."
  (interactive)
  (let ((level (markdown-modern-heading-level-at-point)))
    (if level
        (let ((pattern (format "^%s " (make-string level ?#)))
              (pos (point)))
          (beginning-of-line)
          (if (re-search-backward pattern nil t)
              (beginning-of-line)
            (goto-char pos)
            (message "No previous heading at level %d" level)))
      (markdown-modern-prev-heading))))

;;;###autoload
(defun markdown-modern-up-heading ()
  "Move to parent heading (one level up)."
  (interactive)
  (let ((level (or (markdown-modern-heading-level-at-point)
                   (save-excursion
                     (markdown-modern-prev-heading)
                     (markdown-modern-heading-level-at-point))
                   1)))
    (if (> level 1)
        (let ((pattern (format "^%s " (make-string (1- level) ?#)))
              (pos (point)))
          (beginning-of-line)
          (if (re-search-backward pattern nil t)
              (beginning-of-line)
            (goto-char pos)
            (message "No parent heading")))
      (message "Already at top level"))))

;;; List Commands

;;; List items in the parse tree

(defun markdown-modern--list-item-node (&optional pos)
  "Return the innermost list_item node around POS, or nil.
POS is as for `markdown-modern--block-node-at'."
  (treesit-parent-until
   (markdown-modern--block-node-at pos)
   (lambda (n) (equal (treesit-node-type n) "list_item"))
   t))

(defun markdown-modern--list-item-region (item)
  "Return (START . END) of the whole source lines of list ITEM.
START is the start of the item's first line.  END is the start of the line
after its last non-blank line, or the end of the buffer.  Nested items are
part of the item; blank lines after it are not."
  (save-excursion
    (let ((start (progn (goto-char (treesit-node-start item))
                        (line-beginning-position))))
      (goto-char (treesit-node-end item))
      ;; The node ends after the indentation of the line that follows it.
      (unless (or (bolp) (eobp))
        (beginning-of-line))
      (when (bolp)
        (while (and (> (point) start)
                    (save-excursion (forward-line -1)
                                    (looking-at-p "[ \t]*$")))
          (forward-line -1)))
      (cons start (point)))))

(defun markdown-modern--list-item-sibling (item direction)
  "Return the list item next to ITEM in its list, or nil.
DIRECTION is -1 for the previous item and 1 for the next one."
  (let ((sibling (if (< direction 0)
                     (treesit-node-prev-sibling item t)
                   (treesit-node-next-sibling item t))))
    (and sibling (equal (treesit-node-type sibling) "list_item") sibling)))

(defun markdown-modern--list-item-marker-start (item)
  "Return the position of the bullet or number of list ITEM.
The marker node can include the indentation before it."
  (save-excursion
    (goto-char (treesit-node-start (treesit-node-child item 0)))
    (skip-chars-forward " \t")
    (point)))

(defun markdown-modern--list-item-column (item)
  "Return the column where list ITEM's marker starts."
  (save-excursion
    (goto-char (markdown-modern--list-item-marker-start item))
    (current-column)))

(defun markdown-modern--list-item-marker (item)
  "Return the marker of list ITEM as it would start a new sibling item.
This is the text before the marker on its line (indentation, or a quote
prefix), the marker with the next number for an ordered list, the space
after it, and an empty checkbox for a task item."
  (let* ((marker (treesit-node-child item 0))
         (start (markdown-modern--list-item-marker-start item))
         ;; The text before the marker: indentation and quote markers, or
         ;; the marker of a parent item on the same line, as in "- - a",
         ;; which becomes indentation.
         (prefix (replace-regexp-in-string
                  "[^> \t]" " "
                  (save-excursion (goto-char start)
                                  (buffer-substring-no-properties
                                   (line-beginning-position) start))))
         (text (buffer-substring-no-properties
                start (save-excursion (goto-char (treesit-node-end marker))
                                      (min (point) (line-end-position)))))
         (task (cl-some (lambda (child)
                          (string-prefix-p "task_list_marker"
                                           (treesit-node-type child)))
                        (treesit-node-children item))))
    (when (string-match "\\`\\([0-9]+\\)\\([.)]\\)" text)
      (setq text (concat (number-to-string
                          (1+ (string-to-number (match-string 1 text))))
                         (substring text (match-end 1)))))
    (unless (string-match-p "[ \t]\\'" text)
      (setq text (concat text " ")))
    (concat prefix text (if task "[ ] " ""))))

;;;###autoload
(defun markdown-modern-insert-list-item ()
  "Insert a new list item after the item at point.
The new item goes after the whole item, nested items included, and continues
its list: the same bullet, the next number, an empty checkbox after a task.
Outside a list, start an unordered list."
  (interactive)
  (if-let* ((item (markdown-modern--list-item-node)))
      (let* ((region (markdown-modern--list-item-region item))
             (end (cdr region))
             (marker (markdown-modern--list-item-marker item))
             ;; In a loose list a blank line separates the items.
             (loose (and (markdown-modern--list-item-sibling item 1)
                         (save-excursion
                           (goto-char end)
                           (and (not (eobp)) (looking-at-p "[ \t]*$"))))))
        (goto-char end)
        (cond
         (loose (insert "\n" marker)
                (save-excursion (insert "\n")))
         ((and (eobp) (not (bolp)))
          (insert "\n" marker))
         (t (insert marker)
            (save-excursion (insert "\n")))))
    (if (save-excursion (beginning-of-line) (looking-at-p "[ \t]*$"))
        (progn (delete-region (line-beginning-position) (line-end-position))
               (insert "- "))
      (end-of-line)
      (insert "\n- "))))

;;;###autoload
(defun markdown-modern-toggle-checkbox ()
  "Toggle task list checkbox at point."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (cond
     ((looking-at "^\\([ \t]*[-*+][ \t]+\\)\\[ \\]")
      (replace-match "\\1[x]"))
     ((looking-at "^\\([ \t]*[-*+][ \t]+\\)\\[[xX]\\]")
      (replace-match "\\1[ ]"))
     (t
      (message "No checkbox on current line")))))

(defun markdown-modern--checkbox-overlay-at-point ()
  "Return the rendered task-checkbox overlay under point, or nil.
Matches when point is anywhere on the checkbox glyph, from just before the
opening bracket through just after the closing bracket."
  (cl-flet ((cb (p)
              (and (>= p (point-min)) (<= p (point-max))
                   (cl-find-if
                    (lambda (ov)
                      (eq (overlay-get ov 'markdown-modern-type) 'checkbox))
                    (overlays-at p)))))
    (or (cb (point)) (cb (1- (point))))))

;;;###autoload
(defun markdown-modern-space-or-toggle-checkbox (n)
  "Toggle the task checkbox under point, or insert a space.
When point is on a rendered task-list checkbox, toggle it between checked and
unchecked and insert nothing.  Otherwise insert N spaces, like
`self-insert-command'.

A rendered checkbox is a widget: the only things you do to it are toggle it or
remove it (see `markdown-modern-checkbox-delete-backward'), so its markup is
never revealed at point."
  (interactive "p")
  (if (markdown-modern--checkbox-overlay-at-point)
      (markdown-modern-toggle-checkbox)
    (self-insert-command n)))

;;;###autoload
(defun markdown-modern-remove-checkbox ()
  "Remove the task checkbox on the current line, leaving a plain list item.
`- [ ] text' becomes `- text', in a single undoable step.  With no checkbox on
the line, do nothing."
  (interactive)
  (save-excursion
    (beginning-of-line)
    (if (looking-at "\\([ \t]*[-*+][ \t]+\\)\\[[ xX]\\][ \t]*")
        (replace-match "\\1")
      (message "No checkbox on current line"))))

;;;###autoload
(defun markdown-modern-checkbox-delete-backward (n)
  "Remove the task checkbox under point, or delete backward.
When point is on a rendered checkbox, remove the whole checkbox at once, leaving
a plain list item (see `markdown-modern-remove-checkbox').  Otherwise delete N
characters backward."
  (interactive "p")
  (if (markdown-modern--checkbox-overlay-at-point)
      (markdown-modern-remove-checkbox)
    (delete-char (- n))))

;;;###autoload
(defun markdown-modern-checkbox-delete-forward (n)
  "Remove the task checkbox under point, or delete forward.
When point is on a rendered checkbox, remove the whole checkbox at once, leaving
a plain list item (see `markdown-modern-remove-checkbox').  Otherwise delete N
characters forward."
  (interactive "p")
  (if (markdown-modern--checkbox-overlay-at-point)
      (markdown-modern-remove-checkbox)
    (delete-char n)))

;; Honour `delete-selection-mode' the way the commands these stand in for do.
(put 'markdown-modern-space-or-toggle-checkbox 'delete-selection t)
(put 'markdown-modern-checkbox-delete-backward 'delete-selection 'supersede)
(put 'markdown-modern-checkbox-delete-forward 'delete-selection 'supersede)

;;;###autoload
(defun markdown-modern-move-item-up ()
  "Move the list item at point above the item before it.
Nested items move with it."
  (interactive)
  (let* ((item (or (markdown-modern--list-item-node)
                   (user-error "Not in a list item")))
         (prev (or (markdown-modern--list-item-sibling item -1)
                   (user-error "No item above this one"))))
    (markdown-modern--swap-list-items prev item t)))

;;;###autoload
(defun markdown-modern-move-item-down ()
  "Move the list item at point below the item after it.
Nested items move with it."
  (interactive)
  (let* ((item (or (markdown-modern--list-item-node)
                   (user-error "Not in a list item")))
         (next (or (markdown-modern--list-item-sibling item 1)
                   (user-error "No item below this one"))))
    (markdown-modern--swap-list-items item next nil)))

(defun markdown-modern--swap-list-items (first second point-in-second)
  "Swap list items FIRST and SECOND, which follow each other in one list.
Blank lines between them stay where they are.  Point stays in the moved
item: in SECOND when POINT-IN-SECOND is non-nil, else in FIRST."
  (let* ((a (markdown-modern--list-item-region first))
         (b (markdown-modern--list-item-region second))
         (offset (- (point) (car (if point-in-second b a))))
         (text-a (buffer-substring-no-properties (car a) (cdr a)))
         (gap (buffer-substring-no-properties (cdr a) (car b)))
         (text-b (buffer-substring-no-properties (car b) (cdr b))))
    ;; The last item of the buffer can lack a final newline.
    (unless (string-suffix-p "\n" text-b)
      (setq text-b (concat text-b "\n")
            text-a (string-remove-suffix "\n" text-a)))
    ;; Point on a blank line after the item stays with the item.
    (setq offset (max 0 (min offset (1- (length (if point-in-second
                                                     text-b
                                                   text-a))))))
    (goto-char (car a))
    (delete-region (car a) (cdr b))
    (insert text-b gap text-a)
    (goto-char (+ (car a) offset
                  (if point-in-second 0 (+ (length text-b) (length gap)))))))

(defun markdown-modern--list-item-quote-depth (item)
  "Return how many block quotes contain list ITEM."
  (let ((depth 0)
        (node (treesit-node-parent item)))
    (while node
      (when (equal (treesit-node-type node) "block_quote")
        (setq depth (1+ depth)))
      (setq node (treesit-node-parent node)))
    depth))

(defun markdown-modern--skip-quote-prefix (depth)
  "Move point past up to DEPTH quote markers at the start of this line.
Each marker is `>' with the spaces before it and one space after it.  A
lazy continuation line can have fewer markers."
  (dotimes (_ depth)
    (when (looking-at "[ \t]*>[ \t]?")
      (goto-char (match-end 0)))))

(defun markdown-modern--shift-list-item (item columns)
  "Indent the lines of list ITEM by COLUMNS, or outdent when negative.
The indentation goes after the quote markers of a list inside a quote.
Outdenting removes at most the spaces a line has."
  (let ((region (markdown-modern--list-item-region item))
        (depth (markdown-modern--list-item-quote-depth item)))
    (save-excursion
      (goto-char (car region))
      (let ((end (copy-marker (cdr region))))
        (while (< (point) end)
          (markdown-modern--skip-quote-prefix depth)
          (unless (looking-at-p "[ \t]*$")
            (if (> columns 0)
                (insert (make-string columns ?\s))
              (delete-region (point)
                             (save-excursion
                               (skip-chars-forward " " (+ (point) (- columns)))
                               (point)))))
          (forward-line 1))
        (set-marker end nil)))))

;;;###autoload
(defun markdown-modern-promote-item ()
  "Move the list item at point out one level.
Nested items and continuation lines move with it.  A top-level item that is
indented moves to the left edge, or in a quote to the edge of the quote."
  (interactive)
  (let* ((item (or (markdown-modern--list-item-node)
                   (user-error "Not in a list item")))
         ;; The parent item, unless a quote comes first: the item cannot
         ;; leave the quote.
         (container (treesit-parent-until
                     (treesit-node-parent item)
                     (lambda (n) (member (treesit-node-type n)
                                         '("list_item" "block_quote")))))
         (parent (and container
                      (equal (treesit-node-type container) "list_item")
                      container))
         (column (markdown-modern--list-item-column item))
         (target (if parent
                     (markdown-modern--list-item-column parent)
                   (save-excursion
                     (goto-char (markdown-modern--list-item-marker-start item))
                     (beginning-of-line)
                     (markdown-modern--skip-quote-prefix
                      (markdown-modern--list-item-quote-depth item))
                     (current-column)))))
    (when (<= column target)
      (user-error "Already at the top level"))
    (markdown-modern--shift-list-item item (- target column))))

;;;###autoload
(defun markdown-modern-demote-item ()
  "Nest the list item at point under the item before it.
Nested items and continuation lines move with it."
  (interactive)
  (let* ((item (or (markdown-modern--list-item-node)
                   (user-error "Not in a list item")))
         (prev (or (markdown-modern--list-item-sibling item -1)
                   (user-error "No item above to nest this one under")))
         ;; Line up with the text of the item above, as CommonMark wants.
         (target (save-excursion
                   (goto-char (treesit-node-end (treesit-node-child prev 0)))
                   (current-column))))
    (markdown-modern--shift-list-item
     item (- target (markdown-modern--list-item-column item)))))

;;; Table Commands

;;;###autoload
(defun markdown-modern-insert-table (&optional rows cols)
  "Insert a markdown table with ROWS rows and COLS columns."
  (interactive
   (list (read-number "Rows: " 3)
         (read-number "Columns: " 3)))
  (markdown-modern--ensure-blank-line-before)
  (let ((col-width 10))
    ;; Header row
    (insert "|")
    (dotimes (c cols)
      (let ((header (format "Header %d" (1+ c))))
        (insert (format " %-10s |" header))))
    (insert "\n")
    ;; Separator
    (insert "|")
    (dotimes (_ cols)
      (insert (make-string (+ col-width 2) ?-) "|"))
    (insert "\n")
    ;; Data rows
    (dotimes (_r rows)
      (insert "|")
      (dotimes (_c cols)
        (insert (format " %-10s |" "")))
      (insert "\n")))
  ;; Position cursor in first data cell
  (forward-line (- (1+ rows)))
  (search-forward "|" nil t)
  (forward-char 1))

;;;###autoload
(defun markdown-modern-table-sort (&optional _column)
  "Sort table by _COLUMN (0-indexed)."
  (interactive
   (list (markdown-modern-table-column-at-point)))
  (when-let* ((bounds (markdown-modern-table-bounds)))
    (let ((start (car bounds))
          (end (cdr bounds)))
      (save-excursion
        (goto-char start)
        ;; Skip header and separator
        (forward-line 2)
        (let ((data-start (point)))
          (goto-char end)
          (sort-lines nil data-start (point)))))))

;;; Tab Commands (Context-Sensitive)

;;;###autoload
(defun markdown-modern-tab ()
  "Context-sensitive TAB command.
In tables: move to next cell.
In lists: increase indentation.
Elsewhere: normal tab behavior or cycle visibility."
  (interactive)
  (cond
   ((markdown-modern-in-table-p)
    (markdown-modern-table-next-cell))
   ((markdown-modern-in-list-p)
    (markdown-modern-demote-item))
   ((markdown-modern-in-heading-p)
    (markdown-modern-cycle-visibility))
   (t
    (indent-for-tab-command))))

;;;###autoload
(defun markdown-modern-backtab ()
  "Context-sensitive Shift-TAB command.
In tables: move to previous cell.
In lists: decrease indentation.
Elsewhere: cycle global visibility."
  (interactive)
  (cond
   ((markdown-modern-in-table-p)
    (markdown-modern-table-prev-cell))
   ((markdown-modern-in-list-p)
    (markdown-modern-promote-item))
   (t
    (markdown-modern-cycle-global-visibility))))

(defun markdown-modern--table-pipes ()
  "Return the positions of the unescaped `|' characters on the current line."
  (let ((bol (line-beginning-position)))
    (mapcar (lambda (i) (+ bol i))
            (markdown-modern-render--unescaped-pipes
             (buffer-substring-no-properties bol (line-end-position))))))

(defun markdown-modern--table-enter-cell (pipe next-pipe)
  "Move into the cell between PIPE and NEXT-PIPE.
Point goes to the start of the cell's text.  In a blank cell it goes after
the first space, so typed text is padded like the other cells."
  (let ((end (or next-pipe (line-end-position))))
    (goto-char (1+ pipe))
    (skip-chars-forward " \t" end)
    (when (and (= (point) end) (< (1+ pipe) end))
      (goto-char (+ pipe 2)))))

(defun markdown-modern--table-first-cell ()
  "Move into the first cell of the current row."
  (let ((pipes (markdown-modern--table-pipes)))
    (markdown-modern--table-enter-cell (car pipes) (cadr pipes))))

(defun markdown-modern--table-next-row (columns)
  "Move into the first cell of the next table row.
Skip the separator row.  After the last row, add an empty row with COLUMNS
cells."
  (let ((last-line-end (line-end-position)))
    (forward-line 1)
    (when (and (> (line-end-position) last-line-end)
               (markdown-modern--table-separator-line-p))
      (setq last-line-end (line-end-position))
      (forward-line 1))
    (unless (and (> (line-end-position) last-line-end)
                 (markdown-modern--table-row-line-p))
      (goto-char last-line-end)
      (insert "\n|" (apply #'concat (make-list columns "  |"))))
    (markdown-modern--table-first-cell)))

;;;###autoload
(defun markdown-modern-table-next-cell ()
  "Move to the next table cell.
In the last cell of the last row, add an empty row and move into it."
  (interactive)
  (when (markdown-modern-in-table-p)
    (let* ((pipes (markdown-modern--table-pipes))
           ;; The next cell opens at the first pipe after point.
           (next (cl-count-if (lambda (pipe) (< pipe (point))) pipes)))
      (if (< (1+ next) (length pipes))
          (markdown-modern--table-enter-cell (nth next pipes) (nth (1+ next) pipes))
        (markdown-modern--table-next-row (max 1 (1- (length pipes))))))))

;;;###autoload
(defun markdown-modern-table-prev-cell ()
  "Move to the previous table cell."
  (interactive)
  (when (markdown-modern-in-table-p)
    (let* ((pipes (markdown-modern--table-pipes))
           ;; The current cell opens at pipe CURRENT.
           (current (1- (cl-count-if (lambda (pipe) (< pipe (point))) pipes))))
      (if (>= current 1)
          (markdown-modern--table-enter-cell (nth (1- current) pipes)
                                             (nth current pipes))
        (let ((row-start (line-beginning-position))
              (target nil))
          (save-excursion
            (forward-line -1)
            (when (and (< (point) row-start)
                       (markdown-modern--table-separator-line-p))
              (forward-line -1))
            (when (and (< (point) row-start)
                       (markdown-modern--table-row-line-p))
              (let ((row-pipes (markdown-modern--table-pipes)))
                (when (cdr row-pipes)
                  (markdown-modern--table-enter-cell
                   (car (last row-pipes 2)) (car (last row-pipes)))
                  (setq target (point))))))
          (when target
            (goto-char target)))))))

;;; Visibility Commands

;;;###autoload
(defun markdown-modern-cycle-visibility ()
  "Cycle the heading at point: folded, its subheadings, everything."
  (interactive)
  (outline-cycle))

;;;###autoload
(defun markdown-modern-cycle-global-visibility ()
  "Cycle the whole buffer: top headings, all headings, everything."
  (interactive)
  (outline-cycle-buffer))

;;; Element Reveal Command

;;;###autoload
(defun markdown-modern-toggle-element-at-point ()
  "Toggle rendering of element at point."
  (interactive)
  (if-let* ((elem (markdown-modern-ts--element-at (point))))
      (let* ((start (markdown-modern-node-start elem))
             (end (markdown-modern-node-end elem))
             (has-overlay (cl-some
                          (lambda (ov)
                            (overlay-get ov 'markdown-modern))
                          (overlays-in start end))))
        (if has-overlay
            (markdown-modern-render--unrender-region start end)
          (markdown-modern-render--render-region start end)))
    (message "No markdown element at point")))

;;;###autoload
(defun markdown-modern-follow-link-at-point ()
  "Follow the link at point.
Works both on rendered lines (via overlay properties) and on
revealed lines (by parsing raw markdown syntax at point)."
  (interactive)
  ;; First try overlay property (rendered line)
  (let ((url (get-char-property (point) 'markdown-modern-url)))
    (unless url
      ;; Fallback: parse raw markdown on the current line
      (save-excursion
        (let ((pos (point))
              (bol (line-beginning-position))
              (eol (line-end-position)))
          ;; Check for inline link: [text](url)
          (goto-char bol)
          (while (and (not url)
                      (re-search-forward "\\[\\([^]]*\\)\\](\\([^)]+\\))" eol t))
            (when (and (>= pos (match-beginning 0))
                       (<= pos (match-end 0)))
              (setq url (match-string-no-properties 2))))
          ;; Check for reference link: [text][label], [text][] or [label]
          (goto-char bol)
          (while (and (not url)
                      (re-search-forward
                       "\\[\\([^]]+\\)\\]\\(?:\\[\\([^]]*\\)\\]\\)?" eol t))
            (when (and (>= pos (match-beginning 0))
                       (<= pos (match-end 0)))
              (setq url (markdown-modern-render--link-definition
                         (if (member (match-string-no-properties 2) '(nil ""))
                             (match-string-no-properties 1)
                           (match-string-no-properties 2))))))
          ;; Check for autolink: <url>
          (unless url
            (goto-char bol)
            (while (and (not url)
                        (re-search-forward "<\\([a-zA-Z]+://[^>]+\\)>" eol t))
              (when (and (>= pos (match-beginning 0))
                         (<= pos (match-end 0)))
                (setq url (match-string-no-properties 1)))))
          ;; Check for bare URL at point
          (unless url
            (goto-char bol)
            (while (and (not url)
                        (re-search-forward "https?://[^ \t\n\r>)\"']+" eol t))
              (when (and (>= pos (match-beginning 0))
                         (<= pos (match-end 0)))
                (setq url (match-string-no-properties 0))))))))
    (if url
        (markdown-modern-render--follow-link url)
      (message "No link at point"))))

;;; Code Block Edit Mode
;;
;; Like `org-edit-special', `C-c '' copies the code of a block into a buffer
;; of its own, in the language's major mode, and writes it back on `C-c ''.
;; A copy keeps the language's indentation, syntax and jit-lock away from
;; the Markdown around the block.  The text in front of the code on each
;; line, the indentation of a list item or the `>' of a quote, is taken off
;; for editing and put back when writing.

(defvar-local markdown-modern-code-edit--source-buffer nil
  "The Markdown buffer this code edit buffer writes back to.")

(defvar-local markdown-modern-code-edit--content-bounds nil
  "Markers in the source buffer around the code of the block.")

(defvar-local markdown-modern-code-edit--original-content nil
  "The code as it was copied, without line prefixes or final newline.")

(defvar-local markdown-modern-code-edit--line-prefix nil
  "The text in front of the code on each line of the block.")

(defvar-local markdown-modern-code-edit--final-newline nil
  "Non-nil if the code ends with a newline in the source, before a fence.")

(defvar markdown-modern-code-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c '") #'markdown-modern-code-edit-finish)
    (define-key map (kbd "C-c C-k") #'markdown-modern-code-edit-abort)
    map)
  "Keymap for `markdown-modern-code-edit-mode'.")

(define-minor-mode markdown-modern-code-edit-mode
  "Minor mode for editing a copy of a Markdown code block."
  :lighter " MdM-Edit"
  :keymap markdown-modern-code-edit-mode-map)

(defun markdown-modern-code-edit--strip-prefix (line prefix)
  "Return LINE without as much of PREFIX as it starts with."
  (let ((i 0)
        (n (min (length line) (length prefix))))
    (while (and (< i n) (eq (aref line i) (aref prefix i)))
      (setq i (1+ i)))
    (substring line i)))

(defun markdown-modern-code-edit--add-prefix (code prefix)
  "Return CODE with PREFIX in front of each line.
An empty line gets PREFIX without its trailing spaces, so a line in a
quote keeps its `>' and a line in a list item stays empty."
  (mapconcat (lambda (line)
               (if (string-empty-p line)
                   (string-trim-right prefix)
                 (concat prefix line)))
             (split-string code "\n")
             "\n"))

;;;###autoload
(defun markdown-modern-edit-code-block ()
  "Edit the code block at point in a buffer of its own.
The buffer is in the language's major mode.  \\<markdown-modern-code-edit-mode-map>\\[markdown-modern-code-edit-finish] writes the code back,
\\[markdown-modern-code-edit-abort] leaves the block as it was."
  (interactive)
  (when (and markdown-modern--code-edit-buffer
             (buffer-live-p markdown-modern--code-edit-buffer))
    (user-error "Already editing a code block; finish or abort first"))
  (let ((info (markdown-modern--fenced-code-block-content-at (point))))
    (unless info
      (user-error "Not inside a fenced code block"))
    (let* ((source-buf (current-buffer))
           (block-start (plist-get info :block-start))
           ;; In a list item or quote the parse tree's content starts after
           ;; the first line's prefix and ends before the closing fence's.
           ;; Take whole lines.
           (content-start (save-excursion
                            (goto-char (plist-get info :content-start))
                            (line-beginning-position)))
           (content-end (save-excursion
                          (goto-char (plist-get info :content-end))
                          (skip-chars-backward " \t>" (line-beginning-position))
                          (if (bolp) (point) (plist-get info :content-end))))
           (language (plist-get info :language))
           ;; The opening fence shows what comes in front of the code: the
           ;; indentation of a list item and the markers of a quote.  A list
           ;; marker on the fence's line counts as indentation.
           (prefix (save-excursion
                     (goto-char block-start)
                     (re-search-forward "[`~]" (line-end-position) 'move)
                     (replace-regexp-in-string
                      "[^> \t]" " "
                      (buffer-substring-no-properties
                       (line-beginning-position)
                       (max (line-beginning-position) (1- (point)))))))
           (source-text (buffer-substring-no-properties content-start content-end))
           (final-newline (or (string-suffix-p "\n" source-text)
                              ;; An empty block before its closing fence.
                              (and (string-empty-p source-text)
                                   (save-excursion
                                     (goto-char content-start)
                                     (not (eobp))))))
           (lines (split-string (string-remove-suffix "\n" source-text) "\n"))
           (code (mapconcat (lambda (line)
                              (markdown-modern-code-edit--strip-prefix line prefix))
                            lines "\n"))
           ;; Point's line and column in the code.
           (line (if (< (point) content-start) 0
                   (count-lines content-start (line-beginning-position))))
           (column (max 0 (- (current-column) (length prefix))))
           (edit-buf (generate-new-buffer
                      (format "*MdM-Edit:%s*" (or language "code")))))
      (setq markdown-modern--code-edit-buffer edit-buf)
      (with-current-buffer edit-buf
        (insert code)
        (goto-char (point-min))
        (forward-line line)
        (move-to-column column)
        (when language
          (when-let* ((mode (markdown-modern-render--language-to-mode language)))
            (funcall mode)))
        (setq markdown-modern-code-edit--source-buffer source-buf
              markdown-modern-code-edit--content-bounds
              (cons (with-current-buffer source-buf (copy-marker content-start))
                    (with-current-buffer source-buf (copy-marker content-end)))
              markdown-modern-code-edit--original-content code
              markdown-modern-code-edit--line-prefix prefix
              markdown-modern-code-edit--final-newline final-newline)
        (set-buffer-modified-p nil)
        (markdown-modern-code-edit-mode 1)
        (setq header-line-format
              (substitute-command-keys
               "Editing code block.  \\<markdown-modern-code-edit-mode-map>\\[markdown-modern-code-edit-finish] to finish, \\[markdown-modern-code-edit-abort] to abort"))
        (add-hook 'kill-buffer-hook #'markdown-modern-code-edit--on-kill nil t))
      (pop-to-buffer edit-buf))))

(defun markdown-modern-code-edit--leave (source-pos)
  "Close this code edit buffer and go back to its source buffer.
Give back the window the editor took.  Put point at SOURCE-POS in the
source, when non-nil."
  (let ((source-buf markdown-modern-code-edit--source-buffer)
        (bounds markdown-modern-code-edit--content-bounds)
        (window (get-buffer-window (current-buffer))))
    (remove-hook 'kill-buffer-hook #'markdown-modern-code-edit--on-kill t)
    (if (window-live-p window)
        (quit-window t window)
      (kill-buffer (current-buffer)))
    (when (buffer-live-p source-buf)
      (if-let* ((source-window (get-buffer-window source-buf)))
          (select-window source-window)
        (switch-to-buffer source-buf))
      (when source-pos
        (goto-char source-pos))
      (setq markdown-modern--code-edit-buffer nil))
    (set-marker (car bounds) nil)
    (set-marker (cdr bounds) nil)))

;;;###autoload
(defun markdown-modern-code-edit-finish ()
  "Write the code back to its block and return to the source buffer.
The block changes only if the code did."
  (interactive)
  (unless markdown-modern-code-edit--source-buffer
    (user-error "Not in a code edit buffer"))
  (let* ((code (buffer-substring-no-properties (point-min) (point-max)))
         (prefix markdown-modern-code-edit--line-prefix)
         (bounds markdown-modern-code-edit--content-bounds)
         (line (1- (line-number-at-pos)))
         (column (current-column))
         (source-pos nil))
    (when (buffer-live-p markdown-modern-code-edit--source-buffer)
      (unless (equal code markdown-modern-code-edit--original-content)
        (let ((text (if (string-empty-p code) ""
                      (concat (markdown-modern-code-edit--add-prefix code prefix)
                              (if markdown-modern-code-edit--final-newline "\n" "")))))
          (with-current-buffer markdown-modern-code-edit--source-buffer
            (save-excursion
              (goto-char (car bounds))
              (delete-region (car bounds) (cdr bounds))
              (insert text)))))
      ;; Point goes to the same place in the code in the source.
      (with-current-buffer markdown-modern-code-edit--source-buffer
        (save-excursion
          (goto-char (car bounds))
          (forward-line line)
          (when (< (point) (cdr bounds))
            (move-to-column (+ (length prefix) column)))
          (setq source-pos (min (point) (max (car bounds) (cdr bounds)))))))
    (markdown-modern-code-edit--leave source-pos)))

;;;###autoload
(defun markdown-modern-code-edit-abort ()
  "Leave the code block as it was and return to the source buffer."
  (interactive)
  (unless markdown-modern-code-edit--source-buffer
    (user-error "Not in a code edit buffer"))
  (markdown-modern-code-edit--leave nil))

(defun markdown-modern-code-edit--on-kill ()
  "Forget the code edit buffer in its source when it is killed another way.
As with `markdown-modern-code-edit-abort', the block stays as it was."
  (when (buffer-live-p markdown-modern-code-edit--source-buffer)
    (with-current-buffer markdown-modern-code-edit--source-buffer
      (setq markdown-modern--code-edit-buffer nil))))

(provide 'markdown-modern-commands)
;;; markdown-modern-commands.el ends here
