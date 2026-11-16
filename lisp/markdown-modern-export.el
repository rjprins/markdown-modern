;;; markdown-modern-export.el --- Export functionality for markdown-modern -*- lexical-binding: t; -*-

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

;; Export functionality for markdown-modern.
;; Provides built-in HTML export and optional Pandoc integration.

;;; Code:

(require 'cl-lib)

;;; Customization

(defcustom markdown-modern-export-html-template
  "<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"UTF-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
  <title>%s</title>
  <style>
%s
  </style>
</head>
<body>
  <article class=\"markdown-body\">
%s
  </article>
</body>
</html>"
  "HTML template for export.  %s placeholders: title, CSS, content."
  :type 'string
  :group 'markdown-modern-export)

(defcustom markdown-modern-export-html-css
  "
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
      font-size: 16px;
      line-height: 1.6;
      max-width: 900px;
      margin: 0 auto;
      padding: 20px;
      color: #24292e;
      background-color: #fff;
    }
    .markdown-body {
      box-sizing: border-box;
      min-width: 200px;
      max-width: 980px;
      margin: 0 auto;
      padding: 45px;
    }
    h1, h2, h3, h4, h5, h6 {
      margin-top: 24px;
      margin-bottom: 16px;
      font-weight: 600;
      line-height: 1.25;
    }
    h1 { font-size: 2em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    h2 { font-size: 1.5em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1em; }
    h5 { font-size: 0.875em; }
    h6 { font-size: 0.85em; color: #6a737d; }
    p { margin-top: 0; margin-bottom: 16px; }
    a { color: #0366d6; text-decoration: none; }
    a:hover { text-decoration: underline; }
    strong { font-weight: 600; }
    em { font-style: italic; }
    code {
      font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
      font-size: 85%;
      background-color: rgba(27,31,35,0.05);
      padding: 0.2em 0.4em;
      border-radius: 3px;
    }
    pre {
      font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
      font-size: 85%;
      background-color: #f6f8fa;
      border-radius: 3px;
      padding: 16px;
      overflow: auto;
      line-height: 1.45;
    }
    pre code {
      background-color: transparent;
      padding: 0;
      font-size: 100%;
    }
    blockquote {
      margin: 0;
      padding: 0 1em;
      color: #6a737d;
      border-left: 0.25em solid #dfe2e5;
    }
    ul, ol {
      padding-left: 2em;
      margin-top: 0;
      margin-bottom: 16px;
    }
    li { margin-top: 0.25em; }
    li + li { margin-top: 0.25em; }
    table {
      border-collapse: collapse;
      border-spacing: 0;
      margin-top: 0;
      margin-bottom: 16px;
      width: 100%;
      overflow: auto;
    }
    table th, table td {
      padding: 6px 13px;
      border: 1px solid #dfe2e5;
    }
    table th {
      font-weight: 600;
      background-color: #f6f8fa;
    }
    table tr:nth-child(2n) { background-color: #f6f8fa; }
    hr {
      height: 0.25em;
      padding: 0;
      margin: 24px 0;
      background-color: #e1e4e8;
      border: 0;
    }
    img {
      max-width: 100%;
      box-sizing: content-box;
    }
    .task-list-item {
      list-style-type: none;
    }
    .task-list-item input {
      margin: 0 0.2em 0.25em -1.6em;
      vertical-align: middle;
    }
    .footnote-ref { font-size: 0.8em; vertical-align: super; }
    .footnotes { font-size: 0.9em; margin-top: 2em; border-top: 1px solid #dfe2e5; padding-top: 1em; }
    @media (prefers-color-scheme: dark) {
      body { background-color: #0d1117; color: #c9d1d9; }
      a { color: #58a6ff; }
      code { background-color: rgba(110,118,129,0.4); }
      pre { background-color: #161b22; }
      blockquote { color: #8b949e; border-left-color: #3b434b; }
      table th, table td { border-color: #30363d; }
      table th { background-color: #161b22; }
      table tr:nth-child(2n) { background-color: #161b22; }
      hr { background-color: #21262d; }
    }
"
  "Default CSS for HTML export."
  :type 'string
  :group 'markdown-modern-export)

(defcustom markdown-modern-export-embed-images nil
  "Whether to embed images as base64 in HTML export."
  :type 'boolean
  :group 'markdown-modern-export)

(defcustom markdown-modern-pandoc-executable "pandoc"
  "Path to Pandoc executable."
  :type 'string
  :group 'markdown-modern-export)

(defcustom markdown-modern-use-pandoc nil
  "Whether to use Pandoc for export operations when available."
  :type 'boolean
  :group 'markdown-modern-export)

;;; Pandoc Integration

(defun markdown-modern-pandoc-available-p ()
  "Check if Pandoc is available."
  (executable-find markdown-modern-pandoc-executable))

;;;###autoload
(defun markdown-modern-export-via-pandoc (format &optional output-file)
  "Export current buffer to FORMAT using Pandoc.
FORMAT should be a pandoc output format (e.g., \"html\", \"pdf\", \"docx\").
If OUTPUT-FILE is nil, prompts for destination."
  (interactive
   (list (completing-read "Export format: "
                          '("html" "pdf" "docx" "odt" "epub" "latex" "rst" "org")
                          nil t)
         nil))
  (unless (markdown-modern-pandoc-available-p)
    (user-error "Pandoc not found; install Pandoc or set `markdown-modern-pandoc-executable'"))
  (let* ((base-name (if buffer-file-name
                        (file-name-sans-extension buffer-file-name)
                      "export"))
         (extension (pcase format
                      ("html" ".html")
                      ("pdf" ".pdf")
                      ("docx" ".docx")
                      ("odt" ".odt")
                      ("epub" ".epub")
                      ("latex" ".tex")
                      ("rst" ".rst")
                      ("org" ".org")
                      (_ (format ".%s" format))))
         (default-output (concat base-name extension))
         (output (or output-file
                     (read-file-name "Export to: " nil nil nil
                                    (file-name-nondirectory default-output))))
         (input-file (if buffer-file-name
                         buffer-file-name
                       (let ((temp (make-temp-file "markdown-modern-" nil ".md")))
                         (write-region (point-min) (point-max) temp)
                         temp))))
    ;; Run Pandoc
    (let* ((args (list "-f" "markdown"
                       "-t" format
                       "-o" output
                       input-file))
           (exit-code (apply #'call-process markdown-modern-pandoc-executable
                             nil "*markdown-modern-pandoc*" nil args)))
      (if (zerop exit-code)
          (progn
            (message "Exported to %s" output)
            output)
        (pop-to-buffer "*markdown-modern-pandoc*")
        (user-error "Pandoc export failed")))))

;;;###autoload
(defun markdown-modern-export-pdf (&optional output-file)
  "Export current buffer to PDF using Pandoc.
If OUTPUT-FILE is nil, prompts for destination."
  (interactive)
  (markdown-modern-export-via-pandoc "pdf" output-file))

;;;###autoload
(defun markdown-modern-export-docx (&optional output-file)
  "Export current buffer to DOCX using Pandoc.
If OUTPUT-FILE is nil, prompts for destination."
  (interactive)
  (markdown-modern-export-via-pandoc "docx" output-file))

;;; Built-in HTML Export

;;;###autoload
(defun markdown-modern-export-html (&optional output-file)
  "Export current buffer to HTML.
If OUTPUT-FILE is nil, prompts for destination.
Uses built-in converter (no external dependencies)."
  (interactive)
  (let* ((base-name (if buffer-file-name
                        (file-name-sans-extension buffer-file-name)
                      "export"))
         (default-output (concat base-name ".html"))
         (output (or output-file
                     (read-file-name "Export to: " nil nil nil
                                    (file-name-nondirectory default-output))))
         (title (markdown-modern-export--escape-html
                 (or (markdown-modern-export--get-title)
                     (file-name-base output))))
         (content (markdown-modern-export--markdown-to-html
                   (buffer-substring-no-properties (point-min) (point-max))))
         (html (format markdown-modern-export-html-template
                       title
                       markdown-modern-export-html-css
                       content)))
    (with-temp-file output
      (insert html))
    (message "Exported to %s" output)
    output))

;;;###autoload
(defun markdown-modern-preview-html ()
  "Export to a temporary HTML file and open in browser."
  (interactive)
  (let ((output (make-temp-file "markdown-modern-preview-" nil ".html")))
    (markdown-modern-export-html output)
    (browse-url (concat "file://" output))))

(defun markdown-modern-export--get-title ()
  "Extract title from buffer (first H1 heading)."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^# +\\(.+\\)$" nil t)
      (match-string 1))))

;;; Markdown to HTML Conversion

;; The converter works in two passes.  A line-based block pass splits the
;; document into blocks: code, headings, rules, quotes, lists, tables, HTML,
;; display math and paragraphs.  It recurses into quotes and list items.  An
;; inline pass then renders the text of each paragraph, heading and table
;; cell.  It sets code spans, math, raw HTML and backslash escapes aside
;; first, so the emphasis and link rules never see them, and leaves link
;; destinations alone.  Then it turns each link into one placeholder, with
;; its text rendered on its own, and last it renders emphasis.  Each
;; emphasis span is rendered on its own too, so spans nest and never
;; cross a link or another span.

(defvar markdown-modern-export--link-refs nil
  "Hash table of link reference definitions, bound during a conversion.
Keys are normalized labels, values are (URL . TITLE).")

(defconst markdown-modern-export--html-block-tags
  '("address" "article" "aside" "base" "basefont" "blockquote" "body"
    "caption" "center" "col" "colgroup" "dd" "details" "dialog" "dir" "div"
    "dl" "dt" "fieldset" "figcaption" "figure" "footer" "form" "frame"
    "frameset" "h1" "h2" "h3" "h4" "h5" "h6" "head" "header" "hr" "html"
    "iframe" "legend" "li" "link" "main" "menu" "menuitem" "nav" "noframes"
    "ol" "optgroup" "option" "p" "param" "search" "section" "summary" "table"
    "tbody" "td" "tfoot" "th" "thead" "title" "tr" "track" "ul")
  "Tags that start an HTML block, as in CommonMark.")

(defconst markdown-modern-export--tag-re
  (concat "</?[A-Za-z][A-Za-z0-9-]*"
          "\\(?:[ \t\n]+[A-Za-z_:][A-Za-z0-9_.:-]*"
          "\\(?:[ \t\n]*=[ \t\n]*"
          "\\(?:[^ \t\n\"'=<>`]+\\|'[^']*'\\|\"[^\"]*\"\\)\\)?\\)*"
          "[ \t\n]*/?>")
  "Regexp for an HTML open or closing tag.")

(defconst markdown-modern-export--fence-re
  "\\`\\( \\{0,3\\}\\)\\(`\\{3,\\}\\|~\\{3,\\}\\)\\(.*\\)\\'"
  "Regexp for the opening line of a fenced code block.")

(defconst markdown-modern-export--heading-re
  "\\` \\{0,3\\}\\(#\\{1,6\\}\\)\\(?:[ \t]+\\(.*?\\)\\)?\\(?:[ \t]+#+\\)?[ \t]*\\'"
  "Regexp for an ATX heading line.")

(defconst markdown-modern-export--hr-re
  (concat "\\` \\{0,3\\}\\(?:\\(?:\\*[ \t]*\\)\\{3,\\}"
          "\\|\\(?:-[ \t]*\\)\\{3,\\}\\|\\(?:_[ \t]*\\)\\{3,\\}\\)\\'")
  "Regexp for a horizontal rule.")

(defconst markdown-modern-export--quote-re "\\` \\{0,3\\}> ?"
  "Regexp for the marker of a blockquote line.")

(defconst markdown-modern-export--item-re
  (concat "\\`\\( \\{0,3\\}\\)\\([-*+]\\|\\([0-9]\\{1,9\\}\\)[.)]\\)"
          "\\(?:\\( +\\)\\(.*\\)\\)?\\'")
  "Regexp for the first line of a list item.")

(defconst markdown-modern-export--setext-re "\\` \\{0,3\\}\\(=+\\|-+\\)[ \t]*\\'"
  "Regexp for a setext heading underline.")

(defconst markdown-modern-export--table-delimiter-re
  "\\`[ \t]*|?\\(?:[ \t]*:?-+:?[ \t]*|\\)*[ \t]*:?-+:?[ \t]*|?[ \t]*\\'"
  "Regexp for the delimiter row of a table.")

(defconst markdown-modern-export--link-def-re
  (concat "\\` \\{0,3\\}\\[\\([^]^][^]]*\\)\\]:[ \t]*<?\\([^ \t<>]+\\)>?"
          "\\(?:[ \t]+\\(?:\"\\([^\"]*\\)\"\\|'\\([^']*\\)'\\|(\\([^)]*\\))\\)\\)?"
          "[ \t]*\\'")
  "Regexp for a link reference definition.")

(defconst markdown-modern-export--entity-re
  "&\\(?:#[0-9]\\{1,7\\}\\|#[xX][0-9a-fA-F]\\{1,6\\}\\|[A-Za-z][A-Za-z0-9]\\{0,31\\}\\);"
  "Regexp for an HTML entity or numeric character reference.")

(defconst markdown-modern-export--link-dest-re
  (concat "([ \t\n]*\\([^ \t\n()]*\\(?:([^ \t\n()]*)[^ \t\n()]*\\)*\\)"
          "\\(?:[ \t\n]+\\(?:\"\\([^\"]*\\)\"\\|'\\([^']*\\)'\\)\\)?"
          "[ \t\n]*)")
  "Regexp for the destination and title of an inline link, after its ].
Group 1 is the destination, group 2 or 3 the title.")

(defun markdown-modern-export--markdown-to-html (markdown)
  "Convert MARKDOWN string to HTML."
  (let ((case-fold-search nil)
        (markdown-modern-export--link-refs (make-hash-table :test #'equal)))
    (markdown-modern-export--render-blocks
     (car (markdown-modern-export--parse-blocks
           (mapcar #'markdown-modern-export--expand-indent-tabs
                   (split-string markdown "\r?\n"))))
     nil)))

;;; Block parsing

(defun markdown-modern-export--expand-indent-tabs (line)
  "Return LINE with tabs in its indentation expanded to 4-column stops."
  (if (string-match "\\`[ \t]*\t" line)
      (let ((end (match-end 0))
            (col 0))
        (dotimes (i end)
          (setq col (if (eq (aref line i) ?\t) (* 4 (1+ (/ col 4))) (1+ col))))
        (concat (make-string col ?\s) (substring line end)))
    line))

(defun markdown-modern-export--blank-p (line)
  "Return non-nil when LINE holds only whitespace."
  (string-match-p "\\`[ \t]*\\'" line))

(defun markdown-modern-export--indent (line)
  "Return the number of leading spaces in LINE."
  (string-match "\\` *" line)
  (match-end 0))

(defun markdown-modern-export--strip-indent (line n)
  "Remove up to N leading spaces from LINE."
  (substring line (min n (markdown-modern-export--indent line))))

(defun markdown-modern-export--fence-open (line)
  "Return (INDENT FENCE INFO) when LINE opens a fenced code block."
  (when (string-match markdown-modern-export--fence-re line)
    (let ((indent (length (match-string 1 line)))
          (fence (match-string 2 line))
          (info (string-trim (match-string 3 line))))
      (unless (and (eq (aref fence 0) ?`) (string-search "`" info))
        (list indent fence info)))))

(defun markdown-modern-export--html-block-type (line)
  "Return the CommonMark HTML block type that LINE starts, or nil.
Type 1 ends at a closing script, pre, style or textarea tag, type 2
at -->, and types 6 and 7 at a blank line."
  (cond
   ((string-match-p "\\` \\{0,3\\}<\\(?:script\\|pre\\|style\\|textarea\\)\\(?:[ \t>]\\|\\'\\)"
                    line)
    1)
   ((string-match-p "\\` \\{0,3\\}<!--" line) 2)
   ((and (string-match "\\` \\{0,3\\}</?\\([A-Za-z][A-Za-z0-9-]*\\)\\(?:[ \t>]\\|/>\\|\\'\\)"
                       line)
         (member (downcase (match-string 1 line))
                 markdown-modern-export--html-block-tags))
    6)
   ((string-match-p (concat "\\` \\{0,3\\}" markdown-modern-export--tag-re "[ \t]*\\'")
                    line)
    7)))

(defun markdown-modern-export--interrupts-p (line &optional any-item)
  "Return non-nil when LINE starts a block that ends a paragraph.
An ordered list item interrupts only when it starts at 1, unless
ANY-ITEM is non-nil."
  (or (markdown-modern-export--blank-p line)
      (markdown-modern-export--fence-open line)
      (string-match-p markdown-modern-export--heading-re line)
      (string-match-p markdown-modern-export--hr-re line)
      (string-match-p markdown-modern-export--quote-re line)
      (and (string-match markdown-modern-export--item-re line)
           (or any-item
               (and (match-string 5 line)
                    (not (markdown-modern-export--blank-p (match-string 5 line)))
                    (or (not (match-string 3 line))
                        (equal (match-string 3 line) "1")))))
      (memq (markdown-modern-export--html-block-type line) '(1 2 6))))

(defun markdown-modern-export--parse-blocks (lines)
  "Parse LINES into a list of blocks.
Return (BLOCKS . LOOSE), where LOOSE is non-nil when a blank line
separates two of the blocks."
  (let* ((v (vconcat lines))
         (n (length v))
         (i 0)
         blocks gap loose)
    (while (< i n)
      (if (markdown-modern-export--blank-p (aref v i))
          (setq gap (and blocks t)
                i (1+ i))
        (pcase-let ((`(,block . ,next) (markdown-modern-export--parse-block v i)))
          (when block
            (when gap (setq loose t))
            (setq gap nil)
            (push block blocks))
          (setq i next))))
    (cons (nreverse blocks) loose)))

(defun markdown-modern-export--parse-block (v i)
  "Parse the block that starts at line I of the line vector V.
Return (BLOCK . NEXT), where NEXT is the index of the line after it.
BLOCK is nil for a line that only defines a link reference."
  (let ((line (aref v i)))
    (cond
     ((markdown-modern-export--fence-open line)
      (markdown-modern-export--parse-fence v i))
     ((>= (markdown-modern-export--indent line) 4)
      (markdown-modern-export--parse-indented-code v i))
     ((string-match markdown-modern-export--heading-re line)
      (cons (list 'heading (length (match-string 1 line))
                  (or (match-string 2 line) ""))
            (1+ i)))
     ((string-match-p markdown-modern-export--hr-re line)
      (cons (list 'hr) (1+ i)))
     ((string-match-p markdown-modern-export--quote-re line)
      (markdown-modern-export--parse-quote v i))
     ((string-match-p markdown-modern-export--item-re line)
      (markdown-modern-export--parse-list v i))
     ((markdown-modern-export--html-block-type line)
      (markdown-modern-export--parse-html v i))
     ((markdown-modern-export--parse-math v i))
     ((markdown-modern-export--parse-table v i))
     ((string-match markdown-modern-export--link-def-re line)
      (let ((label (markdown-modern-export--normalize-label (match-string 1 line))))
        (unless (gethash label markdown-modern-export--link-refs)
          (puthash label
                   (cons (match-string 2 line)
                         (or (match-string 3 line) (match-string 4 line)
                             (match-string 5 line)))
                   markdown-modern-export--link-refs)))
      (cons nil (1+ i)))
     (t (markdown-modern-export--parse-paragraph v i)))))

(defun markdown-modern-export--parse-fence (v i)
  "Parse the fenced code block that opens at line I of V."
  (pcase-let* ((`(,indent ,fence ,info)
                (markdown-modern-export--fence-open (aref v i)))
               (close-re (format "\\` \\{0,3\\}%s\\{%d,\\}[ \t]*\\'"
                                 (regexp-quote (substring fence 0 1))
                                 (length fence)))
               (n (length v))
               (j (1+ i))
               (code '()))
    (while (and (< j n) (not (string-match-p close-re (aref v j))))
      (push (markdown-modern-export--strip-indent (aref v j) indent) code)
      (setq j (1+ j)))
    (cons (list 'code
                (replace-regexp-in-string "\\`[.{]+\\|}\\'" ""
                                          (or (car (split-string info)) ""))
                (string-join (nreverse code) "\n"))
          (min n (1+ j)))))

(defun markdown-modern-export--parse-indented-code (v i)
  "Parse the indented code block that starts at line I of V."
  (let ((n (length v))
        (j i)
        (last i))
    (while (and (< j n)
                (or (markdown-modern-export--blank-p (aref v j))
                    (>= (markdown-modern-export--indent (aref v j)) 4)))
      (unless (markdown-modern-export--blank-p (aref v j))
        (setq last j))
      (setq j (1+ j)))
    (cons (list 'code nil
                (mapconcat (lambda (line)
                             (markdown-modern-export--strip-indent line 4))
                           (cl-subseq v i (1+ last))
                           "\n"))
          (1+ last))))

(defun markdown-modern-export--parse-quote (v i)
  "Parse the blockquote that starts at line I of V."
  (let ((n (length v))
        (j i)
        (inner '()))
    (while (and (< j n)
                (let ((line (aref v j)))
                  (cond
                   ((string-match markdown-modern-export--quote-re line)
                    (push (substring line (match-end 0)) inner))
                   ;; A lazy continuation line of a paragraph in the quote.
                   ((and (not (markdown-modern-export--blank-p (car inner)))
                         (not (markdown-modern-export--interrupts-p line t)))
                    (push line inner)))))
      (setq j (1+ j)))
    (cons (list 'quote (car (markdown-modern-export--parse-blocks (nreverse inner))))
          j)))

(defun markdown-modern-export--item-info (line)
  "Return (KIND INDENT FIRST START) when LINE starts a list item.
KIND is the bullet or delimiter character, ordered when START is
a number.  INDENT is the column the item's content starts at and
FIRST the content on LINE."
  (when (and (string-match markdown-modern-export--item-re line)
             (not (string-match-p markdown-modern-export--hr-re line)))
    (let* ((marker-end (match-end 2))
           (spaces (length (or (match-string 4 line) "")))
           (text (or (match-string 5 line) ""))
           (start (and (match-string 3 line)
                       (string-to-number (match-string 3 line))))
           (kind (aref line (1- marker-end))))
      (cond
       ((string-empty-p text)
        (list kind (1+ marker-end) "" start))
       ;; Five or more spaces: the content is indented code.
       ((> spaces 4)
        (list kind (1+ marker-end) (concat (make-string (1- spaces) ?\s) text) start))
       (t (list kind (+ marker-end spaces) text start))))))

(defun markdown-modern-export--parse-list (v i)
  "Parse the list that starts at line I of V."
  (pcase-let* ((n (length v))
               (`(,kind ,_ ,_ ,start) (markdown-modern-export--item-info (aref v i)))
               (j i)
               (items '())
               (loose nil)
               (info nil))
    (while (and (< j n)
                (setq info (markdown-modern-export--item-info (aref v j)))
                (eq (car info) kind))
      (pcase-let ((`(,_ ,width ,first ,_) info)
                  (lines '())
                  (task nil)
                  (trailing 0))
        (when (string-match "\\`\\[\\([ xX]\\)\\]\\(?:[ \t]+\\|\\'\\)" first)
          (setq task (if (equal (match-string 1 first) " ") 'open 'checked)
                first (substring first (match-end 0))))
        (push first lines)
        (setq j (1+ j))
        (while (and (< j n)
                    (let ((line (aref v j)))
                      (cond
                       ((markdown-modern-export--blank-p line)
                        (push "" lines))
                       ((>= (markdown-modern-export--indent line) width)
                        (push (substring line width) lines))
                       ;; A lazy continuation line of the item's paragraph.
                       ((and (not (string-empty-p (car lines)))
                             (not (markdown-modern-export--interrupts-p line t)))
                        (push line lines)))))
          (setq j (1+ j)))
        (while (and lines (string-empty-p (car lines)))
          (setq lines (cdr lines)
                trailing (1+ trailing)))
        (let ((parsed (markdown-modern-export--parse-blocks (nreverse lines))))
          (when (cdr parsed) (setq loose t))
          (push (list task (car parsed)) items))
        (let ((next (and (< j n) (markdown-modern-export--item-info (aref v j)))))
          (if (and next (eq (car next) kind))
              (when (> trailing 0) (setq loose t))
            ;; Leave the blank lines after the list to the caller.
            (setq j (- j trailing))))))
    (cons (list 'list start (nreverse items) loose) j)))

(defun markdown-modern-export--parse-html (v i)
  "Parse the HTML block that starts at line I of V."
  (let* ((type (markdown-modern-export--html-block-type (aref v i)))
         (end-re (pcase type
                   (1 "</\\(?:script\\|pre\\|style\\|textarea\\)>")
                   (2 "-->")))
         (n (length v))
         (j i))
    (if end-re
        (progn
          (while (and (< j n) (not (string-match-p end-re (aref v j))))
            (setq j (1+ j)))
          (setq j (min n (1+ j))))
      (while (and (< j n) (not (markdown-modern-export--blank-p (aref v j))))
        (setq j (1+ j))))
    (cons (list 'html (string-join (cl-subseq v i j) "\n")) j)))

(defun markdown-modern-export--parse-math (v i)
  "Parse a display math block of $$ lines at line I of V, or return nil.
The block ends at a line that ends with $$, which can be the first."
  (when (string-match-p "\\` \\{0,3\\}\\$\\$" (aref v i))
    (let* ((n (length v))
           (closing "\\$\\$[ \t]*\\'")
           (first (string-trim (aref v i)))
           (j (if (and (> (length first) 2) (string-match-p closing first))
                  i
                (let ((k (1+ i)))
                  (while (and (< k n)
                              (not (markdown-modern-export--blank-p (aref v k)))
                              (not (string-match-p closing (aref v k))))
                    (setq k (1+ k)))
                  (and (< k n) (string-match-p closing (aref v k)) k)))))
      (when j
        (cons (list 'math (string-trim (string-join (cl-subseq v i (1+ j)) "\n")))
              (1+ j))))))

(defun markdown-modern-export--split-row (line)
  "Split the table row LINE into trimmed cells.
A backslash-escaped pipe stays in its cell."
  (let ((text (string-trim line))
        (cells '())
        (cell "")
        (i 0))
    (when (string-prefix-p "|" text)
      (setq text (substring text 1)))
    (when (and (string-suffix-p "|" text) (not (string-suffix-p "\\|" text)))
      (setq text (substring text 0 -1)))
    (while (< i (length text))
      (let ((c (aref text i)))
        (cond
         ((and (eq c ?\\) (< (1+ i) (length text)) (eq (aref text (1+ i)) ?|))
          (setq cell (concat cell "\\|")
                i (1+ i)))
         ((eq c ?|)
          (push cell cells)
          (setq cell ""))
         (t (setq cell (concat cell (string c))))))
      (setq i (1+ i)))
    (push cell cells)
    (mapcar #'string-trim (nreverse cells))))

(defun markdown-modern-export--parse-table (v i)
  "Parse a table at line I of V, or return nil."
  (let ((n (length v))
        (header (aref v i)))
    (when (and (< (1+ i) n)
               (string-search "|" header)
               (string-match-p markdown-modern-export--table-delimiter-re (aref v (1+ i)))
               (string-search "-" (aref v (1+ i)))
               (= (length (markdown-modern-export--split-row header))
                  (length (markdown-modern-export--split-row (aref v (1+ i))))))
      (let ((aligns (mapcar (lambda (cell)
                              (let ((left (string-prefix-p ":" cell))
                                    (right (string-suffix-p ":" cell)))
                                (cond ((and left right) "center")
                                      (left "left")
                                      (right "right"))))
                            (markdown-modern-export--split-row (aref v (1+ i)))))
            (rows '())
            (j (+ i 2)))
        (while (and (< j n)
                    (not (markdown-modern-export--interrupts-p (aref v j))))
          (push (markdown-modern-export--split-row (aref v j)) rows)
          (setq j (1+ j)))
        (cons (list 'table aligns (markdown-modern-export--split-row header)
                    (nreverse rows))
              j)))))

(defun markdown-modern-export--parse-paragraph (v i)
  "Parse the paragraph that starts at line I of V.
A setext underline turns it into a heading."
  (let ((n (length v))
        (j (1+ i))
        (lines (list (string-trim-left (aref v i))))
        (level nil))
    (while (and (< j n) (not level)
                (let ((line (aref v j)))
                  (cond
                   ((string-match markdown-modern-export--setext-re line)
                    (setq level (if (eq (aref (match-string 1 line) 0) ?=) 1 2)))
                   ((not (markdown-modern-export--interrupts-p line))
                    (push (string-trim-left line) lines)))))
      (setq j (1+ j)))
    (let ((text (string-trim-right (string-join (nreverse lines) "\n"))))
      (cons (if level (list 'heading level text) (list 'para text))
            j))))

;;; Block rendering

(defun markdown-modern-export--render-blocks (blocks tight)
  "Render BLOCKS as HTML.
When TIGHT is non-nil, paragraphs are not wrapped in <p>."
  (mapconcat (lambda (block) (markdown-modern-export--render-block block tight))
             blocks "\n"))

(defun markdown-modern-export--render-block (block tight &optional prefix)
  "Render BLOCK as HTML.
When TIGHT is non-nil, a paragraph is not wrapped in <p>.  PREFIX
is HTML to put before a paragraph's text."
  (pcase block
    (`(para ,text)
     (let ((html (concat prefix (markdown-modern-export--inline text))))
       (if tight html (format "<p>%s</p>" html))))
    (`(heading ,level ,text)
     (format "<h%d id=\"%s\">%s</h%d>"
             level (markdown-modern-export--heading-id text)
             (markdown-modern-export--inline text) level))
    (`(code ,lang ,text)
     (format "<pre><code%s>%s</code></pre>"
             (if (or (null lang) (string-empty-p lang)) ""
               (format " class=\"language-%s\"" (markdown-modern-export--escape-html lang)))
             (markdown-modern-export--escape-html text)))
    (`(hr) "<hr>")
    (`(html ,text) text)
    (`(math ,text)
     (format "<div class=\"math display\">%s</div>"
             (markdown-modern-export--escape-html text)))
    (`(quote ,blocks)
     (format "<blockquote>\n%s\n</blockquote>"
             (markdown-modern-export--render-blocks blocks nil)))
    (`(list ,start ,items ,loose)
     (let ((tag (if start "ol" "ul")))
       (format "<%s%s>\n%s\n</%s>"
               tag
               (if (and start (/= start 1)) (format " start=\"%d\"" start) "")
               (mapconcat (lambda (item)
                            (markdown-modern-export--render-item item (not loose)))
                          items "\n")
               tag)))
    (`(table ,aligns ,header ,rows)
     (markdown-modern-export--render-table aligns header rows))))

(defun markdown-modern-export--render-item (item tight)
  "Render the list ITEM, a list (TASK BLOCKS), as an <li>.
TASK is nil, `open' or `checked'.  When TIGHT is non-nil, its
paragraphs are not wrapped in <p>."
  (pcase-let* ((`(,task ,blocks) item)
               (box (when task
                      (format "<input type=\"checkbox\"%s disabled> "
                              (if (eq task 'checked) " checked" "")))))
    (format "<li%s>%s</li>"
            (if task " class=\"task-list-item\"" "")
            (if (and box (eq (car-safe (car blocks)) 'para))
                (mapconcat #'identity
                           (cons (markdown-modern-export--render-block
                                  (car blocks) tight box)
                                 (mapcar (lambda (block)
                                           (markdown-modern-export--render-block block tight))
                                         (cdr blocks)))
                           "\n")
              (concat box (markdown-modern-export--render-blocks blocks tight))))))

(defun markdown-modern-export--render-table (aligns header rows)
  "Render a table with column ALIGNS, HEADER cells and body ROWS."
  (cl-flet ((row (tag cells)
              (concat "<tr>"
                      (mapconcat
                       (lambda (pair)
                         (format "<%s%s>%s</%s>"
                                 tag
                                 (if (cdr pair)
                                     (format " style=\"text-align: %s\"" (cdr pair))
                                   "")
                                 (markdown-modern-export--inline (car pair))
                                 tag))
                       (cl-mapcar #'cons
                                  (append cells
                                          (make-list (max 0 (- (length aligns)
                                                               (length cells)))
                                                     ""))
                                  aligns)
                       "")
                      "</tr>\n")))
    (concat "<table>\n<thead>\n" (row "th" header) "</thead>\n"
            (when rows
              (concat "<tbody>\n"
                      (mapconcat (lambda (cells) (row "td" cells)) rows "")
                      "</tbody>\n"))
            "</table>")))

;;; Inline rendering

(defun markdown-modern-export--inline (text)
  "Render the inline Markdown in TEXT as HTML."
  (let* ((slots (make-hash-table))
         (count 0)
         (stash (lambda (html)
                  (puthash count html slots)
                  (prog1 (format "\uE000%d\uE001" count)
                    (setq count (1+ count))))))
    (with-temp-buffer
      (let ((case-fold-search nil))
        (insert text)
        (markdown-modern-export--inline-protect stash)
        (goto-char (point-min))
        (while (re-search-forward " \\{2,\\}\n" nil t)
          (replace-match (concat (funcall stash "<br>") "\n") t t))
        (markdown-modern-export--inline-spans stash)
        ;; Put back what was set aside.  A slot can hold other slots.
        (goto-char (point-min))
        (while (re-search-forward "\uE000\\([0-9]+\\)\uE001" nil t)
          (let ((start (match-beginning 0)))
            (replace-match (gethash (string-to-number (match-string 1)) slots) t t)
            (goto-char start)))
        (buffer-string)))))

(defun markdown-modern-export--inline-protect (stash)
  "Set aside code, math, raw HTML and escapes in the current buffer.
Each is replaced with a placeholder from the function STASH, which
takes the final HTML.  Escape other <, > and & characters.  Skip
the destination and title of inline links, which
`markdown-modern-export--inline-links' reads as written."
  (goto-char (point-min))
  (while (re-search-forward "[]\\`$<>&]" nil t)
    (let ((start (match-beginning 0))
          (char (char-before)))
      (goto-char start)
      (pcase char
        (?\]
         (if (looking-at (concat "\\]" markdown-modern-export--link-dest-re))
             (goto-char (match-end 0))
           (forward-char 1)))
        (?\\
         (cond
          ((looking-at "\\\\\\([!-/:-@[-`{-~]\\)")
           (replace-match (funcall stash (markdown-modern-export--escape-html
                                          (match-string 1)))
                          t t))
          ((looking-at "\\\\\n")
           (replace-match (concat (funcall stash "<br>") "\n") t t))
          (t (forward-char 1))))
        (?`
         (looking-at "`+")
         (let ((ticks (length (match-string 0)))
               (open-end (match-end 0))
               close)
           (goto-char open-end)
           (while (and (not close) (re-search-forward "`+" nil t))
             (when (= (- (match-end 0) (match-beginning 0)) ticks)
               (setq close (match-beginning 0))))
           (if (not close)
               (goto-char open-end)
             (let ((code (replace-regexp-in-string
                          "\n" " " (buffer-substring-no-properties open-end close))))
               (when (string-match-p "\\` .*[^ ].* \\'" code)
                 (setq code (substring code 1 -1)))
               (delete-region start (+ close ticks))
               (goto-char start)
               (insert (funcall stash
                                (format "<code>%s</code>"
                                        (markdown-modern-export--escape-html code))))))))
        (?$
         (cond
          ((looking-at "\\$\\$\\(?:[^$]\\|\\$[^$]\\)+?\\$\\$")
           (replace-match (funcall stash (format "<span class=\"math display\">%s</span>"
                                                 (markdown-modern-export--escape-html
                                                  (match-string 0))))
                          t t))
          ((looking-at "\\$[^$ \t\n]\\(?:[^$]*?[^$ \t\n\\]\\)?\\$\\([^0-9]\\|\\'\\)")
           (let* ((end (or (match-beginning 1) (match-end 0)))
                  (math (buffer-substring-no-properties start end)))
             (delete-region start end)
             (insert (funcall stash (format "<span class=\"math inline\">%s</span>"
                                            (markdown-modern-export--escape-html math))))))
          (t (forward-char 1))))
        (?<
         (cond
          ((looking-at "<!--\\(?:[^-]\\|-[^-]\\)*-->")
           (replace-match (funcall stash (match-string 0)) t t))
          ((looking-at "<\\([A-Za-z][A-Za-z0-9+.-]\\{1,31\\}:[^ \t\n<>]*\\)>")
           (let ((url (markdown-modern-export--escape-html (match-string 1))))
             (replace-match (funcall stash (format "<a href=\"%s\">%s</a>" url url)) t t)))
          ((looking-at "<\\([^ \t\n<>@\\]+@[^ \t\n<>\\]+\\)>")
           (let ((mail (markdown-modern-export--escape-html (match-string 1))))
             (replace-match (funcall stash (format "<a href=\"mailto:%s\">%s</a>" mail mail))
                            t t)))
          ((looking-at markdown-modern-export--tag-re)
           (replace-match (funcall stash (match-string 0)) t t))
          (t (delete-char 1)
             (insert "&lt;"))))
        (?>
         (delete-char 1)
         (insert "&gt;"))
        (?&
         (if (looking-at markdown-modern-export--entity-re)
             (goto-char (match-end 0))
           (delete-char 1)
           (insert "&amp;")))))))

(defun markdown-modern-export--normalize-label (label)
  "Return LABEL normalized for matching link references."
  (downcase (replace-regexp-in-string "[ \t\n]+" " " (string-trim label))))

(defun markdown-modern-export--attribute (text)
  "Return TEXT with its double quotes escaped for an HTML attribute."
  (string-replace "\"" "&quot;" text))

(defun markdown-modern-export--link-attribute (text)
  "Return the link destination or title TEXT as an HTML attribute value.
Backslash escapes give their character.  Escape <, >, double quotes
and any & that does not start an entity."
  (replace-regexp-in-string
   (concat markdown-modern-export--entity-re "\\|[&<>\"]")
   (lambda (match)
     (pcase match
       ("&" "&amp;")
       ("<" "&lt;")
       (">" "&gt;")
       ("\"" "&quot;")
       (_ match)))
   (replace-regexp-in-string "\\\\\\([!-/:-@[-`{-~]\\)" "\\1" text t)
   t t))

(defun markdown-modern-export--inline-spans (stash)
  "Render links and emphasis in the accessible part of the buffer.
Each link and emphasis span becomes a placeholder from the function
STASH."
  (markdown-modern-export--inline-links stash)
  (markdown-modern-export--emphasis stash))

(defun markdown-modern-export--inline-links (stash)
  "Convert links and images in the accessible part of the buffer to HTML.
Each becomes a placeholder from the function STASH.  The text of a
link is rendered on its own, so emphasis never pairs across the link."
  (goto-char (point-min))
  (while (re-search-forward "!?\\[" nil t)
    (let ((start (match-beginning 0))
          url title end text)
      (goto-char start)
      (if (not (looking-at "\\(!\\)?\\[\\(\\(?:[^][]\\|\\[[^][]*\\]\\)*\\)\\]"))
          (goto-char (1+ start))
        (let ((image (match-beginning 1))
              (text-end (match-end 0)))
          (setq text (match-string 2))
          (goto-char text-end)
          (cond
           ((looking-at markdown-modern-export--link-dest-re)
            (setq url (markdown-modern-export--link-attribute (match-string 1))
                  title (let ((title (or (match-string 2) (match-string 3))))
                          (and title (markdown-modern-export--link-attribute title)))
                  end (match-end 0)))
           (t
            (let* ((full (looking-at "\\[\\([^]]*\\)\\]"))
                   (label (if (and full (not (string-empty-p (match-string 1))))
                              (match-string 1)
                            text))
                   (ref (gethash (markdown-modern-export--normalize-label label)
                                 markdown-modern-export--link-refs)))
              (when ref
                (setq url (markdown-modern-export--escape-html (car ref))
                      title (and (cdr ref)
                                 (markdown-modern-export--escape-html (cdr ref)))
                      end (if full (match-end 0) text-end))))))
          (if (not url)
              (goto-char (1+ start))
            (let ((title-attr (if title (format " title=\"%s\"" title) "")))
              (if image
                  (progn
                    (delete-region start end)
                    (goto-char start)
                    (insert
                     (funcall stash
                              (format "<img src=\"%s\" alt=\"%s\"%s>"
                                      (if (and markdown-modern-export-embed-images
                                               (file-exists-p url))
                                          (markdown-modern-export--image-to-base64 url)
                                        url)
                                      (markdown-modern-export--attribute text)
                                      title-attr))))
                ;; Render the text on its own, between the brackets.
                (delete-region (1- text-end) end)
                (delete-region start (1+ start))
                (let (html)
                  (save-restriction
                    (narrow-to-region start (- text-end 2))
                    (markdown-modern-export--inline-spans stash)
                    (setq html (buffer-string))
                    (delete-region (point-min) (point-max)))
                  (goto-char start)
                  (insert (funcall stash (format "<a href=\"%s\"%s>%s</a>"
                                                 url title-attr html))))))))))))

(defconst markdown-modern-export--emphasis-delimiters
  '(("***" "<strong><em>" "</em></strong>")
    ("___" "<strong><em>" "</em></strong>" t)
    ("**" "<strong>" "</strong>")
    ("__" "<strong>" "</strong>" t)
    ("*" "<em>" "</em>")
    ("_" "<em>" "</em>" t)
    ("~~" "<del>" "</del>"))
  "Emphasis delimiters with their opening and closing tags, longest first.
A fourth element t means the delimiter must not touch a letter or
digit outside, so snake_case words stay as they are.")

(defun markdown-modern-export--emphasis (stash)
  "Render emphasis in the accessible part of the buffer.
A span runs from a delimiter to the first one that can close it.  Its
text must not start or end with whitespace or the delimiter's
character.  The text is rendered on its own and the span becomes a
placeholder from the function STASH, so spans found later nest around
it and never cross it."
  (pcase-dolist (`(,delim ,open ,close ,word-bound)
                 markdown-modern-export--emphasis-delimiters)
    (let* ((char (substring delim 0 1))
           (len (length delim))
           (quoted (regexp-quote delim))
           (span (format "\\(%s\\([^%s[:space:]]\\(?:[[:ascii:][:nonascii:]]*?[^%s[:space:]]\\)??\\)%s\\)"
                         quoted char char quoted))
           (re (if word-bound
                   (concat "\\(?:^\\|[^[:alnum:]_]\\)" span "\\(?:[^[:alnum:]_]\\|$\\)")
                 span)))
      (goto-char (point-min))
      (while (re-search-forward re nil t)
        (let ((start (match-beginning 1))
              (text-end (match-end 2))
              html)
          (delete-region text-end (match-end 1))
          (delete-region start (+ start len))
          (save-restriction
            (narrow-to-region start (- text-end len))
            (markdown-modern-export--emphasis stash)
            (setq html (buffer-string))
            (delete-region (point-min) (point-max)))
          (goto-char start)
          (insert (funcall stash (concat open html close))))))))

(defun markdown-modern-export--image-to-base64 (path)
  "Convert image at PATH to base64 data URI."
  (let* ((ext (file-name-extension path))
         (mime (pcase (downcase ext)
                 ((or "jpg" "jpeg") "image/jpeg")
                 ("png" "image/png")
                 ("gif" "image/gif")
                 ("svg" "image/svg+xml")
                 ("webp" "image/webp")
                 (_ "application/octet-stream")))
         (data (with-temp-buffer
                 (insert-file-contents-literally path)
                 (base64-encode-string (buffer-string) t))))
    (format "data:%s;base64,%s" mime data)))

(defun markdown-modern-export--heading-id (text)
  "Generate an ID from heading TEXT."
  (downcase (replace-regexp-in-string
             "[^a-zA-Z0-9]+" "-"
             (string-trim text))))

(defun markdown-modern-export--escape-html (text)
  "Escape HTML special characters in TEXT."
  (let ((result text))
    (setq result (replace-regexp-in-string "&" "&amp;" result))
    (setq result (replace-regexp-in-string "<" "&lt;" result))
    (setq result (replace-regexp-in-string ">" "&gt;" result))
    (setq result (replace-regexp-in-string "\"" "&quot;" result))
    result))

(provide 'markdown-modern-export)
;;; markdown-modern-export.el ends here
