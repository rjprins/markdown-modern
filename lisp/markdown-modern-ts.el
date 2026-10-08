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
(require 'seq)

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

(defvar-local markdown-modern-ts--parser nil
  "Tree-sitter parser for markdown.")

(defvar-local markdown-modern-ts--inline-parser nil
  "Tree-sitter parser for markdown-inline.")

(defvar-local markdown-modern-ts--parser-owner nil
  "Buffer that created and owns these parsers.
Indirect buffers can inherit parser references from their source buffer.")

;;; Grammar Management

;; v0.4.1 is the newest release for Tree-sitter ABI 14.  Tree-sitter libraries
;; older than 0.25, such as the one in GNU's Windows build, need ABI 14.
;; Emacs 31's markdown-ts-mode installs the same version.  Use a tag, not a
;; commit: Emacs 30 can only clone tags and branches.
(defconst markdown-modern-ts--grammar-sources
  '((markdown . ("https://github.com/tree-sitter-grammars/tree-sitter-markdown"
                 "v0.4.1"
                 "tree-sitter-markdown/src"))
    (markdown-inline . ("https://github.com/tree-sitter-grammars/tree-sitter-markdown"
                        "v0.4.1"
                        "tree-sitter-markdown-inline/src")))
  "Tree-sitter grammar sources for markdown.")

