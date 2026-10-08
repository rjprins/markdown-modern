;;; markdown-modern-commands-test.el --- Command tests for markdown-modern -*- lexical-binding: t; no-byte-compile: t; -*-

;; Copyright (C) 2026 markdown-modern contributors

;;; Commentary:

;; Unit tests for markdown-modern interactive commands.
;; Tests buffer manipulation, cursor positioning, and user-facing functions.

;;; Code:

(require 'ert)
(require 'markdown-modern)
(require 'markdown-modern-commands)
(require 'markdown-modern-elements)
(require 'markdown-modern-render)

;;; Test Helper Macro

(defmacro mg-cmd-test (name doc initial expected &rest body)
  "Define a command test NAME with DOC.
INITIAL is the starting buffer state (| marks cursor).
EXPECTED is the expected final state (| marks expected cursor).
BODY contains the commands to execute."
  (declare (indent 3))
  `(ert-deftest ,(intern (format "cmd/%s" name)) ()
     ,doc
     (with-temp-buffer
       ;; Parse initial state
       (let* ((init-str ,initial)
              (cursor-pos (string-match "|" init-str))
              (content (replace-regexp-in-string "|" "" init-str)))
         (insert content)
         (goto-char (1+ (or cursor-pos 0))))
       (markdown-modern-ts--init)
       ;; Execute body
       ,@body
       ;; Check expected state
       (let* ((exp-str ,expected)
              (exp-cursor (string-match "|" exp-str))
              (exp-content (replace-regexp-in-string "|" "" exp-str)))
         (should (equal (buffer-string) exp-content))
         (when exp-cursor
           (should (= (point) (1+ exp-cursor))))))))

(defmacro mg-cmd-test-region (name doc initial expected &rest body)
  "Like `mg-cmd-test' but with region support.
Use [ and ] to mark region boundaries in INITIAL."
  (declare (indent 3))
  `(ert-deftest ,(intern (format "cmd/%s" name)) ()
     ,doc
     (with-temp-buffer
       ;; Parse initial state with region markers
       (let* ((init-str ,initial)
              (region-start (string-match "\\[" init-str))
              (region-end (1- (string-match "\\]" init-str)))  ; Adjust for [ removal
              (content (replace-regexp-in-string "\\[\\|\\]" "" init-str)))
         (insert content)
         (when (and region-start region-end)
           (set-mark (1+ region-start))
           (goto-char (1+ region-end))
           (activate-mark)))
       (markdown-modern-ts--init)
       ;; Execute body
       ,@body
       ;; Check expected state
       (let* ((exp-str ,expected)
              (exp-content (replace-regexp-in-string "|\\|\\[\\|\\]" "" exp-str)))
         (should (equal (buffer-string) exp-content))))))

;;; Style Insertion Tests - No Region

(mg-cmd-test bold-insert-empty
  "Bold inserts ** pair at point"
  "|" "**|**"
  (markdown-modern-insert-bold))

(mg-cmd-test italic-insert-empty
  "Italic inserts * pair at point"
  "|" "*|*"
  (markdown-modern-insert-italic))

(mg-cmd-test code-insert-empty
  "Code inserts ` pair at point"
  "|" "`|`"
  (markdown-modern-insert-code))

(mg-cmd-test strike-insert-empty
  "Strike inserts ~~ pair at point"
  "|" "~~|~~"
  (markdown-modern-insert-strike))

(mg-cmd-test kbd-insert-empty
  "Kbd inserts <kbd> pair at point"
  "|" "<kbd>|</kbd>"
  (markdown-modern-insert-kbd))

;;; Style Insertion Tests - With Region

(mg-cmd-test-region bold-wrap-region
  "Bold wraps selected text"
  "[hello]" "**hello**"
  (markdown-modern-insert-bold))

(mg-cmd-test-region italic-wrap-region
  "Italic wraps selected text"
  "[world]" "*world*"
  (markdown-modern-insert-italic))

(mg-cmd-test-region code-wrap-region
  "Code wraps selected text"
  "[foo]" "`foo`"
  (markdown-modern-insert-code))

(mg-cmd-test-region strike-wrap-region
  "Strike wraps selected text"
  "[bar]" "~~bar~~"
  (markdown-modern-insert-strike))

;;; Heading Tests

(mg-cmd-test heading-level-1
  "Insert level 1 heading"
  "|" "# |"
  (markdown-modern-insert-heading-1))

(mg-cmd-test heading-level-2
  "Insert level 2 heading"
  "|" "## |"
  (markdown-modern-insert-heading-2))

(mg-cmd-test heading-level-3
  "Insert level 3 heading"
  "|" "### |"
  (markdown-modern-insert-heading-3))

(mg-cmd-test heading-level-6
  "Insert level 6 heading"
  "|" "###### |"
  (markdown-modern-insert-heading-6))

(mg-cmd-test heading-at-existing-text
  "Heading at line start prepends markers"
  "|text" "## |text"
  (markdown-modern-insert-heading 2))

(mg-cmd-test heading-promote
  "Promote heading decreases level"
  "|## Title" "|# Title"
  (markdown-modern-promote-heading))

(mg-cmd-test heading-demote
  "Demote heading increases level"
  "|# Title" "|## Title"
  (markdown-modern-demote-heading))

(mg-cmd-test heading-promote-at-h1
  "Promote at H1 does nothing"
  "|# Title" "|# Title"
  (markdown-modern-promote-heading))

;;; List Tests

(mg-cmd-test list-item-new
  "New list item at empty buffer"
  "|" "- |"
  (markdown-modern-insert-list-item))

(mg-cmd-test list-item-continue
  "Continue existing list"
  "- item|" "- item\n- |"
  (markdown-modern-insert-list-item))

(mg-cmd-test list-item-ordered-continue
  "Continue ordered list increments number"
  "1. first|" "1. first\n2. |"
  (markdown-modern-insert-list-item))

(mg-cmd-test checkbox-toggle-unchecked
  "Toggle unchecked checkbox to checked"
  "|- [ ] task" "|- [x] task"
  (markdown-modern-toggle-checkbox))

(mg-cmd-test checkbox-toggle-checked
  "Toggle checked checkbox to unchecked"
  "|- [x] task" "|- [ ] task"
  (markdown-modern-toggle-checkbox))

(mg-cmd-test checkbox-toggle-uppercase
  "Toggle uppercase X checkbox"
  "|- [X] task" "|- [ ] task"
  (markdown-modern-toggle-checkbox))

(mg-cmd-test checkbox-remove-unchecked
  "Remove an unchecked checkbox, leaving a plain list item"
  "- [ ] |task" "- task"
  (markdown-modern-remove-checkbox))

(mg-cmd-test checkbox-remove-checked
  "Remove a checked checkbox, leaving a plain list item"
  "- [x] |task" "- task"
  (markdown-modern-remove-checkbox))

(mg-cmd-test checkbox-remove-indented
  "Remove a nested checkbox, preserving indentation"
  "  - [ ] |task" "  - task"
  (markdown-modern-remove-checkbox))

(mg-cmd-test list-promote
  "Promote list item decreases indent"
  "|  - item" "|- item"
  (markdown-modern-promote-item))

(mg-cmd-test list-demote
  "Demote list item increases indent"
  "|- item" "|  - item"
  (markdown-modern-demote-item))

;;; Blockquote Tests

(mg-cmd-test blockquote-new-line
  "Blockquote at empty line"
  "|" "> |"
  (markdown-modern-insert-blockquote))

(mg-cmd-test blockquote-increase-level
  "Blockquote on existing quote adds level"
  "|> text" "|>> text"
  (markdown-modern-insert-blockquote))

;;; Code Block Tests

(ert-deftest cmd/code-block-insert ()
  "Code block inserts fences."
  (with-temp-buffer
    (markdown-modern-insert-code-block "python")
    (should (string-match-p "```python" (buffer-string)))
    (should (string-match-p "```$" (buffer-string)))))

(ert-deftest cmd/code-block-empty-language ()
  "Code block without language."
  (with-temp-buffer
    (markdown-modern-insert-code-block "")
    (should (string-match-p "^```\n" (buffer-string)))))

;;; Link and Image Tests

(ert-deftest cmd/link-insert ()
  "Link insertion creates proper markdown."
  (with-temp-buffer
    (markdown-modern-insert-link "http://example.com" "Example")
    (should (equal (buffer-string) "[Example](http://example.com)"))))

(ert-deftest cmd/link-insert-empty-url ()
  "Link with empty URL positions cursor."
  (with-temp-buffer
    (markdown-modern-insert-link "" "text")
    (should (equal (buffer-string) "[text]()"))))

(ert-deftest cmd/image-insert ()
  "Image insertion creates proper markdown."
  (with-temp-buffer
    (markdown-modern-insert-image "photo.jpg" "My Photo")
    (should (equal (buffer-string) "![My Photo](photo.jpg)"))))

;;; Table Tests

(ert-deftest cmd/table-insert ()
  "Table creation with specified dimensions."
  (with-temp-buffer
    (markdown-modern-insert-table 2 3)
    (let ((content (buffer-string)))
      (should (string-match-p "| Header 1" content))
      (should (string-match-p "| Header 2" content))
      (should (string-match-p "| Header 3" content))
      (should (string-match-p "|---" content)))))

(defun markdown-modern-commands-test--table (text command &optional times)
  "Run COMMAND TIMES times on TEXT, where @ marks point.
Return the buffer text with @ at the new point."
  (with-temp-buffer
    (insert (replace-regexp-in-string "@" "" text))
    (goto-char (1+ (string-match "@" text)))
    (markdown-modern-ts--init)
    (dotimes (_ (or times 1))
      (funcall command))
    (insert "@")
    (buffer-string)))

(ert-deftest cmd/table-next-cell-visits-empty-cell ()
  "TAB stops in an empty cell instead of skipping to the next row."
  (should (equal (markdown-modern-commands-test--table
                  "| a@ |   | c |\n|---|---|---|\n"
                  #'markdown-modern-table-next-cell)
                 "| a | @  | c |\n|---|---|---|\n")))

(ert-deftest cmd/table-next-cell-skips-escaped-pipe ()
  "An escaped pipe does not start a new cell."
  (should (equal (markdown-modern-commands-test--table
                  "| a@ \\| b | c |\n|---|---|\n"
                  #'markdown-modern-table-next-cell)
                 "| a \\| b | @c |\n|---|---|\n")))

(ert-deftest cmd/table-next-cell-moves-to-next-row ()
  "TAB in the last cell of a row moves past the separator to the next row."
  (should (equal (markdown-modern-commands-test--table
                  "| a | b@ |\n|---|---|\n| 1 | 2 |\n"
                  #'markdown-modern-table-next-cell)
                 "| a | b |\n|---|---|\n| @1 | 2 |\n")))

(ert-deftest cmd/table-tab-adds-row ()
  "TAB in the last cell of the last row adds an empty row."
  (should (equal (markdown-modern-commands-test--table
                  "| a | b |\n|---|---|\n| 1 | 2@ |\n\nafter\n"
                  #'markdown-modern-tab)
                 "| a | b |\n|---|---|\n| 1 | 2 |\n| @ |  |\n\nafter\n"))
  (should (equal (markdown-modern-commands-test--table
                  "| a | b |\n|---|---|\n| 1 | 2@ |\n"
                  #'markdown-modern-tab 2)
                 "| a | b |\n|---|---|\n| 1 | 2 |\n|  | @ |\n")))

(ert-deftest cmd/table-tab-adds-row-at-buffer-end ()
  "TAB adds a row when the table ends without a final newline."
  (should (equal (markdown-modern-commands-test--table
                  "| a |\n|---|\n| 1@ |"
                  #'markdown-modern-tab)
                 "| a |\n|---|\n| 1 |\n| @ |")))

(ert-deftest cmd/table-tab-adds-row-after-header ()
  "TAB in a table with only a header adds the first body row."
  (should (equal (markdown-modern-commands-test--table
                  "| a | b@ |\n|---|---|\n"
                  #'markdown-modern-tab)
                 "| a | b |\n|---|---|\n| @ |  |\n")))

(ert-deftest cmd/table-prev-cell ()
  "S-TAB moves to the previous cell, across rows and into empty cells."
  (should (equal (markdown-modern-commands-test--table
                  "| a | b |\n|---|---|\n| @1 | 2 |\n"
                  #'markdown-modern-table-prev-cell)
                 "| a | @b |\n|---|---|\n| 1 | 2 |\n"))
  (should (equal (markdown-modern-commands-test--table
                  "| a |   | c@ |\n|---|---|---|\n"
                  #'markdown-modern-table-prev-cell)
                 "| a | @  | c |\n|---|---|---|\n"))
  (should (equal (markdown-modern-commands-test--table
                  "| @a | b |\n|---|---|\n"
                  #'markdown-modern-table-prev-cell)
                 "| @a | b |\n|---|---|\n"))
  ;; The grammar does not parse an all-empty body row; S-TAB still works there.
  (should (equal (markdown-modern-commands-test--table
                  "| a | b |\n|---|---|\n| 1 | 2 |\n| @  |   |\n"
                  #'markdown-modern-backtab)
                 "| a | b |\n|---|---|\n| 1 | @2 |\n|   |   |\n")))

;;; Navigation Tests

(ert-deftest cmd/next-heading ()
  "Navigate to next heading."
  (with-temp-buffer
    (insert "# First\n\ntext\n\n## Second")
    (markdown-modern-mode)
    (goto-char (point-min))
    (markdown-modern-next-heading)
    (should (looking-at "## Second"))))

(ert-deftest cmd/prev-heading ()
  "Navigate to previous heading."
  (with-temp-buffer
    (insert "# First\n\ntext\n\n## Second")
    (markdown-modern-mode)
    (goto-char (point-max))
    (markdown-modern-prev-heading)
    (should (looking-at "## Second"))
    (markdown-modern-prev-heading)
    (should (looking-at "# First"))))

(ert-deftest cmd/next-heading-same-level ()
  "Navigate to next heading at same level."
  (with-temp-buffer
    (insert "## A\n\n### Sub\n\n## B")
    (markdown-modern-mode)
    (goto-char (point-min))
    (markdown-modern-next-heading-same-level)
    (should (looking-at "## B"))))

(ert-deftest cmd/up-heading ()
  "Navigate to parent heading."
  (with-temp-buffer
    (insert "# Parent\n\n## Child\n\n### Grandchild")
    (markdown-modern-mode)
    (goto-char (point-max))
    (beginning-of-line)
    (markdown-modern-up-heading)
    (should (looking-at "## Child"))))

;;; Utility Function Tests

(ert-deftest cmd/wrap-region-or-insert-no-region ()
  "Wrap helper inserts pair when no region."
  (with-temp-buffer
    (markdown-modern--wrap-region-or-insert "<<" ">>")
    (should (equal (buffer-string) "<<>>"))
    (should (= (point) 3))))  ; Cursor between

(ert-deftest cmd/wrap-region-or-insert-with-region ()
  "Wrap helper wraps text when region active."
  (with-temp-buffer
    (insert "text")
    (set-mark (point-min))
    (goto-char (point-max))
    (activate-mark)
    (markdown-modern--wrap-region-or-insert "<<" ">>")
    (should (equal (buffer-string) "<<text>>"))))

(ert-deftest cmd/at-line-start-p ()
  "Line start detection."
  (with-temp-buffer
    (insert "  text")
    (goto-char 1)
    (should (markdown-modern--at-line-start-p))
    (goto-char 3)
    (should (markdown-modern--at-line-start-p))  ; After whitespace
    (goto-char 5)
    (should-not (markdown-modern--at-line-start-p))))  ; After text

(provide 'markdown-modern-commands-test)
;;; markdown-modern-commands-test.el ends here
