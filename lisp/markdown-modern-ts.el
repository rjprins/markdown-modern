;;; markdown-modern-ts.el --- Tree-sitter integration for markdown-modern -*- lexical-binding: t; -*-

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

;; Tree-sitter integration layer for markdown-modern.
;; Provides parsing, AST queries, and element detection.

;;; Code:

(require 'treesit)
(require 'cl-lib)

;;; Data Structures

(cl-defstruct markdown-modern-node
  "Represents a parsed markdown element."
  type        ; Symbol: 'heading, 'emphasis, 'code-block, etc.
  start       ; Buffer position (1-indexed)
  end         ; Buffer position (1-indexed)
  level       ; For headings: 1-6; for lists: nesting depth
  language    ; For code blocks: language identifier
  children    ; List of child markdown-modern-node
  properties  ; Plist of additional properties
  treesit-node) ; The underlying treesit node

;;; Internal Variables

(defvar-local markdown-modern-ts--use-tree-sitter nil
  "Whether tree-sitter is being used for parsing.
Set to t before loading markdown-modern to enable tree-sitter
\(requires markdown grammar to be installed).")

(defvar-local markdown-modern-ts--parser nil
  "Tree-sitter parser for markdown.")

(defvar-local markdown-modern-ts--inline-parser nil
  "Tree-sitter parser for markdown-inline.")

(defvar-local markdown-modern-ts--parse-cache nil
  "Cache of parsed regions.")

;;; Grammar Management

(defconst markdown-modern-ts--grammar-sources
  '((markdown . ("https://github.com/tree-sitter-grammars/tree-sitter-markdown"
                 "split_parser"
                 "tree-sitter-markdown/src"))
    (markdown-inline . ("https://github.com/tree-sitter-grammars/tree-sitter-markdown"
                        "split_parser"
                        "tree-sitter-markdown-inline/src")))
  "Tree-sitter grammar sources for markdown.")