(defun markdown-modern-ts--ensure-grammar ()
  "Require Tree-sitter support and both Markdown grammars."
  (unless (treesit-available-p)
    (user-error "Use an Emacs build with Tree-sitter support for markdown-modern"))
  (let ((missing (seq-remove #'treesit-language-available-p
                             '(markdown markdown-inline))))
    (when missing
      (user-error "Missing Markdown grammars: %s; run M-x markdown-modern-install-grammars"
                  (mapconcat #'symbol-name missing ", ")))))

;;;###autoload
(defun markdown-modern-install-grammars ()
  "Install any missing Markdown Tree-sitter grammars.
Requires an Emacs build with Tree-sitter support, Git and a C compiler."
  (interactive)
  (unless (treesit-available-p)
    (user-error "Use an Emacs build with Tree-sitter support for markdown-modern"))
  (condition-case err
      (let ((treesit-language-source-alist
             (append markdown-modern-ts--grammar-sources treesit-language-source-alist)))
        (dolist (language '(markdown markdown-inline))
          (unless (treesit-language-available-p language)
            (treesit-install-language-grammar language))
          (unless (treesit-language-available-p language)
            (error "Grammar unavailable after installation: %s" language)))
        (message "Markdown grammars are ready"))
    (error
     (user-error "Cannot install Markdown grammars: %s" (error-message-string err)))))

;;; Parser Initialization

(defun markdown-modern-ts--init ()
  "Initialize tree-sitter parsers for the current buffer."
  (markdown-modern-ts--ensure-grammar)
  (markdown-modern-ts--cleanup)
  (setq markdown-modern-ts--parser-owner (current-buffer))
  (condition-case err
      (setq markdown-modern-ts--parser (treesit-parser-create 'markdown nil t)
            markdown-modern-ts--inline-parser (treesit-parser-create 'markdown-inline nil t))
    (error
     (markdown-modern-ts--cleanup)
     (user-error "Cannot initialize Markdown parsers: %s" (error-message-string err)))))

(defun markdown-modern-ts--cleanup ()
  "Delete the current buffer's Markdown Modern parsers."
  (when (eq markdown-modern-ts--parser-owner (current-buffer))
    (dolist (parser (list markdown-modern-ts--parser markdown-modern-ts--inline-parser))
      (when parser (treesit-parser-delete parser))))
  (setq markdown-modern-ts--parser nil
        markdown-modern-ts--inline-parser nil
        markdown-modern-ts--parser-owner nil))

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
    ("latex_block" . math)
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
  '((atx_heading) @heading)
  "Query for finding headings.")

(defconst markdown-modern-ts--block-query
  '([(atx_heading)
      (paragraph)
      (fenced_code_block)
      (indented_code_block)
      (block_quote)
      (list)
      (thematic_break)
      (pipe_table)
      (html_block)] @block)
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
  (when-let* ((ts-node (markdown-modern-ts--node-at pos)))
    (markdown-modern-ts--make-element ts-node)))

(defun markdown-modern-ts--make-element (ts-node)
  "Create a markdown-modern-node from tree-sitter node TS-NODE."
  (when ts-node
    (let* ((type-str (treesit-node-type ts-node))
           (type (if (and (equal type-str "latex_block")
                          (string-prefix-p "$$" (treesit-node-text ts-node)))
                     'math-block
                   (markdown-modern-ts--map-node-type type-str)))
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
    (when-let* ((info (car (treesit-filter-child
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
  (when-let* ((root (markdown-modern-ts--root-node)))
    (dolist (capture (treesit-query-capture root markdown-modern-ts--heading-query))
      (funcall callback (markdown-modern-ts--make-element (cdr capture))))))

(defun markdown-modern-ts--walk-blocks (callback &optional start end)
  "Walk block elements, calling CALLBACK with each.
Optional START and END limit the range."
  (when-let* ((root (markdown-modern-ts--root-node)))
    (let ((captures (treesit-query-capture
                     root markdown-modern-ts--block-query
                     (or start (point-min))
                     (or end (point-max)))))
      (dolist (capture captures)
        (funcall callback (markdown-modern-ts--make-element (cdr capture)))))))

(defun markdown-modern-ts--children (node)
  "Get children of NODE as markdown-modern-nodes."
  (when-let* ((ts-node (markdown-modern-node-treesit-node node)))
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
  ;; `treesit-node-at' can return a parentless block_continuation at a
  ;; newline inside a code fence.  A named node covering the character
  ;; keeps the enclosing block accessible, including on blank content lines.
  (when-let* ((parser markdown-modern-ts--parser)
              (node (treesit-node-on pos (min (1+ pos) (point-max)) parser t)))
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
    (when-let* ((start-block (markdown-modern-ts--containing-block start)))
      (setq block-start (min block-start (markdown-modern-node-start start-block))))
    (when-let* ((end-block (markdown-modern-ts--containing-block end)))
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
    (let ((elements '()))
      ;; Parse the text range for inline elements
      (treesit-parser-set-included-ranges
       markdown-modern-ts--inline-parser
       (list (cons start end)))
      ;; Query for inline elements
      (when-let* ((root (treesit-parser-root-node markdown-modern-ts--inline-parser)))
        (dolist (child (markdown-modern-ts--collect-inline-nodes root))
          (push (markdown-modern-ts--make-element child) elements)))
      (nreverse elements))))

(defun markdown-modern-ts--collect-inline-nodes (node)
  "Recursively collect all inline element nodes from NODE."
  (let ((result '())
        (type (treesit-node-type node)))
    (when (member type '("emphasis" "strong_emphasis" "strikethrough"
                        "code_span" "inline_link" "full_reference_link"
                        "image" "uri_autolink" "email_autolink" "latex_block"))
      (push node result))
    ;; Code and math contents stay literal, including Markdown delimiters.
    (unless (member type '("code_span" "latex_block"))
      (dotimes (i (treesit-node-child-count node))
        (setq result (append result
                             (markdown-modern-ts--collect-inline-nodes
                              (treesit-node-child node i))))))
    result))

(defun markdown-modern-ts--literal-inline-at-p (pos)
  "Return non-nil if POS is inside inline code, math or an HTML tag."
  (when markdown-modern-ts--inline-parser
    (let ((node (treesit-node-at pos markdown-modern-ts--inline-parser)))
      (while (and node
                  (not (member (treesit-node-type node)
                               '("code_span" "latex_block" "html_tag"))))
        (setq node (treesit-node-parent node)))
      node)))

(provide 'markdown-modern-ts)
;;; markdown-modern-ts.el ends here
