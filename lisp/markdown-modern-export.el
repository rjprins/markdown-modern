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
    (user-error "Pandoc not found. Install Pandoc or set `markdown-modern-pandoc-executable'"))
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
         (title (or (markdown-modern-export--get-title)
                    (file-name-base output)))
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

(defun markdown-modern-export--markdown-to-html (markdown)
  "Convert MARKDOWN string to HTML."
  (with-temp-buffer
    (insert markdown)
    (goto-char (point-min))
    ;; Process in order: blocks first, then inline
    (markdown-modern-export--process-blocks)
    (markdown-modern-export--process-inline)
    (buffer-string)))

(defun markdown-modern-export--process-blocks ()
  "Process block-level elements in buffer."
  ;; Process code blocks first (to protect their contents)
  (markdown-modern-export--process-fenced-code-blocks)
  ;; Then other blocks
  (markdown-modern-export--process-headings)
  (markdown-modern-export--process-blockquotes)
  (markdown-modern-export--process-lists)
  (markdown-modern-export--process-tables)
  (markdown-modern-export--process-hrs)
  (markdown-modern-export--process-paragraphs))

(defun markdown-modern-export--process-inline ()
  "Process inline elements in buffer."
  ;; Process images BEFORE links (images use ![...] which contains link syntax)
  (markdown-modern-export--process-images)
  (markdown-modern-export--process-links)
  (markdown-modern-export--process-bold)
  (markdown-modern-export--process-italic)
  (markdown-modern-export--process-strikethrough)
  (markdown-modern-export--process-inline-code))

(defun markdown-modern-export--process-headings ()
  "Convert markdown headings to HTML."
  (goto-char (point-min))
  (while (re-search-forward "^\\(#\\{1,6\\}\\) +\\(.+\\)$" nil t)
    (let* ((level (length (match-string 1)))
           (text (match-string 2))
           (id (markdown-modern-export--heading-id text)))
      (replace-match (format "<h%d id=\"%s\">%s</h%d>" level id text level)))))

(defun markdown-modern-export--heading-id (text)
  "Generate an ID from heading TEXT."
  (downcase (replace-regexp-in-string
             "[^a-zA-Z0-9]+" "-"
             (string-trim text))))

(defun markdown-modern-export--process-fenced-code-blocks ()
  "Convert fenced code blocks to HTML."
  (goto-char (point-min))
  ;; Process fenced code blocks by finding pairs of ```
  (while (re-search-forward "^```\\([a-zA-Z0-9_+-]*\\)?$" nil t)
    (let ((lang (or (match-string 1) ""))
          (start (match-beginning 0))
          (code-start (1+ (match-end 0))))
      (when (re-search-forward "^```$" nil t)
        (let* ((code-end (match-beginning 0))
               (end (match-end 0))
               (code (buffer-substring-no-properties code-start code-end)))
          ;; Remove trailing newline from code if present
          (when (and (> (length code) 0) (eq (aref code (1- (length code))) ?\n))
            (setq code (substring code 0 -1)))
          (delete-region start end)
          (goto-char start)
          (insert (format "<pre><code%s>%s</code></pre>"
                          (if (string-empty-p lang) ""
                            (format " class=\"language-%s\"" lang))
                          (markdown-modern-export--escape-html code))))))))

(defun markdown-modern-export--process-blockquotes ()
  "Convert blockquotes to HTML."
  (goto-char (point-min))
  (while (re-search-forward "^\\(>+ ?\\(.+\\)\n?\\)+" nil t)
    (let ((start (match-beginning 0))
          (end (match-end 0)))
      (save-excursion
        (goto-char start)
        (let ((content ""))
          (while (and (< (point) end)
                      (looking-at "^> ?\\(.*\\)$"))
            (setq content (concat content (match-string 1) "\n"))
            (forward-line 1))
          (delete-region start (point))
          (insert (format "<blockquote>\n%s</blockquote>\n"
                         (string-trim content))))))))