(defun markdown-modern-ts--ensure-grammar ()
  "Ensure markdown tree-sitter grammar is available."
  (when markdown-modern-ts--use-tree-sitter
    (condition-case err
        (unless (treesit-language-available-p 'markdown)
          (if (yes-or-no-p "Markdown tree-sitter grammar not found.  Install it? ")
              (markdown-modern-ts--install-grammar)
            (markdown-modern-ts--enable-fallback-mode)))
      (error
       (message "markdown-modern: Grammar check failed (%s), using fallback" (error-message-string err))
       (markdown-modern-ts--enable-fallback-mode)))))

(defun markdown-modern-ts--install-grammar ()
  "Install markdown tree-sitter grammar."
  (condition-case err
      (let ((treesit-language-source-alist markdown-modern-ts--grammar-sources))
        (message "Installing markdown grammar...")
        (treesit-install-language-grammar 'markdown)
        (message "Installing markdown-inline grammar...")
        (treesit-install-language-grammar 'markdown-inline)
        (message "Grammars installed successfully."))
    (error
     (message "markdown-modern: Grammar installation failed (%s), using fallback" (error-message-string err))
     (markdown-modern-ts--enable-fallback-mode))))

(defun markdown-modern-ts--enable-fallback-mode ()
  "Enable regex-based parsing fallback when tree-sitter unavailable."
  (setq markdown-modern-ts--use-tree-sitter nil)
  (message "markdown-modern: Using fallback regex parser (limited functionality)"))

;;; Parser Initialization

(defun markdown-modern-ts--init ()
  "Initialize tree-sitter parsers for the current buffer."
  (when markdown-modern-ts--use-tree-sitter
    (condition-case err
        (progn
          (when (treesit-language-available-p 'markdown)
            (setq markdown-modern-ts--parser
                  (treesit-parser-create 'markdown)))
          (when (treesit-language-available-p 'markdown-inline)
            (setq markdown-modern-ts--inline-parser
                  (treesit-parser-create 'markdown-inline)))
          (setq markdown-modern-ts--parse-cache (make-hash-table :test 'equal)))
      (error
       (message "markdown-modern: Tree-sitter init failed (%s), using fallback" (error-message-string err))
       (markdown-modern-ts--enable-fallback-mode)))))

;;; Node Type Mapping

(defconst markdown-modern-ts--node-type-map
  '(;; Block elements
    ("atx_heading" . heading)
    ("setext_heading" . heading)
    ("paragraph" . paragraph)
    ("fenced_code_block" . code-block)
    ("indented_code_block" . code-block-indented)
    ("block_quote" . blockquote)
    ("list" . list)
    ("list_item" . list-item)
    ("task_list_marker_checked" . task-checked)
    ("task_list_marker_unchecked" . task-unchecked)
    ("thematic_break" . hr)
    ("html_block" . html-block)
    ("link_reference_definition" . link-ref-def)
    ("pipe_table" . table)
    ("pipe_table_header" . table-header)
    ("pipe_table_delimiter_row" . table-delimiter)
    ("pipe_table_row" . table-row)
    ("pipe_table_cell" . table-cell)
    ;; Inline elements
    ("emphasis" . emphasis)
    ("strong_emphasis" . strong)
    ("strikethrough" . strikethrough)
    ("code_span" . code-span)
    ("inline_link" . link)
    ("full_reference_link" . link-ref)
    ("collapsed_reference_link" . link-ref-collapsed)
    ("shortcut_link" . link-shortcut)
    ("image" . image)
    ("uri_autolink" . autolink)
    ("email_autolink" . autolink-email)
    ("hard_line_break" . hard-break)
    ("backslash_escape" . escape)
    ;; Markers/delimiters
    ("atx_h1_marker" . h1-marker)
    ("atx_h2_marker" . h2-marker)
    ("atx_h3_marker" . h3-marker)
    ("atx_h4_marker" . h4-marker)
    ("atx_h5_marker" . h5-marker)
    ("atx_h6_marker" . h6-marker)
    ("list_marker_minus" . list-marker)
    ("list_marker_plus" . list-marker)
    ("list_marker_star" . list-marker)
    ("list_marker_dot" . list-marker-ordered)
    ("list_marker_parenthesis" . list-marker-ordered)
    ("block_quote_marker" . quote-marker)
    ("fenced_code_block_delimiter" . code-fence)
    ("code_fence_content" . code-content)
    ("info_string" . code-language)
    ("link_text" . link-text)
    ("link_destination" . link-url)
    ("link_title" . link-title)
    ("image_description" . image-alt))
  "Mapping from tree-sitter node types to markdown-modern element types.")

(defun markdown-modern-ts--map-node-type (ts-type)
  "Map tree-sitter node type TS-TYPE to markdown-modern type."
  (or (cdr (assoc ts-type markdown-modern-ts--node-type-map))
      (intern ts-type)))

;;; Queries

(defconst markdown-modern-ts--heading-query
  (treesit-query-compile
   'markdown
   '((atx_heading) @heading))
  "Query for finding headings.")

(defconst markdown-modern-ts--block-query
  (treesit-query-compile
   'markdown
   '([(atx_heading)
      (paragraph)
      (fenced_code_block)
      (indented_code_block)
      (block_quote)
      (list)
      (thematic_break)
      (pipe_table)
      (html_block)] @block))
  "Query for finding block elements.")

;;; Node Access Functions

(defun markdown-modern-ts--root-node ()
  "Get the root node of the markdown parse tree."
  (when markdown-modern-ts--parser
    (treesit-parser-root-node markdown-modern-ts--parser)))

(defun markdown-modern-ts--node-at (pos)
  "Get the smallest tree-sitter node at position POS."
  ;; Pass the parser object, not the language symbol: since Emacs 31,
  ;; `treesit-node-at' given a language falls back to the buffer's first
  ;; parser regardless of language, which here is the inline parser.
  (when markdown-modern-ts--parser
    (treesit-node-at pos markdown-modern-ts--parser)))

(defun markdown-modern-ts--element-at (pos)
  "Get the markdown-modern element at buffer position POS."
  (when-let ((ts-node (markdown-modern-ts--node-at pos)))
    (markdown-modern-ts--make-element ts-node)))

(defun markdown-modern-ts--make-element (ts-node)
  "Create a markdown-modern-node from tree-sitter node TS-NODE."
  (when ts-node
    (let* ((type-str (treesit-node-type ts-node))
           (type (markdown-modern-ts--map-node-type type-str))
           (start (treesit-node-start ts-node))
           (end (treesit-node-end ts-node)))
      (make-markdown-modern-node
       :type type
       :start start
       :end end
       :level (markdown-modern-ts--get-heading-level ts-node)
       :language (markdown-modern-ts--get-code-language ts-node)
       :treesit-node ts-node
       :properties nil))))

(defun markdown-modern-ts--get-heading-level (ts-node)
  "Get heading level from TS-NODE if it's a heading, nil otherwise."
  (when (string-match-p "heading" (treesit-node-type ts-node))
    (let ((marker (treesit-node-child-by-field-name ts-node "marker")))
      (if marker
          (length (string-trim (treesit-node-text marker)))
        ;; Try to detect from marker node type
        (let ((first-child (treesit-node-child ts-node 0)))
          (when first-child
            (pcase (treesit-node-type first-child)
              ("atx_h1_marker" 1)
              ("atx_h2_marker" 2)
              ("atx_h3_marker" 3)
              ("atx_h4_marker" 4)
              ("atx_h5_marker" 5)
              ("atx_h6_marker" 6)
              (_ 1))))))))

(defun markdown-modern-ts--get-code-language (ts-node)
  "Get code language from TS-NODE if it's a code block, nil otherwise.
In the tree-sitter-markdown grammar the language is an `info_string' child
node (not a field), so look it up by type."
  (when (string-match-p "code_block" (treesit-node-type ts-node))
    (when-let ((info (car (treesit-filter-child
                           ts-node
                           (lambda (c)
                             (string= (treesit-node-type c) "info_string"))))))
      (string-trim (treesit-node-text info)))))

(defun markdown-modern-ts--heading-text (node)
  "Get the text content of heading NODE (without markers)."
  (when (eq (markdown-modern-node-type node) 'heading)
    (let* ((ts-node (markdown-modern-node-treesit-node node))
           (text (treesit-node-text ts-node)))
      ;; Remove leading # markers and whitespace
      (string-trim (replace-regexp-in-string "^#+ *" "" text)))))

;;; Traversal Functions

(defun markdown-modern-ts--walk-headings (callback)
  "Walk all headings in buffer, calling CALLBACK with each node."
  (when-let ((root (markdown-modern-ts--root-node)))
    (dolist (capture (treesit-query-capture root markdown-modern-ts--heading-query))
      (funcall callback (markdown-modern-ts--make-element (cdr capture))))))

(defun markdown-modern-ts--walk-blocks (callback &optional start end)
  "Walk block elements, calling CALLBACK with each.
Optional START and END limit the range."
  (when-let ((root (markdown-modern-ts--root-node)))
    (let ((captures (treesit-query-capture
                     root markdown-modern-ts--block-query
                     (or start (point-min))
                     (or end (point-max)))))
      (dolist (capture captures)
        (funcall callback (markdown-modern-ts--make-element (cdr capture)))))))

(defun markdown-modern-ts--children (node)
  "Get children of NODE as markdown-modern-nodes."
  (when-let ((ts-node (markdown-modern-node-treesit-node node)))
    (let ((children '())
          (count (treesit-node-child-count ts-node)))
      (dotimes (i count)
        (push (markdown-modern-ts--make-element
               (treesit-node-child ts-node i))
              children))
      (nreverse children))))

(defun markdown-modern-ts--parent (node)
  "Get parent of NODE as markdown-modern-node."
  (when-let* ((ts-node (markdown-modern-node-treesit-node node))
              (parent (treesit-node-parent ts-node)))
    (markdown-modern-ts--make-element parent)))

;;; Block Boundary Detection

(defun markdown-modern-ts--containing-block (pos)
  "Get the block element containing position POS."
  (when-let ((node (markdown-modern-ts--node-at pos)))
    ;; Walk up to find block-level element
    (let ((current node))
      (while (and current
                  (not (markdown-modern-ts--block-element-p current)))
        (setq current (treesit-node-parent current)))
      (when current
        (markdown-modern-ts--make-element current)))))

(defun markdown-modern-ts--block-element-p (ts-node)
  "Return non-nil if TS-NODE is a block-level element."
  (member (treesit-node-type ts-node)
          '("atx_heading" "setext_heading" "paragraph"
            "fenced_code_block" "indented_code_block"
            "block_quote" "list" "list_item"
            "thematic_break" "pipe_table" "html_block")))

(defun markdown-modern-ts--containing-block-bounds (start end)
  "Get bounds of block containing region START to END."
  (let ((block-start start)
        (block-end end))
    ;; Expand to block boundaries
    (when-let ((start-block (markdown-modern-ts--containing-block start)))
      (setq block-start (min block-start (markdown-modern-node-start start-block))))
    (when-let ((end-block (markdown-modern-ts--containing-block end)))
      (setq block-end (max block-end (markdown-modern-node-end end-block))))
    (cons block-start block-end)))

;;; Line/Region Queries

(defun markdown-modern-ts--elements-in-region (start end)
  "Get all elements in region from START to END."
  (let ((elements '()))
    (markdown-modern-ts--walk-blocks
     (lambda (node)
       (push node elements))
     start end)
    (nreverse elements)))

(defun markdown-modern-ts--elements-on-line (line-num)
  "Get elements on line number LINE-NUM."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- line-num))
    (let ((start (line-beginning-position))
          (end (line-end-position)))
      (markdown-modern-ts--elements-in-region start end))))

;;; Inline Element Detection

(defun markdown-modern-ts--inline-elements-in (start end)
  "Get inline elements within range START to END."
  (when markdown-modern-ts--inline-parser
    (let ((elements '())
          (_text (buffer-substring-no-properties start end)))
      ;; Parse the text range for inline elements
      (treesit-parser-set-included-ranges
       markdown-modern-ts--inline-parser
       (list (cons start end)))
      ;; Query for inline elements
      (when-let ((root (treesit-parser-root-node markdown-modern-ts--inline-parser)))
        (dolist (child (markdown-modern-ts--collect-inline-nodes root))
          (push (markdown-modern-ts--make-element child) elements)))
      (nreverse elements))))

(defun markdown-modern-ts--collect-inline-nodes (node)
  "Recursively collect all inline element nodes from NODE."
  (let ((result '())
        (type (treesit-node-type node)))
    (when (member type '("emphasis" "strong_emphasis" "strikethrough"
                        "code_span" "inline_link" "full_reference_link"
                        "image" "uri_autolink" "email_autolink"))
      (push node result))
    ;; Recurse into children, but not inside inline code. Markdown content inside
    ;; a code span must stay literal, including underscores and asterisks.
    (unless (string= type "code_span")
      (dotimes (i (treesit-node-child-count node))
        (setq result (append result
                             (markdown-modern-ts--collect-inline-nodes
                              (treesit-node-child node i))))))
    result))

;;; Fallback Regex-based Parsing

(defconst markdown-modern-ts--heading-regex
  "^\\(#\\{1,6\\}\\) +\\(.*\\)"
  "Regex for ATX headings.")

(defconst markdown-modern-ts--emphasis-regex
  "\\(?:^\\|[^\\*_]\\)\\(\\*\\([^\\*\n\r]+\\)\\*\\|_\\([^_\n\r]+\\)_\\)"
  "Regex for emphasis (italic).  Only matches within a single line.")

(defconst markdown-modern-ts--strong-regex
  "\\(?:^\\|[^\\*_]\\)\\(\\*\\*\\([^\\*\n\r]+\\)\\*\\*\\|__\\([^_\n\r]+\\)__\\)"
  "Regex for strong (bold).  Only matches within a single line.")

(defconst markdown-modern-ts--code-span-regex
  "`\\([^`\n\r]+\\)`"
  "Regex for inline code.  Only matches within a single line.")

(defconst markdown-modern-ts--image-regex
  "!\\[\\([^]]*\\)\\](\\([^)]+\\))"
  "Regex for inline images.")

(defconst markdown-modern-ts--link-regex
  "\\[\\([^]]+\\)\\](\\([^)]+\\))"
  "Regex for inline links.")

(defconst markdown-modern-ts--code-block-regex
  "^[ \t]?[ \t]?[ \t]?\\(?:```\\|~~~\\)\\([a-zA-Z0-9_+-]*\\)?[ \t]*\r?$"
  "Regex for fenced code block start/end.
Group 1 captures the language (empty for a bare fence).
Allows up to 3 spaces indent per CommonMark spec.
Handles Windows CRLF line endings with \\r?.")

(defun markdown-modern-ts--fallback-parse-region (start end)
  "Parse region from START to END using regex fallback."
  (condition-case err
      (let ((elements '())
            (code-block-regions '())    ; Track code block regions to exclude
            (code-span-regions '())     ; Track inline code spans to exclude
            (blockquote-regions '()))   ; Track blockquote regions to exclude
        (save-excursion
      ;; FIRST: Find all fenced code blocks to know what regions to skip
      ;; Search for closing fence beyond region boundary if needed
      ;; Note: Use \r? for Windows CRLF
      ;; Important: closing fence must match opening fence type AND indentation
      (goto-char start)
      (while (and (< (point) end)
                  (re-search-forward "^\\([ \t]*\\)\\(```\\|~~~\\)\\([a-zA-Z0-9_+-]*\\)?[ \t]*\r?$" end t))
        (let* ((block-start (match-beginning 0))
               (_indent (match-string 1))     ; Capture the indentation
               (fence-char (match-string 2))  ; "```" or "~~~"
               (lang (match-string 3))
               ;; Build regex requiring SAME fence character for closing
               ;; Allow any leading whitespace (indented code blocks in lists)
               (closing-regex (concat "^[ \t]*" (regexp-quote fence-char) "[ \t]*\r?$"))
               ;; Limit search to reasonable distance (500 lines max)
               (search-limit (save-excursion (forward-line 500) (point))))
          ;; Search for closing fence with same character and compatible indentation
          (when (re-search-forward closing-regex search-limit t)
            (let ((block-end (match-end 0)))
              (push (cons block-start block-end) code-block-regions)
              (push (make-markdown-modern-node
                     :type 'code-block
                     :start block-start
                     :end block-end
                     :properties (list :language lang))
                    elements)))))

      ;; SECOND: Find all blockquotes to know what regions to skip for inline elements
      (goto-char start)
      (while (and (< (point) end)
                  (re-search-forward "^\\(>+\\)[ \t]?" end t))
        (let ((quote-start (match-beginning 0))
              (quote-end (line-end-position)))
          ;; Extend to include consecutive blockquote lines
          (save-excursion
            (forward-line 1)
            (while (and (< (point) end)
                        (looking-at "^>"))
              (setq quote-end (line-end-position))
              (forward-line 1)))
          (push (cons quote-start (min quote-end end)) blockquote-regions)
          (goto-char (min quote-end end))))

      ;; Helpers for skipping regions where inline markup should not be parsed.
      ;; `in-literal-region-p' treats the position right after a closing backtick
      ;; as *outside* the span — emphasis adjacent to it can use that backtick
      ;; as its required non-`*_' prefix character.
      (cl-labels ((in-code-block-p (pos)
                    (cl-some (lambda (region)
                               (and (>= pos (car region))
                                    (<= pos (cdr region))))
                             code-block-regions))
                  (in-special-block-p (pos)
                    (or (cl-some (lambda (region)
                                   (and (>= pos (car region))
                                        (<= pos (cdr region))))
                                 code-block-regions)
                        (cl-some (lambda (region)
                                   (and (>= pos (car region))
                                        (<= pos (cdr region))))
                                 blockquote-regions)))
                  (in-literal-region-p (pos)
                    (or (cl-some (lambda (region)
                                   (and (>= pos (car region))
                                        (< pos (cdr region))))
                                 code-block-regions)
                        (cl-some (lambda (region)
                                   (and (>= pos (car region))
                                        (< pos (cdr region))))
                                 code-span-regions))))

        ;; Find inline code spans before other inline markup so emphasis, links,
        ;; and math markers inside backticks are treated as literal text.
        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward markdown-modern-ts--code-span-regex end t))
          (unless (in-special-block-p (match-beginning 0))
            (let ((span-start (match-beginning 0))
                  (span-end (min (match-end 0) end)))
              (push (cons span-start span-end) code-span-regions)
              (push (make-markdown-modern-node
                     :type 'code-span
                     :start span-start
                     :end span-end)
                    elements))))

        ;; Find headings (not in code blocks)
        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward markdown-modern-ts--heading-regex end t))
          (unless (in-code-block-p (match-beginning 0))
            (push (make-markdown-modern-node
                   :type 'heading
                   :start (match-beginning 0)
                   :end (min (match-end 0) end)
                   :level (length (match-string 1)))
                  elements)))

        ;; Find horizontal rules (not in code blocks)
        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward "^\\(---+\\|\\*\\*\\*+\\|___+\\)[ \t]*$" end t))
          (unless (in-code-block-p (match-beginning 0))
            (push (make-markdown-modern-node
                   :type 'hr
                   :start (match-beginning 0)
                   :end (min (match-end 0) end))
                  elements)))

        ;; Find blockquotes (not in code blocks) - group consecutive lines
        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward "^\\(>+\\)[ \t]?" end t))
          (unless (in-code-block-p (match-beginning 0))
            (let ((quote-start (match-beginning 0))
                  (level (length (match-string 1)))
                  (quote-end (line-end-position)))
              ;; Extend to include consecutive blockquote lines
              (save-excursion
                (forward-line 1)
                (while (and (< (point) end)
                            (looking-at "^>"))
                  (setq quote-end (line-end-position))
                  (forward-line 1)))
              (push (make-markdown-modern-node
                     :type 'blockquote
                     :start quote-start
                     :end (min quote-end end)
                     :level level)
                    elements)
              ;; Skip to end of this blockquote
              (goto-char (min quote-end end)))))

        ;; Find unordered list items (not in code blocks)
        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward "^\\([ \t]*\\)\\([-*+]\\)[ \t]+" end t))
          (unless (in-code-block-p (match-beginning 0))
            (let ((item-start (match-beginning 0))
                  (indent (length (match-string 1))))
              (push (make-markdown-modern-node
                     :type 'list-item
                     :start item-start
                     :end (min (line-end-position) end)
                     :level (/ indent 2)
                     :properties (list :ordered nil))
                    elements))))

        ;; Find ordered list items (not in code blocks)
        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward "^\\([ \t]*\\)\\([0-9]+\\)[.)][ \t]+" end t))
          (unless (in-code-block-p (match-beginning 0))
            (let ((item-start (match-beginning 0))
                  (indent (length (match-string 1)))
                  (num (string-to-number (match-string 2))))
              (push (make-markdown-modern-node
                     :type 'list-item
                     :start item-start
                     :end (min (line-end-position) end)
                     :level (/ indent 2)
                     :properties (list :ordered t :number num))
                    elements))))

        ;; Find tables - group consecutive table rows into single table element
        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward "^|.+|[ \t]*$" end t))
          (unless (in-code-block-p (match-beginning 0))
            (let ((table-start (match-beginning 0))
                  (table-end (match-end 0)))
              ;; Extend to include all consecutive table rows
              (save-excursion
                (forward-line 1)
                (while (and (< (point) end)
                            (looking-at "^|.+|[ \t]*$"))
                  (setq table-end (match-end 0))
                  (forward-line 1)))
              (push (make-markdown-modern-node
                     :type 'table
                     :start table-start
                     :end (min table-end end))
                    elements)
              ;; Skip to end of this table
              (goto-char (min table-end end)))))

        ;; Find display math blocks ($$...$$) - two-pass like code blocks
        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward "^\\$\\$[ \t]*\r?$" end t))
          (let ((block-start (match-beginning 0)))
            (unless (in-code-block-p block-start)
              (if (re-search-forward "^\\$\\$[ \t]*\r?$" end t)
                  (let ((block-end (match-end 0)))
                    (push (make-markdown-modern-node
                           :type 'math-block
                           :start block-start
                           :end (min block-end end))
                          elements))
                ;; No closing $$, skip
                (goto-char end)))))

        ;; Find inline math ($...$) - not in code blocks/spans, not display math
        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward "\\$\\([^$\n]+\\)\\$" end t))
          (let ((pos (match-beginning 0))
                (mend (match-end 0)))
            (unless (or (in-literal-region-p pos)
                        (and (> pos (point-min))
                             (eq (char-before pos) ?$))
                        (and (< mend (point-max))
                             (eq (char-after mend) ?$)))
              (push (make-markdown-modern-node
                     :type 'math
                     :start pos
                     :end (min mend end))
                    elements))))

        ;; Find inline elements - outside code blocks and code spans
        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward markdown-modern-ts--strong-regex end t))
          (let ((pos (match-beginning 1)))
            (unless (in-literal-region-p pos)
              (push (make-markdown-modern-node
                     :type 'strong
                     :start pos
                     :end (min (match-end 1) end))
                    elements))))

        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward markdown-modern-ts--emphasis-regex end t))
          (let ((pos (match-beginning 1)))
            (unless (in-literal-region-p pos)
              (push (make-markdown-modern-node
                     :type 'emphasis
                     :start pos
                     :end (min (match-end 1) end))
                    elements))))

        ;; Find images (before links so links can skip image positions)
        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward markdown-modern-ts--image-regex end t))
          (let ((pos (match-beginning 0)))
            (unless (in-literal-region-p pos)
              (push (make-markdown-modern-node
                     :type 'image
                     :start pos
                     :end (min (match-end 0) end)
                     :properties (list :alt (match-string 1)
                                       :url (match-string 2)))
                    elements))))

        (goto-char start)
        (while (and (< (point) end)
                    (re-search-forward markdown-modern-ts--link-regex end t))
          (let ((pos (match-beginning 0)))
            (unless (or (in-literal-region-p pos)
                        ;; Skip if preceded by ! (that's an image, not a link)
                        (and (> pos (point-min))
                             (eq (char-before pos) ?!)))
              (push (make-markdown-modern-node
                     :type 'link
                     :start pos
                     :end (min (match-end 0) end)
                     :properties (list :text (match-string 1)
                                       :url (match-string 2)))
                    elements))))))
      (nreverse elements))
    (error
     (message "markdown-modern: Parse error: %s" (error-message-string err))
     nil)))

(provide 'markdown-modern-ts)
;;; markdown-modern-ts.el ends here