(defun markdown-modern-export--process-lists ()
  "Convert lists to HTML."
  ;; Unordered lists - match lines starting with list markers
  (goto-char (point-min))
  (while (re-search-forward "^[ \t]*[-*+] .+" nil t)
    (beginning-of-line)
    (let ((start (point))
          (items '()))
      ;; Collect consecutive list items
      (while (and (not (eobp))
                  (looking-at "^[ \t]*[-*+] \\(.+\\)$"))
        (let ((item (match-string 1)))
          ;; Check for task list
          (if (string-match "^\\[\\([ xX]\\)\\] \\(.*\\)$" item)
              (let ((checked (not (string= (match-string 1 item) " ")))
                    (text (match-string 2 item)))
                (push (format "<li class=\"task-list-item\"><input type=\"checkbox\"%s disabled> %s</li>"
                              (if checked " checked" "")
                              text)
                      items))
            (push (format "<li>%s</li>" item) items)))
        (forward-line 1))
      (delete-region start (point))
      (insert (format "<ul>\n%s\n</ul>\n"
                      (string-join (nreverse items) "\n")))))
  ;; Ordered lists
  (goto-char (point-min))
  (while (re-search-forward "^[ \t]*[0-9]+[.)] .+" nil t)
    (beginning-of-line)
    (let ((start (point))
          (items '()))
      (while (and (not (eobp))
                  (looking-at "^[ \t]*[0-9]+[.)] \\(.+\\)$"))
        (push (format "<li>%s</li>" (match-string 1)) items)
        (forward-line 1))
      (delete-region start (point))
      (insert (format "<ol>\n%s\n</ol>\n"
                      (string-join (nreverse items) "\n"))))))

(defun markdown-modern-export--process-tables ()
  "Convert markdown tables to HTML."
  (goto-char (point-min))
  (while (re-search-forward "^|.+|" nil t)
    (beginning-of-line)
    (let ((start (point))
          (rows '())
          (is-header t))
      ;; Collect consecutive table rows
      (while (and (not (eobp))
                  (looking-at "^|\\(.+\\)|[ \t]*$"))
        (let* ((row-text (match-string 1))
               (cells (split-string row-text "|")))
          (if (string-match-p "^[-:|]+$" row-text)
              ;; Separator row - switch from header to body
              (setq is-header nil)
            ;; Data row
            (push (cons is-header cells) rows)))
        (forward-line 1))
      (delete-region start (point))
      (insert (markdown-modern-export--build-table (nreverse rows))))))

(defun markdown-modern-export--build-table (rows)
  "Build HTML table from ROWS list of (is-header . cells)."
  (let ((html "<table>\n")
        (in-tbody nil))
    (dolist (row rows)
      (let ((is-header (car row))
            (cells (cdr row)))
        (if is-header
            (progn
              (setq html (concat html "<thead>\n<tr>"))
              (dolist (cell cells)
                (setq html (concat html (format "<th>%s</th>" (string-trim cell)))))
              (setq html (concat html "</tr>\n</thead>\n")))
          (unless in-tbody
            (setq html (concat html "<tbody>\n"))
            (setq in-tbody t))
          (setq html (concat html "<tr>"))
          (dolist (cell cells)
            (setq html (concat html (format "<td>%s</td>" (string-trim cell)))))
          (setq html (concat html "</tr>\n")))))
    (when in-tbody
      (setq html (concat html "</tbody>\n")))
    (concat html "</table>\n")))

(defun markdown-modern-export--process-hrs ()
  "Convert horizontal rules to HTML."
  (goto-char (point-min))
  (while (re-search-forward "^\\(---+\\|\\*\\*\\*+\\|___+\\)$" nil t)
    (replace-match "<hr>")))

(defun markdown-modern-export--process-paragraphs ()
  "Wrap remaining text in <p> tags."
  (goto-char (point-min))
  (while (not (eobp))
    (cond
     ;; Skip HTML tags
     ((looking-at "^<")
      (forward-line 1))
     ;; Skip empty lines
     ((looking-at "^[ \t]*$")
      (forward-line 1))
     ;; Wrap text in paragraph
     (t
      (let ((start (point)))
        (while (and (not (eobp))
                    (not (looking-at "^[ \t]*$"))
                    (not (looking-at "^<")))
          (forward-line 1))
        (let ((text (string-trim (buffer-substring-no-properties start (point)))))
          (delete-region start (point))
          (insert (format "<p>%s</p>\n" text))))))))

;;; Inline Processing

(defun markdown-modern-export--process-links ()
  "Convert markdown links to HTML."
  (goto-char (point-min))
  (while (re-search-forward "\\[\\([^]]+\\)\\](\\([^)]+\\))" nil t)
    (let ((text (match-string 1))
          (url (match-string 2)))
      (replace-match (format "<a href=\"%s\">%s</a>" url text) t t))))

(defun markdown-modern-export--process-images ()
  "Convert markdown images to HTML."
  (goto-char (point-min))
  (while (re-search-forward "!\\[\\([^]]*\\)\\](\\([^)]+\\))" nil t)
    (let ((alt (match-string 1))
          (src (match-string 2)))
      (if (and markdown-modern-export-embed-images
               (file-exists-p src))
          ;; Embed as base64
          (let ((data (markdown-modern-export--image-to-base64 src)))
            (replace-match (format "<img src=\"%s\" alt=\"%s\">" data alt) t t))
        (replace-match (format "<img src=\"%s\" alt=\"%s\">" src alt) t t)))))

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

(defun markdown-modern-export--process-bold ()
  "Convert bold markup to HTML."
  (goto-char (point-min))
  (while (re-search-forward "\\*\\*\\([^*]+\\)\\*\\*\\|__\\([^_]+\\)__" nil t)
    (let ((text (or (match-string 1) (match-string 2))))
      (replace-match (format "<strong>%s</strong>" text) t t))))

(defun markdown-modern-export--process-italic ()
  "Convert italic markup to HTML."
  (goto-char (point-min))
  (while (re-search-forward "\\*\\([^*]+\\)\\*\\|_\\([^_]+\\)_" nil t)
    (let ((text (or (match-string 1) (match-string 2))))
      ;; Avoid matching already-processed bold
      (unless (or (string-prefix-p "strong>" text)
                  (string-suffix-p "</strong" text))
        (replace-match (format "<em>%s</em>" text) t t)))))

(defun markdown-modern-export--process-strikethrough ()
  "Convert strikethrough markup to HTML."
  (goto-char (point-min))
  (while (re-search-forward "~~\\([^~]+\\)~~" nil t)
    (replace-match (format "<del>%s</del>" (match-string 1)) t t)))

(defun markdown-modern-export--process-inline-code ()
  "Convert inline code to HTML."
  (goto-char (point-min))
  (while (re-search-forward "`\\([^`]+\\)`" nil t)
    (replace-match (format "<code>%s</code>"
                          (markdown-modern-export--escape-html (match-string 1)))
                  t t)))

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
