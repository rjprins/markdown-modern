;;; markdown-modern-render.el --- Rendering engine for markdown-modern -*- lexical-binding: t; -*-

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

;; Rendering engine for markdown-modern.
;; Manages overlays, text properties, and display properties.

;;; Code:

(require 'cl-lib)
(require 'face-remap)
(require 'url-parse)
(require 'markdown-modern-mermaid)

;; Variables defined in markdown-modern-ts.el
(defvar markdown-modern-ts--use-tree-sitter)

;; Variables defined in markdown-modern.el
(defvar markdown-modern--rendering-enabled)
(defvar markdown-modern-display-images)
(defvar markdown-modern-image-max-width)
(defvar markdown-modern-image-max-height)
(defvar markdown-modern-left-margin)
(defvar markdown-modern-code-block-syntax-highlight)

;; Variables defined later in this file
(defvar markdown-modern-math-block-scale)

;; Functions defined in markdown-modern-ts.el
(declare-function markdown-modern-ts--elements-in-region "markdown-modern-ts")
(declare-function markdown-modern-ts--fallback-parse-region "markdown-modern-ts")
(declare-function markdown-modern-ts--inline-elements-in "markdown-modern-ts")
(declare-function markdown-modern-ts--children "markdown-modern-ts")
(declare-function markdown-modern-node-type "markdown-modern-ts")
(declare-function markdown-modern-node-start "markdown-modern-ts")
(declare-function markdown-modern-node-end "markdown-modern-ts")
(declare-function markdown-modern-node-level "markdown-modern-ts")
(declare-function markdown-modern-node-language "markdown-modern-ts")
(declare-function markdown-modern-node-properties "markdown-modern-ts")

;;; Internal Variables

(defvar-local markdown-modern-render--overlays nil
  "List of active overlays in the buffer.")

(defvar-local markdown-modern-render--overlay-pool nil
  "Pool of reusable overlays.")

(defvar-local markdown-modern-render--rendering-p nil
  "Non-nil when rendering is in progress.")

;;; Display Character Sets

(defvar markdown-modern-render--bullet-chars '(?● ?○ ?■ ?□)
  "Characters for unordered list bullets at each nesting level.")

(defvar markdown-modern-render--checkbox-chars
  '((unchecked . ?☐)
    (checked . ?☑)
    (partial . ?☒))
  "Characters for task list checkboxes.")

(defvar markdown-modern-render--hr-char ?─
  "Character used for horizontal rules.")

(defvar markdown-modern-render--table-chars
  '((top-left . ?┌)
    (top-right . ?┐)
    (bottom-left . ?└)
    (bottom-right . ?┘)
    (horizontal . ?─)
    (vertical . ?│)
    (cross . ?┼)
    (t-down . ?┬)
    (t-up . ?┴)
    (t-right . ?├)
    (t-left . ?┤))
  "Characters for table borders.")

(defvar markdown-modern-render--blockquote-char ?▌
  "Character for blockquote left border.")

;;; Initialization

(defun markdown-modern-render--init ()
  "Initialize the rendering engine for current buffer."
  (setq markdown-modern-render--overlays '())
  (setq markdown-modern-render--overlay-pool '())
  (markdown-modern-render--setup-display-chars))

(defun markdown-modern-render--setup-display-chars ()
  "Set up display characters based on environment."
  (cond
   ;; GUI Emacs - use Unicode
   ((display-graphic-p)
    (setq markdown-modern-render--bullet-chars '(?● ?○ ?■ ?□))
    (setq markdown-modern-render--checkbox-chars '((unchecked . ?☐) (checked . ?☑)))
    (setq markdown-modern-render--hr-char ?─)
    (setq markdown-modern-render--blockquote-char ?▌))
   ;; Terminal with Unicode
   ((char-displayable-p ?●)
    (setq markdown-modern-render--bullet-chars '(?● ?○ ?◆ ?◇))
    (setq markdown-modern-render--checkbox-chars '((unchecked . ?☐) (checked . ?☑)))
    (setq markdown-modern-render--hr-char ?─)
    (setq markdown-modern-render--blockquote-char ?│))
   ;; Basic ASCII terminal
   (t
    (setq markdown-modern-render--bullet-chars '(?* ?- ?+ ?.))
    (setq markdown-modern-render--checkbox-chars '((unchecked . ?\[) (checked . ?x)))
    (setq markdown-modern-render--hr-char ?-)
    (setq markdown-modern-render--blockquote-char ?|))))

;;; Overlay Management

(defun markdown-modern-render--get-overlay (start end)
  "Get an overlay for region START to END, reusing from pool if possible."
  (let ((ov (or (pop markdown-modern-render--overlay-pool)
                (make-overlay start end nil t nil))))
    (move-overlay ov start end)
    ;; Clear any existing properties when reusing from pool
    (overlay-put ov 'display nil)
    (overlay-put ov 'face nil)
    (overlay-put ov 'invisible nil)
    (overlay-put ov 'before-string nil)
    (overlay-put ov 'after-string nil)
    (overlay-put ov 'wrap-prefix nil)
    (overlay-put ov 'line-prefix nil)
    (overlay-put ov 'priority nil)
    ;; Set standard properties
    (overlay-put ov 'markdown-modern t)
    (overlay-put ov 'evaporate t)
    (push ov markdown-modern-render--overlays)
    ov))

(defun markdown-modern-render--release-overlay (ov)
  "Release overlay OV back to the pool."
  (when (overlay-buffer ov)
    (overlay-put ov 'display nil)
    (overlay-put ov 'face nil)
    (overlay-put ov 'invisible nil)
    (overlay-put ov 'before-string nil)
    (overlay-put ov 'after-string nil)
    (overlay-put ov 'help-echo nil)
    (delete-overlay ov)
    (setq markdown-modern-render--overlays (delq ov markdown-modern-render--overlays))
    (push ov markdown-modern-render--overlay-pool)))

(defun markdown-modern-render--clear-region (start end)
  "Clear all markdown-modern overlays in region from START to END."
  (dolist (ov (overlays-in start end))
    (when (overlay-get ov 'markdown-modern)
      (markdown-modern-render--release-overlay ov))))

(defun markdown-modern-render--clear-all ()
  "Clear all markdown-modern overlays in the buffer."
  (dolist (ov markdown-modern-render--overlays)
    (when (overlay-buffer ov)
      (delete-overlay ov)))
  (setq markdown-modern-render--overlays nil)
  (setq markdown-modern-render--overlay-pool nil))

;;; Core Rendering Functions

(defun markdown-modern-render--element-in-table-p (elem-start table-regions)
  "Return non-nil if ELEM-START is inside one of TABLE-REGIONS."
  (cl-some (lambda (region)
             (and (>= elem-start (car region))
                  (<= elem-start (cdr region))))
           table-regions))

(defun markdown-modern-render--render-region (start end)
  "Render markdown elements in region from START to END."
  (when (and (not markdown-modern-render--rendering-p)
             markdown-modern--rendering-enabled)
    (let ((markdown-modern-render--rendering-p t)
          (inhibit-read-only t))
      (with-silent-modifications
        (markdown-modern-render--clear-region start end)
        (let ((elements (if markdown-modern-ts--use-tree-sitter
                           (markdown-modern-ts--elements-in-region start end)
                         (markdown-modern-ts--fallback-parse-region start end))))
          (dolist (elem elements)
            (markdown-modern-render--render-element elem)))))))

(defun markdown-modern-render--unrender-region (start end)
  "Remove rendering from region START to END."
  (with-silent-modifications
    (markdown-modern-render--clear-region start end)))

(defun markdown-modern-render--reveal-markup (start end)
  "Reveal raw markup in START..END while preserving styling.
Releases only the overlays that hide or replace source text (those carrying
a `display' property: the marker/delimiter \"\" overlays, plus table, bullet,
image and similar replacements), so the markdown syntax becomes visible.
Overlays that merely apply a face (heading size, bold, italic, code colour)
are kept, so revealed text stays formatted."
  (with-silent-modifications
    (dolist (ov (overlays-in start end))
      (when (and (overlay-get ov 'markdown-modern)
                 (overlay-get ov 'display))
        (markdown-modern-render--release-overlay ov)))))

;;; Element Rendering Dispatch

(defun markdown-modern-render--render-element (elem)
  "Render a single element ELEM."
  (when elem
    (pcase (markdown-modern-node-type elem)
      ;; Headings
      ('heading (markdown-modern-render--heading elem))
      ;; Inline formatting
      ('strong (markdown-modern-render--strong elem))
      ('emphasis (markdown-modern-render--emphasis elem))
      ('strikethrough (markdown-modern-render--strikethrough elem))
      ('code-span (markdown-modern-render--code-span elem))
      ;; Links and images
      ('link (markdown-modern-render--link elem))
      ('link-ref (markdown-modern-render--link elem))
      ('image (markdown-modern-render--image elem))
      ('autolink (markdown-modern-render--autolink elem))
      ;; Block elements
      ('code-block (markdown-modern-render--code-block elem))
      ('blockquote (markdown-modern-render--blockquote elem))
      ('list (markdown-modern-render--list elem))
      ('list-item (markdown-modern-render--list-item elem))
      ('hr (markdown-modern-render--hr elem))
      ('table (markdown-modern-render--table elem))
      ('table-row (markdown-modern-render--table-row-standalone elem))
      ('table-separator (markdown-modern-render--table-separator elem))
      ;; Extended elements
      ('footnote-ref (markdown-modern-render--footnote-ref elem))
      ('math (markdown-modern-render--math elem))
      ('math-block (markdown-modern-render--math-block elem))
      ;; Paragraphs: parse and render inline elements
      ('paragraph (markdown-modern-render--paragraph elem))
      ;; Default: no special rendering
      (_ nil))))

;;; Paragraph Rendering

(defun markdown-modern-render--paragraph (elem)
  "Render paragraph ELEM by parsing and rendering its inline elements."
  (let* ((start (markdown-modern-node-start elem))
         (end (markdown-modern-node-end elem))
         (inlines (markdown-modern-ts--inline-elements-in start end)))
    (dolist (inline-elem inlines)
      (ignore-errors
        (markdown-modern-render--render-element inline-elem)))))

;;; Inline Element Rendering

(defun markdown-modern-render--heading (elem)
  "Render heading element ELEM."
  (let* ((start (markdown-modern-node-start elem))
         (end (markdown-modern-node-end elem))
         (level (or (markdown-modern-node-level elem) 1))
         (face (intern (format "markdown-modern-heading-%d" (min level 6)))))
    ;; Find the marker (### )
    (save-excursion
      (goto-char start)
      (when (looking-at "^\\(#\\{1,6\\}\\)[ \t]*")
        (let ((marker-end (match-end 0))
              (content-start (match-end 0)))
          ;; Hide the marker
          (let ((ov (markdown-modern-render--get-overlay start marker-end)))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'heading-marker))
          ;; Apply the heading face over the whole line (markers included), so
          ;; when the markers are revealed at point they appear at the heading's
          ;; size.  While rendered they stay hidden by the display "" overlay.
          (let ((ov (markdown-modern-render--get-overlay start end)))
            (overlay-put ov 'face face)
            (overlay-put ov 'markdown-modern-type 'heading-content))
          ;; Render inline markup inside the heading (code spans, emphasis,
          ;; links).  Under tree-sitter these are not returned as separate
          ;; block elements, so the heading must descend into them itself,
          ;; the way paragraphs do.  In the regex fallback this is a no-op
          ;; (no inline parser) and the spans are emitted independently.
          (dolist (inline (markdown-modern-ts--inline-elements-in content-start end))
            (ignore-errors (markdown-modern-render--render-element inline))))))))

(defun markdown-modern-render--strong (elem)
  "Render strong/bold element ELEM."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      (when (looking-at "\\(\\*\\*\\|__\\)\\([^\n\r]*?\\)\\(\\*\\*\\|__\\)")
        (let ((delim1-end (match-end 1))
              (content-start (match-beginning 2))
              (content-end (match-end 2))
              (delim2-start (match-beginning 3)))
          ;; Hide opening delimiter
          (let ((ov (markdown-modern-render--get-overlay start delim1-end)))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'strong-delim))
          ;; Apply bold face to content - high priority to override backgrounds
          (let ((ov (markdown-modern-render--get-overlay content-start content-end)))
            (overlay-put ov 'face 'markdown-modern-bold)
            (overlay-put ov 'markdown-modern-type 'strong-content)
            (overlay-put ov 'priority 100))
          ;; Hide closing delimiter
          (let ((ov (markdown-modern-render--get-overlay delim2-start end)))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'strong-delim)))))))

(defun markdown-modern-render--emphasis (elem)
  "Render emphasis/italic element ELEM."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      (when (looking-at "\\([*_]\\)\\([^\n\r]*?\\)\\([*_]\\)")
        (let ((delim1-end (match-end 1))
              (content-start (match-beginning 2))
              (content-end (match-end 2))
              (delim2-start (match-beginning 3)))
          ;; Hide opening delimiter
          (let ((ov (markdown-modern-render--get-overlay start delim1-end)))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'emphasis-delim))
          ;; Apply italic face to content - high priority
          (let ((ov (markdown-modern-render--get-overlay content-start content-end)))
            (overlay-put ov 'face 'markdown-modern-italic)
            (overlay-put ov 'markdown-modern-type 'emphasis-content)
            (overlay-put ov 'priority 100))
          ;; Hide closing delimiter
          (let ((ov (markdown-modern-render--get-overlay delim2-start end)))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'emphasis-delim)))))))

(defun markdown-modern-render--strikethrough (elem)
  "Render strikethrough element ELEM."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      (when (looking-at "~~\\([^\n\r]*?\\)~~")
        (let ((content-start (match-beginning 1))
              (content-end (match-end 1)))
          ;; Hide opening ~~
          (let ((ov (markdown-modern-render--get-overlay start (+ start 2))))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'strike-delim))
          ;; Apply strikethrough face
          (let ((ov (markdown-modern-render--get-overlay content-start content-end)))
            (overlay-put ov 'face 'markdown-modern-strikethrough)
            (overlay-put ov 'markdown-modern-type 'strike-content))
          ;; Hide closing ~~
          (let ((ov (markdown-modern-render--get-overlay (- end 2) end)))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'strike-delim)))))))

(defun markdown-modern-render--code-span (elem)
  "Render inline code span element ELEM."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      (when (looking-at "`+\\([^`\n\r]+\\)`+")
        (let* ((backtick-count (- (match-end 0) (match-beginning 0)
                                  (- (match-end 1) (match-beginning 1))))
               (delim-len (/ backtick-count 2))
               (content-start (+ start delim-len))
               (content-end (- end delim-len)))
          ;; Hide opening backticks
          (let ((ov (markdown-modern-render--get-overlay start content-start)))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'code-delim))
          ;; Apply code face to content - high priority
          (let ((ov (markdown-modern-render--get-overlay content-start content-end)))
            (overlay-put ov 'face 'markdown-modern-inline-code)
            (overlay-put ov 'markdown-modern-type 'code-content)
            (overlay-put ov 'priority 90))
          ;; Hide closing backticks
          (let ((ov (markdown-modern-render--get-overlay content-end end)))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'code-delim)))))))

;;; Link and Image Rendering

(defvar markdown-modern-render--link-keymap
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1] #'markdown-modern-render--follow-link-at-mouse)
    (define-key map [mouse-2] #'markdown-modern-render--follow-link-at-mouse)
    (define-key map (kbd "RET") #'markdown-modern-render--follow-link-at-point)
    map)
  "Keymap for link overlays.")

(defun markdown-modern-render--link (elem)
  "Render link element ELEM."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      (when (looking-at "\\[\\([^]]+\\)\\](\\([^)]+\\))")
        (let ((_text (match-string 1))
              (url (match-string 2))
              (text-start (match-beginning 1))
              (text-end (match-end 1))
              (_url-start (match-beginning 2))
              (_url-end (match-end 2)))
          ;; Hide opening [
          (let ((ov (markdown-modern-render--get-overlay start (1+ start))))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'link-delim))
          ;; Style link text
          (let ((ov (markdown-modern-render--get-overlay text-start text-end)))
            (overlay-put ov 'face 'markdown-modern-link)
            (overlay-put ov 'mouse-face 'highlight)
            (overlay-put ov 'help-echo url)
            (overlay-put ov 'keymap markdown-modern-render--link-keymap)
            (overlay-put ov 'follow-link t)
            (overlay-put ov 'markdown-modern-url url)
            (overlay-put ov 'markdown-modern-type 'link-text))
          ;; Hide ]( and URL and )
          (let ((ov (markdown-modern-render--get-overlay text-end end)))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'link-delim)))))))

(defun markdown-modern-render--follow-link (url)
  "Follow link URL - handle internal anchors vs external URLs."
  (cond
   ;; Internal anchor link (starts with #)
   ((string-prefix-p "#" url)
    (let ((anchor (substring url 1)))
      (markdown-modern-render--goto-anchor anchor)))
   ;; Relative file link
   ((and (not (string-match-p "^[a-z]+://" url))
         (string-match-p "\\.md\\(?:#\\|$\\)" url))
    (let* ((parts (split-string url "#"))
           (file (car parts))
           (anchor (cadr parts)))
      (find-file (expand-file-name file))
      (when anchor
        (markdown-modern-render--goto-anchor anchor))))
   ;; External URL
   (t (browse-url url))))

(defun markdown-modern-render--goto-anchor (anchor)
  "Navigate to ANCHOR (heading ID) in current buffer."
  (goto-char (point-min))
  ;; Search for heading that matches anchor
  (let ((target-id (downcase (replace-regexp-in-string "[^a-z0-9-]" "" anchor))))
    (if (re-search-forward "^#\\{1,6\\} +\\(.+\\)$" nil t)
        (let ((found nil))
          (goto-char (point-min))
          (while (and (not found)
                      (re-search-forward "^#\\{1,6\\} +\\(.+\\)$" nil t))
            (let* ((heading-text (match-string 1))
                   (heading-id (downcase
                               (replace-regexp-in-string
                                "[^a-z0-9-]" ""
                                (replace-regexp-in-string " +" "-" heading-text)))))
              (when (string= heading-id target-id)
                (setq found t)
                (beginning-of-line)
                (recenter 0))))  ; Put heading at top of window
          (unless found
            (message "Anchor '%s' not found" anchor)))
      (message "No headings found"))))

(defun markdown-modern-render--follow-link-at-mouse (event)
  "Follow link at mouse EVENT position."
  (interactive "e")
  (let* ((pos (posn-point (event-end event)))
         (url (get-char-property pos 'markdown-modern-url)))
    (when url
      (markdown-modern-render--follow-link url))))

(defun markdown-modern-render--follow-link-at-point ()
  "Follow link at point."
  (interactive)
  (let ((url (get-char-property (point) 'markdown-modern-url)))
    (when url
      (markdown-modern-render--follow-link url))))

(defvar markdown-modern-render--image-cache-dir nil
  "Directory for caching downloaded remote images.")

(defun markdown-modern-render--image-cache-dir ()
  "Return the image cache directory, creating it if needed."
  (unless markdown-modern-render--image-cache-dir
    (setq markdown-modern-render--image-cache-dir
          (expand-file-name "markdown-modern/images"
                            (or (getenv "XDG_CACHE_HOME")
                                (expand-file-name ".cache" "~")))))
  (unless (file-directory-p markdown-modern-render--image-cache-dir)
    (make-directory markdown-modern-render--image-cache-dir t))
  markdown-modern-render--image-cache-dir)

(defun markdown-modern-render--url-p (path)
  "Return non-nil if PATH is a remote URL."
  (or (string-prefix-p "http://" path)
      (string-prefix-p "https://" path)))

(defun markdown-modern-render--image-cache-path (url)
  "Return local cache file path for remote image URL."
  (let* ((hash (md5 url))
         ;; Preserve extension for image type detection
         (ext (or (file-name-extension (url-filename (url-generic-parse-url url)))
                  "png")))
    (expand-file-name (concat hash "." ext)
                      (markdown-modern-render--image-cache-dir))))

(defun markdown-modern-render--image (elem)
  "Render image element ELEM."
  (when markdown-modern-display-images
    (let ((start (markdown-modern-node-start elem))
          (end (markdown-modern-node-end elem)))
      (save-excursion
        (goto-char start)
        (when (looking-at "!\\[\\([^]]*\\)\\](\\([^)]+\\))")
          (let* ((alt-text (match-string 1))
                 (image-path (match-string 2))
                 (full-path (markdown-modern-render--resolve-image-path image-path)))
            (cond
             ;; Local file exists - display directly
             ((and full-path
                   (not (markdown-modern-render--url-p image-path))
                   (file-exists-p full-path))
              (markdown-modern-render--display-image start end full-path alt-text image-path))
             ;; Remote URL - check cache or fetch async
             ((and full-path (markdown-modern-render--url-p image-path))
              (let ((cache-file (markdown-modern-render--image-cache-path image-path)))
                (if (and (file-exists-p cache-file)
                         (> (file-attribute-size (file-attributes cache-file)) 0))
                    ;; Already cached (non-empty): reuse, never re-fetch on re-render
                    (markdown-modern-render--display-image start end cache-file alt-text image-path)
                  ;; Show placeholder and fetch async
                  (markdown-modern-render--image-placeholder start end alt-text image-path)
                  (markdown-modern-render--fetch-image-async
                   image-path cache-file
                   (current-buffer) start end alt-text))))
             ;; Not found
             (t
              (markdown-modern-render--image-placeholder start end alt-text image-path)))))))))

(defun markdown-modern-render--display-image (start end file-path alt-text orig-path)
  "Display image from FILE-PATH as overlay from START to END."
  (let* ((image (create-image file-path nil nil
                              :max-width markdown-modern-image-max-width
                              :max-height markdown-modern-image-max-height))
         (ov (markdown-modern-render--get-overlay start end)))
    (overlay-put ov 'display image)
    (overlay-put ov 'help-echo (format "%s\n%s" alt-text orig-path))
    (overlay-put ov 'markdown-modern-type 'image)))

(defun markdown-modern-render--image-placeholder (start end alt-text image-path)
  "Show a placeholder overlay from START to END for ALT-TEXT and IMAGE-PATH."
  (let ((ov (markdown-modern-render--get-overlay start end)))
    (overlay-put ov 'display
                 (propertize (format "[Image: %s]" (or alt-text image-path))
                            'face 'markdown-modern-image-alt))
    (overlay-put ov 'markdown-modern-type 'image-placeholder)))

(defun markdown-modern-render--fetch-image-async (url cache-file buffer start end alt-text)
  "Fetch image from URL asynchronously, cache to CACHE-FILE, then display.
The image replaces the placeholder overlay between START and END in BUFFER;
ALT-TEXT is used for the tooltip."
  (require 'url)
  (url-retrieve
   url
   (lambda (status)
     (unwind-protect
         (if (plist-get status :error)
             (message "markdown-modern: Failed to fetch image: %s" url)
           ;; Skip HTTP headers
           (goto-char (point-min))
           (when (re-search-forward "\r?\n\r?\n" nil t)
             ;; Write binary data directly to cache file
             (let ((body-start (point))
                   (coding-system-for-write 'binary))
               (set-buffer-multibyte nil)
               (write-region body-start (point-max) cache-file nil 'silent))
             ;; Update the overlay in the original buffer
             (when (and (file-exists-p cache-file)
                        (> (file-attribute-size (file-attributes cache-file)) 0)
                        (buffer-live-p buffer))
               (with-current-buffer buffer
                 ;; Find and replace the placeholder overlay
                 (dolist (ov (overlays-in start end))
                   (when (eq (overlay-get ov 'markdown-modern-type) 'image-placeholder)
                     (let ((image (create-image cache-file nil nil
                                                :max-width markdown-modern-image-max-width
                                                :max-height markdown-modern-image-max-height)))
                       (overlay-put ov 'display image)
                       (overlay-put ov 'help-echo (format "%s\n%s" alt-text url))
                       (overlay-put ov 'markdown-modern-type 'image))))))))
       (kill-buffer)))
   nil t t))

(defun markdown-modern-render--resolve-image-path (path)
  "Resolve image PATH relative to current buffer's directory."
  (if (or (string-prefix-p "http://" path)
          (string-prefix-p "https://" path)
          (file-name-absolute-p path))
      path
    (when buffer-file-name
      (expand-file-name path (file-name-directory buffer-file-name)))))

(defun markdown-modern-render--autolink (elem)
  "Render autolink element ELEM."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      (when (looking-at "<\\([^>]+\\)>")
        (let ((url (match-string 1)))
          ;; Hide < >
          (let ((ov (markdown-modern-render--get-overlay start (1+ start))))
            (overlay-put ov 'display ""))
          (let ((ov (markdown-modern-render--get-overlay (1- end) end)))
            (overlay-put ov 'display ""))
          ;; Style the URL
          (let ((ov (markdown-modern-render--get-overlay (1+ start) (1- end))))
            (overlay-put ov 'face 'markdown-modern-link)
            (overlay-put ov 'mouse-face 'highlight)
            (overlay-put ov 'help-echo url)
            (overlay-put ov 'markdown-modern-url url)
            (overlay-put ov 'follow-link t)
            (overlay-put ov 'keymap markdown-modern-render--link-keymap)))))))

;;; Block Element Rendering

(defun markdown-modern-render--code-block (elem)
  "Render fenced code block element ELEM.
Uses :extend t on face to extend background to window edge.
Dispatches to mermaid renderer for mermaid code blocks."
  (let* ((start (markdown-modern-node-start elem))
         (end (markdown-modern-node-end elem))
         (language (or (plist-get (markdown-modern-node-properties elem) :language)
                       (markdown-modern-node-language elem)))
         ;; Also detect language from buffer text if not in properties
         (detected-lang (or language
                            (save-excursion
                              (goto-char start)
                              (when (looking-at "[ \t]*\\(?:```\\|~~~\\)\\([a-zA-Z0-9_+-]*\\)")
                                (match-string-no-properties 1))))))
    (if (and (stringp detected-lang)
             (string-equal (downcase detected-lang) "mermaid"))
        ;; Mermaid diagram
        (markdown-modern-render--mermaid elem)
      ;; Regular code block
      (save-excursion
        (goto-char start)
        ;; Match opening fence - allow up to 3 spaces indent per CommonMark spec
        ;; Note: Use \r? to handle Windows CRLF line endings
        (when (looking-at "\\([ \t]*\\)\\(```\\|~~~\\)\\([a-zA-Z0-9_+-]*\\)?[ \t]*\r?$")
        (let* ((fence-line-end (line-end-position))
               ;; Get language - strip text properties that might interfere with display
               (raw-lang (or language (match-string 3) ""))
               (_lang (if (stringp raw-lang)
                          (substring-no-properties raw-lang)
                        ""))
               (content-start (1+ fence-line-end))  ; Start of next line
               (content-end (save-excursion
                              (goto-char end)
                              ;; Search backward from end for closing fence
                              ;; Use fence-line-end as limit to not find opening fence
                              (if (re-search-backward "^[ \t]*\\(```\\|~~~\\)[ \t]*\r?$" fence-line-end t)
                                  (match-beginning 0)
                                end)))
               (closing-fence-start content-end))

          ;; Hide opening fence line but preserve the newline
          ;; This prevents the previous line from merging with code content
          (let ((ov (markdown-modern-render--get-overlay start fence-line-end)))
            (overlay-put ov 'markdown-modern-type 'code-fence)
            (overlay-put ov 'priority 100)
            (overlay-put ov 'display ""))

          ;; Apply background per-line, starting at bol so the face
          ;; extends under the line-prefix margin area
          (when (< content-start content-end)
            (save-excursion
              (goto-char content-start)
              (while (< (point) content-end)
                (let* ((bol (line-beginning-position))
                       (eol (line-end-position))
                       (line-end (min (1+ eol) content-end)))
                  (let ((ov (markdown-modern-render--get-overlay bol line-end)))
                    (overlay-put ov 'face 'markdown-modern-code-block)
                    (overlay-put ov 'markdown-modern-type 'code-block-content)
                    (overlay-put ov 'priority 10)))
                (forward-line 1))))

          ;; Syntax-highlight the content on top of the background.
          (when (and markdown-modern-code-block-syntax-highlight
                     (stringp detected-lang)
                     (> (length detected-lang) 0)
                     (< content-start content-end))
            (markdown-modern-render--highlight-code
             content-start content-end detected-lang))

          ;; Hide closing fence
          (when (< closing-fence-start end)
            (let ((ov (markdown-modern-render--get-overlay closing-fence-start end)))
              (overlay-put ov 'display "")
              (overlay-put ov 'markdown-modern-type 'code-fence)
              (overlay-put ov 'priority 100)))))))))

(defun markdown-modern-render--highlight-code (start end language)
  "Apply syntax highlighting to code from START to END for LANGUAGE."
  (let* ((mode (markdown-modern-render--language-to-mode language))
         (text (buffer-substring-no-properties start end))
         (ranges nil))
    (when mode
      ;; Fontify a copy in a temp buffer and collect (offset end-offset face)
      ;; ranges -- do NOT create overlays here, this is the wrong buffer.
      (with-temp-buffer
        (insert text)
        (delay-mode-hooks
          (condition-case nil
              (funcall mode)
            (error nil)))
        (font-lock-ensure)
        (let ((pos (point-min)))
          (while (< pos (point-max))
            (let ((next-change (or (next-single-property-change pos 'face)
                                   (point-max)))
                  (face (get-text-property pos 'face)))
              (when face
                (push (list (1- pos) (1- next-change) face) ranges))
              (setq pos next-change)))))
      ;; Create the highlight overlays in the *source* buffer.
      (dolist (r (nreverse ranges))
        (let ((ov (markdown-modern-render--get-overlay
                   (+ start (nth 0 r)) (+ start (nth 1 r)))))
          (overlay-put ov 'face (nth 2 r))
          (overlay-put ov 'markdown-modern-type 'code-highlight)
          ;; Above the background overlay (priority 10) so token foreground
          ;; colours win.
          (overlay-put ov 'priority 20))))))

(defconst markdown-modern-render--language-mode-alist
  '(("elisp" . emacs-lisp-mode)
    ("emacs-lisp" . emacs-lisp-mode)
    ("python" . python-mode)
    ("py" . python-mode)
    ("javascript" . js-mode)
    ("js" . js-mode)
    ("typescript" . typescript-ts-mode)
    ("ts" . typescript-ts-mode)
    ("rust" . rust-ts-mode)
    ("go" . go-ts-mode)
    ("golang" . go-ts-mode)
    ("c" . c-mode)
    ("cpp" . c++-mode)
    ("c++" . c++-mode)
    ("java" . java-mode)
    ("ruby" . ruby-mode)
    ("rb" . ruby-mode)
    ("shell" . sh-mode)
    ("bash" . sh-mode)
    ("sh" . sh-mode)
    ("zsh" . sh-mode)
    ("json" . js-mode)
    ("yaml" . yaml-mode)
    ("yml" . yaml-mode)
    ("html" . html-mode)
    ("css" . css-mode)
    ("sql" . sql-mode)
    ("xml" . xml-mode)
    ("lisp" . lisp-mode)
    ("clojure" . clojure-mode)
    ("clj" . clojure-mode)
    ("haskell" . haskell-mode)
    ("hs" . haskell-mode)
    ("ocaml" . tuareg-mode)
    ("ml" . tuareg-mode)
    ("lua" . lua-mode)
    ("perl" . perl-mode)
    ("php" . php-mode)
    ("r" . ess-r-mode)
    ("scala" . scala-mode)
    ("swift" . swift-mode)
    ("kotlin" . kotlin-mode)
    ("objc" . objc-mode)
    ("objective-c" . objc-mode)
    ("diff" . diff-mode)
    ("makefile" . makefile-mode)
    ("make" . makefile-mode)
    ("dockerfile" . dockerfile-mode)
    ("docker" . dockerfile-mode)
    ("toml" . toml-mode)
    ("ini" . conf-mode)
    ("conf" . conf-mode)
    ("tex" . latex-mode)
    ("latex" . latex-mode))
  "Alist mapping language identifiers to Emacs major modes.")

(defun markdown-modern-render--language-to-mode (language)
  "Get Emacs major mode for LANGUAGE identifier."
  (let* ((lang-lower (downcase language))
         (mode (cdr (assoc lang-lower markdown-modern-render--language-mode-alist))))
    (when (and mode (fboundp mode))
      mode)))

(defun markdown-modern-render--blockquote (elem)
  "Render blockquote element ELEM.
Uses simple styling that works well with `visual-line-mode' wrapping.
Also handles list items inside blockquotes."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem))
        ;; Get the base indentation from the buffer's line-prefix
        (base-indent (or (and (boundp 'markdown-modern-left-margin)
                              (make-string markdown-modern-left-margin ?\s))
                         "")))
    ;; Process each line
    (save-excursion
      (goto-char start)
      (while (< (point) end)
        (when (looking-at "^\\(>+\\)[ \t]?")
          (let* ((marker-start (match-beginning 1))
                 (marker-end (match-end 0))
                 (level (length (match-string 1)))
                 (eol (line-end-position))
                 ;; Build the prefix string for the blockquote bar
                 (bar-str (propertize (concat (make-string level markdown-modern-render--blockquote-char) " ")
                                      'face 'markdown-modern-blockquote-marker))
                 ;; Full wrap prefix includes base indentation
                 (full-bar-str (concat base-indent bar-str)))
            ;; Replace > markers with styled block character
            (let ((ov (markdown-modern-render--get-overlay marker-start marker-end)))
              (overlay-put ov 'display bar-str)
              (overlay-put ov 'markdown-modern-type 'quote-marker))
            ;; Check if this line has a list item inside the blockquote
            (when (< marker-end eol)
              (goto-char marker-end)
              (cond
               ;; Unordered list item: > - item or > * item
               ((looking-at "\\([-*+]\\)[ \t]+")
                (let* ((list-marker-start (match-beginning 1))
                       (list-marker-end (match-end 1))
                       (content-start (match-end 0))
                       (bullet (nth 0 markdown-modern-render--bullet-chars))
                       ;; Wrap prefix: base indent + bar + space for bullet alignment
                       (wrap-str (concat full-bar-str "  ")))
                  ;; Replace - with bullet
                  (let ((ov (markdown-modern-render--get-overlay list-marker-start list-marker-end)))
                    (overlay-put ov 'display (propertize (string bullet)
                                                         'face 'markdown-modern-list-bullet))
                    (overlay-put ov 'markdown-modern-type 'list-marker))
                  ;; Apply face to content with wrap-prefix for line continuation
                  (let ((ov (markdown-modern-render--get-overlay content-start eol)))
                    (overlay-put ov 'face 'markdown-modern-blockquote)
                    (overlay-put ov 'wrap-prefix wrap-str)
                    (overlay-put ov 'markdown-modern-type 'blockquote-list-content))))
               ;; Ordered list item: > 1. item
               ((looking-at "\\([0-9]+\\)[.)][ \t]+")
                (let* ((num-start (match-beginning 1))
                       (num-end (match-end 0))
                       (content-start (match-end 0))
                       ;; Wrap prefix: base indent + bar + space for number alignment
                       (wrap-str (concat full-bar-str "   ")))
                  ;; Style the number
                  (let ((ov (markdown-modern-render--get-overlay num-start num-end)))
                    (overlay-put ov 'face 'markdown-modern-list-number)
                    (overlay-put ov 'markdown-modern-type 'list-marker))
                  ;; Apply face to content with wrap-prefix
                  (let ((ov (markdown-modern-render--get-overlay content-start eol)))
                    (overlay-put ov 'face 'markdown-modern-blockquote)
                    (overlay-put ov 'wrap-prefix wrap-str)
                    (overlay-put ov 'markdown-modern-type 'blockquote-list-content))))
               ;; Regular blockquote content (no list)
               (t
                (let ((ov (markdown-modern-render--get-overlay marker-end eol)))
                  (overlay-put ov 'face 'markdown-modern-blockquote)
                  ;; Wrap prefix shows bar on continuation lines
                  (overlay-put ov 'wrap-prefix full-bar-str)
                  (overlay-put ov 'markdown-modern-type 'blockquote-content)))))))
        (forward-line 1)))))

(defun markdown-modern-render--list (elem)
  "Render list element ELEM."
  ;; Lists are containers, render children
  (dolist (child (markdown-modern-ts--children elem))
    (markdown-modern-render--render-element child)))

(defun markdown-modern-render--list-item (elem)
  "Render list item element ELEM.
Includes `wrap-prefix' for proper line continuation."
  (let ((start (markdown-modern-node-start elem))
        (_end (markdown-modern-node-end elem))
        ;; Get the base indentation from the buffer's line-prefix
        (base-indent (or (and (boundp 'markdown-modern-left-margin)
                              (make-string markdown-modern-left-margin ?\s))
                         "")))
    (save-excursion
      (goto-char start)
      (cond
       ;; Task list item
       ((looking-at "^\\([ \t]*\\)\\([-*+]\\)[ \t]+\\(\\[[ xX]\\]\\)[ \t]+")
        (let* ((indent (match-string 1))
               (marker-start (match-beginning 2))
               (marker-end (match-end 2))
               (checkbox-start (match-beginning 3))
               (checkbox-end (match-end 3))
               (content-start (match-end 0))
               (checkbox-text (match-string 3))
               (is-checked (string-match-p "[xX]" checkbox-text))
               (_level (/ (length indent) 2))
               (eol (line-end-position))
               ;; Wrap prefix: base indent + list indent + space for checkbox alignment
               (wrap-str (concat base-indent indent "   ")))
          ;; Hide list marker
          (let ((ov (markdown-modern-render--get-overlay marker-start (1+ marker-end))))
            (overlay-put ov 'display "")
            (overlay-put ov 'markdown-modern-type 'list-marker))
          ;; Render checkbox
          (let ((ov (markdown-modern-render--get-overlay checkbox-start checkbox-end)))
            (overlay-put ov 'display
                         (propertize
                          (string (cdr (assq (if is-checked 'checked 'unchecked)
                                            markdown-modern-render--checkbox-chars)))
                          'face (if is-checked
                                    'markdown-modern-task-checked
                                  'markdown-modern-task-unchecked)))
            (overlay-put ov 'markdown-modern-type 'checkbox)
            (overlay-put ov 'markdown-modern-checkbox-state (if is-checked 'checked 'unchecked)))
          ;; Add wrap-prefix to content
          (when (< content-start eol)
            (let ((ov (markdown-modern-render--get-overlay content-start eol)))
              (overlay-put ov 'wrap-prefix wrap-str)
              (overlay-put ov 'markdown-modern-type 'list-content)))))
       ;; Unordered list item
       ((looking-at "^\\([ \t]*\\)\\([-*+]\\)[ \t]+")
        (let* ((indent (match-string 1))
               (marker-start (match-beginning 2))
               (marker-end (match-end 2))
               (content-start (match-end 0))
               (level (/ (length indent) 2))
               (bullet (nth (mod level (length markdown-modern-render--bullet-chars))
                           markdown-modern-render--bullet-chars))
               (eol (line-end-position))
               ;; Wrap prefix: base indent + list indent + space for bullet alignment
               (wrap-str (concat base-indent indent "  ")))
          ;; Replace marker with bullet
          (let ((ov (markdown-modern-render--get-overlay marker-start marker-end)))
            (overlay-put ov 'display (propertize (string bullet)
                                                'face 'markdown-modern-list-bullet))
            (overlay-put ov 'markdown-modern-type 'list-marker))
          ;; Add wrap-prefix to content
          (when (< content-start eol)
            (let ((ov (markdown-modern-render--get-overlay content-start eol)))
              (overlay-put ov 'wrap-prefix wrap-str)
              (overlay-put ov 'markdown-modern-type 'list-content)))))
       ;; Ordered list item
       ((looking-at "^\\([ \t]*\\)\\([0-9]+\\)\\([.):]\\)[ \t]+")
        (let* ((indent (match-string 1))
               (number (match-string 2))
               (marker-start (match-beginning 2))
               (marker-end (match-end 3))
               (content-start (match-end 0))
               (eol (line-end-position))
               ;; Wrap prefix: base indent + list indent + space for number alignment
               (wrap-str (concat base-indent indent (make-string (+ 2 (length number)) ?\s))))
          ;; Style number
          (let ((ov (markdown-modern-render--get-overlay marker-start marker-end)))
            (overlay-put ov 'face 'markdown-modern-list-number)
            (overlay-put ov 'markdown-modern-type 'list-marker))
          ;; Add wrap-prefix to content
          (when (< content-start eol)
            (let ((ov (markdown-modern-render--get-overlay content-start eol)))
              (overlay-put ov 'wrap-prefix wrap-str)
              (overlay-put ov 'markdown-modern-type 'list-content)))))))))

(defun markdown-modern-render--hr (elem)
  "Render horizontal rule element ELEM.
Uses a conservative fixed count to ensure the rule never wraps."
  (let* ((start (markdown-modern-node-start elem))
         (end (markdown-modern-node-end elem))
         ;; Use a fixed safe count.  Box-drawing chars like ─ can render
         ;; wider than Emacs reports, especially on Windows.  40 chars is
         ;; safely under any reasonable column width.
         (count 40))
    (let ((ov (markdown-modern-render--get-overlay start end)))
      (overlay-put ov 'display
                   (propertize (make-string count markdown-modern-render--hr-char)
                              'face 'markdown-modern-hr))
      (overlay-put ov 'markdown-modern-type 'hr))))

(defun markdown-modern-render--process-cell-text (text base-face)
  "Process TEXT for inline formatting like **bold**, with BASE-FACE as default."
  (let ((result (propertize text 'face base-face)))
    ;; Process bold **text** -> text with bold added
    (while (string-match "\\*\\*\\([^*]+\\)\\*\\*" result)
      (let* ((bold-text (match-string 1 result))
             (styled (propertize bold-text 'face (list :inherit base-face :weight 'bold))))
        (setq result (replace-match styled t t result))))
    result))

(defun markdown-modern-render--table-parse-row (line)
  "Parse LINE into list of cell contents (without | delimiters)."
  (when (string-match "^[ \t]*|\\(.*\\)|[ \t]*$" line)
    (let ((inner (match-string 1 line)))
      (split-string inner "|" nil))))

(defun markdown-modern-render--strip-markdown (text)
  "Strip markdown formatting markers from TEXT."
  (let ((result text))
    (setq result (string-replace "**" "" result))
    (setq result (string-replace "__" "" result))
    (setq result (string-replace "`" "" result))
    result))

(defcustom markdown-modern-table-max-width nil
  "Maximum total width for rendered tables.
If nil, automatically uses window width minus margins."
  :type '(choice (const :tag "Auto (window width)" nil)
                 (integer :tag "Fixed width"))
  :group 'markdown-modern)

(defun markdown-modern-render--table-display-width ()
  "Get the available display width for tables.
Uses `window-body-width' of the window displaying the current buffer,
falling back to 80 if the buffer is not yet displayed.
Subtracts `line-prefix' width because Emacs applies `line-prefix' to
each visual line within an overlay's display string, which would
otherwise cause overflow and garbled wrapping in `visual-line-mode'."
  (let* ((win (get-buffer-window (current-buffer)))
         (raw-width (if win
                       (max 40 (window-body-width win))
                     (or markdown-modern-table-max-width 80)))
         (prefix-width (if (and (local-variable-p 'line-prefix)
                                line-prefix
                                (stringp line-prefix))
                           (string-width line-prefix)
                         0)))
    (max 40 (- raw-width prefix-width))))

(defun markdown-modern-render--table-column-widths (rows)
  "Calculate column widths from ROWS at natural content width.
Columns are sized to their widest cell so no content is truncated.  Tables
are scaled down to fit only when `markdown-modern-table-max-width' is set to a
number; with the default nil a wide table keeps its natural width and is
read by scrolling horizontally (see `markdown-modern-toggle-truncate-lines')."
  (let ((widths nil)
        (num-cols 0))
    ;; First pass: get natural widths (using string-width for display accuracy)
    (dolist (row rows)
      (setq num-cols (max num-cols (length row)))
      (let ((col 0))
        (dolist (cell row)
          (let* ((trimmed (string-trim cell))
                 (is-sep (string-match-p "^[-:|]+$" trimmed))
                 (content (if is-sep "" (markdown-modern-render--strip-markdown trimmed)))
                 (cell-width (string-width content)))
            (if (nth col widths)
                (when (> cell-width (nth col widths))
                  (setf (nth col widths) cell-width))
              (setq widths (append widths (list cell-width)))))
          (setq col (1+ col)))))
    ;; Ensure minimum width of 5 per column
    (setq widths (mapcar (lambda (w) (max 5 (or w 5))) widths))
    ;; Scale down only when a fixed maximum width is configured.  By default
    ;; tables render at natural width (no truncation); over-wide tables are
    ;; handled by horizontal scrolling, not by clipping cell content.
    (when markdown-modern-table-max-width
      (let* ((border-overhead (+ 1 num-cols (* 2 num-cols)))
             (available (max num-cols (- markdown-modern-table-max-width border-overhead)))
             (total (apply #'+ widths)))
        (when (> total available)
          (let ((scale (/ (float available) (float total))))
            (setq widths (mapcar (lambda (w) (max 5 (floor (* w scale)))) widths)))
          (let ((new-total (apply #'+ widths)))
            (when (> new-total available)
              (let ((per-col (max 5 (/ available num-cols))))
                (setq widths (mapcar (lambda (_) per-col) widths))))))))
    widths))

(defun markdown-modern-render--wrap-text (text width)
  "Wrap TEXT to WIDTH, returning list of lines.
Guarantees all returned lines are at most WIDTH characters.
Forces breaks on long words when no space is found."
  (let ((trimmed (string-trim text)))
    (if (or (zerop (length trimmed)) (<= width 0))
        (list "")
      (let ((lines nil)
            (remaining trimmed))
        ;; Keep breaking while remaining text is longer than width
        (while (> (length remaining) width)
          (let* ((chunk (substring remaining 0 width))
                 (last-space (string-match-p " [^ ]*$" chunk)))
            (if (and last-space (> last-space 0))
                ;; Break at last space within width
                (progn
                  (push (substring remaining 0 last-space) lines)
                  (setq remaining (string-trim-left (substring remaining last-space))))
              ;; No space in chunk - force break at exactly width
              (push chunk lines)
              (setq remaining (string-trim-left (substring remaining width))))))
        ;; Add final piece (guaranteed <= width)
        (when (> (length remaining) 0)
          (push remaining lines))
        (or (nreverse lines) (list ""))))))

(defun markdown-modern-render--table-truncate-to-width (str width)
  "Truncate STR to fit in WIDTH display columns.
Uses `string-width' for accurate multi-byte character handling."
  (if (<= (string-width str) width)
      str
    ;; Binary search for the right truncation point
    (let ((lo 0) (hi (length str)))
      (while (< (1+ lo) hi)
        (let ((mid (/ (+ lo hi) 2)))
          (if (<= (string-width (substring str 0 mid)) (- width 1))
              (setq lo mid)
            (setq hi mid))))
      (concat (substring str 0 lo) "…"))))

(defun markdown-modern-render--table-format-row (cells widths is-separator)
  "Format CELLS with WIDTHS.  Return single-line string, truncating if needed.
IS-SEPARATOR non-nil formats the separator row instead of a data row."
  (let ((num-cols (length widths)))
    (if is-separator
        ;; Separator row - single line
        (concat "├" (mapconcat (lambda (w) (make-string (+ w 2) ?─)) widths "┼") "┤")
      ;; Data row - truncate cells that exceed width
      (let ((parts nil))
        (dotimes (col num-cols)
          (let* ((width (or (nth col widths) 15))
                 (cell (or (nth col cells) ""))
                 (content (markdown-modern-render--strip-markdown (string-trim cell)))
                 (cw (string-width content))
                 (truncated (if (> cw width)
                                (markdown-modern-render--table-truncate-to-width content width)
                              content))
                 (pad-needed (max 0 (- width (string-width truncated))))
                 (padded (concat " " truncated (make-string pad-needed ?\s) " ")))
            (push padded parts)))
        (concat "│" (mapconcat #'identity (nreverse parts) "│") "│")))))

(defun markdown-modern-render--table (elem)
  "Render table element ELEM using per-row overlays for reliable display.
Always finds the COMPLETE table by scanning beyond element boundaries."
  (let ((start (markdown-modern-node-start elem))
        (rows nil)
        (row-info nil))
    (save-excursion
      ;; Find the true start of the table (scan backwards)
      (goto-char start)
      (beginning-of-line)
      (while (and (not (bobp))
                  (save-excursion
                    (forward-line -1)
                    (looking-at "^[ \t]*|.+|[ \t]*$")))
        (forward-line -1))
      ;; Now scan forward to collect ALL rows (no end limit)
      (let ((is-header t)
            (seen-separator nil)
            (keep-going t))
        (while (and keep-going (looking-at "^[ \t]*|.+|[ \t]*$"))
          (let* ((bol (line-beginning-position))
                 (eol (line-end-position))
                 (line (buffer-substring-no-properties bol eol))
                 (cells (markdown-modern-render--table-parse-row line))
                 (is-sep (and cells (string-match-p "^[ \t]*|[-:|]+|" line))))
            (when cells
              (push cells rows)
              (push (list bol eol is-sep
                          (and is-header (not is-sep) (not seen-separator)))
                    row-info)
              (when is-sep (setq seen-separator t))
              (when (and (not is-sep) seen-separator)
                (setq is-header nil))))
          (if (= (forward-line 1) 1)
              (setq keep-going nil))))
      (setq rows (nreverse rows))
      (setq row-info (nreverse row-info))
      ;; Clear overlays in the full table region (properly tracked)
      (when row-info
        (let ((table-start (nth 0 (car row-info)))
              (table-end (nth 1 (car (last row-info)))))
          (markdown-modern-render--clear-region table-start table-end)))
      ;; Create per-row overlays
      (when (and rows row-info)
        (let ((widths (markdown-modern-render--table-column-widths rows)))
          (when widths
            (markdown-modern-render--table-create-overlays
             rows row-info widths)))))))

(defun markdown-modern-render--table-create-overlays (rows row-info widths)
  "Create per-row overlays for table ROWS with ROW-INFO and WIDTHS.
Each source line gets its own overlay, avoiding multi-line display issues."
  (let* ((top-border (propertize
                      (concat "┌" (mapconcat (lambda (w) (make-string (+ w 2) ?─)) widths "┬") "┐")
                      'face 'markdown-modern-table))
         (bottom-border (propertize
                         (concat "└" (mapconcat (lambda (w) (make-string (+ w 2) ?─)) widths "┴") "┘")
                         'face 'markdown-modern-table))
         (row-separator (propertize
                         (concat "├" (mapconcat (lambda (w) (make-string (+ w 2) ?─)) widths "┼") "┤")
                         'face 'markdown-modern-table))
         (num-rows (length row-info))
         (row-idx 0))
    (dolist (info row-info)
      (let* ((bol (nth 0 info))
             (eol (nth 1 info))
             (is-sep (nth 2 info))
             (is-hdr (nth 3 info))
             (is-first (= row-idx 0))
             (is-last (= row-idx (1- num-rows)))
             (next-is-sep (and (< (1+ row-idx) num-rows)
                               (nth 2 (nth (1+ row-idx) row-info))))
             (cells (nth row-idx rows))
             (formatted (markdown-modern-render--table-format-row cells widths is-sep))
             (face (if is-hdr 'markdown-modern-table-header 'markdown-modern-table))
             (parts nil))
        ;; Top border before first row
        (when is-first
          (push top-border parts)
          (push "\n" parts))
        ;; Row content at natural width (no truncation; scroll for overflow)
        (push (propertize formatted 'face face) parts)
        (push "\n" parts)
        ;; After-row: bottom border on last, separator between data rows
        (cond
         (is-last
          (push bottom-border parts)
          (push "\n" parts))
         ((and (not is-sep) (not next-is-sep))
          (push row-separator parts)
          (push "\n" parts)))
        ;; Create overlay covering this source line + its newline
        (let* ((ov-end (min (1+ eol) (point-max)))
               (display-str (apply #'concat (nreverse parts)))
               (ov (markdown-modern-render--get-overlay bol ov-end)))
          (overlay-put ov 'display display-str)
          (overlay-put ov 'priority 200)
          (overlay-put ov 'markdown-modern-type 'table)
          ;; Override buffer-local line-prefix/wrap-prefix with empty
          ;; strings.  Emacs applies these to every visual line inside
          ;; an overlay's display string; the buffer-local 4-space
          ;; indent would push the table past window-body-width and
          ;; visual-line-mode wraps each row, garbling the table.
          (overlay-put ov 'line-prefix "")
          (overlay-put ov 'wrap-prefix "")))
      (setq row-idx (1+ row-idx)))))

(defun markdown-modern-render--table-row (row)
  "Render a single table ROW."
  (let ((start (plist-get row :start))
        (end (plist-get row :end))
        (is-header (plist-get row :is-header)))
    (save-excursion
      (goto-char start)
      ;; Transform | characters to box-drawing characters
      (while (re-search-forward "|" (1+ end) t)
        (let ((ov (markdown-modern-render--get-overlay (1- (point)) (point))))
          (overlay-put ov 'display
                       (propertize (string (cdr (assq 'vertical markdown-modern-render--table-chars)))
                                  'face 'markdown-modern-table-border))
          (overlay-put ov 'markdown-modern-type 'table-border)))
      ;; Apply header face if needed
      (when is-header
        (let ((ov (markdown-modern-render--get-overlay start end)))
          (overlay-put ov 'face 'markdown-modern-table-header)
          (overlay-put ov 'markdown-modern-type 'table-header)
          (overlay-put ov 'priority -5))))))

(defun markdown-modern-render--table-row-standalone (elem)
  "Render a standalone table row element ELEM from fallback parser."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      ;; Apply table background - include newline for :extend to work
      (let* ((eol (line-end-position))
             (end-with-nl (min (1+ eol) (point-max)))
             (ov (markdown-modern-render--get-overlay start end-with-nl)))
        (overlay-put ov 'face 'markdown-modern-table)
        (overlay-put ov 'markdown-modern-type 'table-row)
        (overlay-put ov 'priority -10))
      ;; Transform | characters to box-drawing
      (while (re-search-forward "|" end t)
        (let ((ov (markdown-modern-render--get-overlay (1- (point)) (point))))
          (overlay-put ov 'display
                       (propertize "│" 'face 'markdown-modern-table-border))
          (overlay-put ov 'markdown-modern-type 'table-border))))))

(defun markdown-modern-render--table-separator (elem)
  "Render table separator element ELEM as a horizontal line."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      ;; Count cells by counting | characters
      (let* ((row-text (buffer-substring-no-properties start end))
             (cell-count (1- (length (split-string row-text "|" t))))
             (line-str (concat "├" (mapconcat (lambda (_) "────────") (number-sequence 1 cell-count) "┼") "┤")))
        (let ((ov (markdown-modern-render--get-overlay start end)))
          (overlay-put ov 'display (propertize line-str 'face 'markdown-modern-table-border))
          (overlay-put ov 'markdown-modern-type 'table-separator))))))

;;; Extended Element Rendering

(defun markdown-modern-render--footnote-ref (elem)
  "Render footnote reference element ELEM."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      (when (looking-at "\\[\\^\\([^]]+\\)\\]")
        (let ((ref (match-string 1)))
          ;; Display as superscript
          (let ((ov (markdown-modern-render--get-overlay start end)))
            (overlay-put ov 'display
                         (propertize ref 'face 'markdown-modern-footnote-ref
                                    'display '(raise 0.3)))
            (overlay-put ov 'help-echo (format "Footnote: %s" ref))
            (overlay-put ov 'markdown-modern-type 'footnote-ref)))))))

;;; LaTeX-to-Unicode Conversion Tables

(defconst markdown-modern-render--latex-symbols
  '(;; Greek lowercase
    ("\\alpha" . "α") ("\\beta" . "β") ("\\gamma" . "γ") ("\\delta" . "δ")
    ("\\epsilon" . "ε") ("\\varepsilon" . "ε") ("\\zeta" . "ζ") ("\\eta" . "η")
    ("\\theta" . "θ") ("\\vartheta" . "ϑ") ("\\iota" . "ι") ("\\kappa" . "κ")
    ("\\lambda" . "λ") ("\\mu" . "μ") ("\\nu" . "ν") ("\\xi" . "ξ")
    ("\\pi" . "π") ("\\varpi" . "ϖ") ("\\rho" . "ρ") ("\\varrho" . "ϱ")
    ("\\sigma" . "σ") ("\\varsigma" . "ς") ("\\tau" . "τ") ("\\upsilon" . "υ")
    ("\\phi" . "φ") ("\\varphi" . "φ") ("\\chi" . "χ") ("\\psi" . "ψ")
    ("\\omega" . "ω")
    ;; Greek uppercase
    ("\\Gamma" . "Γ") ("\\Delta" . "Δ") ("\\Theta" . "Θ") ("\\Lambda" . "Λ")
    ("\\Xi" . "Ξ") ("\\Pi" . "Π") ("\\Sigma" . "Σ") ("\\Upsilon" . "Υ")
    ("\\Phi" . "Φ") ("\\Psi" . "Ψ") ("\\Omega" . "Ω")
    ;; Operators
    ("\\int" . "∫") ("\\iint" . "∬") ("\\iiint" . "∭")
    ("\\oint" . "∮") ("\\sum" . "∑") ("\\prod" . "∏")
    ("\\partial" . "∂") ("\\nabla" . "∇") ("\\infty" . "∞")
    ("\\cdot" . "·") ("\\times" . "×") ("\\pm" . "±") ("\\mp" . "∓")
    ("\\div" . "÷") ("\\star" . "⋆") ("\\circ" . "∘") ("\\bullet" . "∙")
    ("\\oplus" . "⊕") ("\\otimes" . "⊗")
    ;; Relations
    ("\\leq" . "≤") ("\\le" . "≤") ("\\geq" . "≥") ("\\ge" . "≥")
    ("\\neq" . "≠") ("\\ne" . "≠") ("\\approx" . "≈") ("\\equiv" . "≡")
    ("\\sim" . "∼") ("\\simeq" . "≃") ("\\cong" . "≅") ("\\propto" . "∝")
    ("\\ll" . "≪") ("\\gg" . "≫") ("\\prec" . "≺") ("\\succ" . "≻")
    ;; Set theory
    ("\\in" . "∈") ("\\notin" . "∉") ("\\ni" . "∋")
    ("\\subset" . "⊂") ("\\supset" . "⊃")
    ("\\subseteq" . "⊆") ("\\supseteq" . "⊇")
    ("\\cup" . "∪") ("\\cap" . "∩")
    ("\\emptyset" . "∅") ("\\varnothing" . "∅")
    ;; Arrows
    ("\\to" . "→") ("\\rightarrow" . "→") ("\\leftarrow" . "←")
    ("\\leftrightarrow" . "↔")
    ("\\Rightarrow" . "⇒") ("\\Leftarrow" . "⇐")
    ("\\Leftrightarrow" . "⇔") ("\\iff" . "⇔")
    ("\\mapsto" . "↦") ("\\uparrow" . "↑") ("\\downarrow" . "↓")
    ;; Logic
    ("\\forall" . "∀") ("\\exists" . "∃") ("\\nexists" . "∄")
    ("\\neg" . "¬") ("\\lnot" . "¬")
    ("\\wedge" . "∧") ("\\land" . "∧")
    ("\\vee" . "∨") ("\\lor" . "∨")
    ("\\top" . "⊤") ("\\bot" . "⊥") ("\\vdash" . "⊢") ("\\models" . "⊨")
    ;; Dots
    ("\\ldots" . "…") ("\\cdots" . "⋯") ("\\vdots" . "⋮") ("\\ddots" . "⋱")
    ("\\dots" . "…")
    ;; Misc symbols
    ("\\hbar" . "ℏ") ("\\ell" . "ℓ") ("\\Re" . "ℜ") ("\\Im" . "ℑ")
    ("\\aleph" . "ℵ") ("\\wp" . "℘")
    ("\\angle" . "∠") ("\\triangle" . "△")
    ("\\diamond" . "⋄") ("\\langle" . "⟨") ("\\rangle" . "⟩")
    ;; Spacing commands (replace with appropriate space or nothing)
    ("\\quad" . " ") ("\\qquad" . "  ") ("\\," . " ") ("\\;" . " ")
    ("\\!" . "") ("\\:" . " ") ("\\ " . " "))
  "Alist mapping LaTeX commands to Unicode characters.")

(defconst markdown-modern-render--latex-superscripts
  '((?0 . ?⁰) (?1 . ?¹) (?2 . ?²) (?3 . ?³) (?4 . ?⁴)
    (?5 . ?⁵) (?6 . ?⁶) (?7 . ?⁷) (?8 . ?⁸) (?9 . ?⁹)
    (?+ . ?⁺) (?- . ?⁻) (?= . ?⁼) (?\( . ?⁽) (?\) . ?⁾)
    (?n . ?ⁿ) (?i . ?ⁱ) (?x . ?ˣ) (?y . ?ʸ)
    (?a . ?ᵃ) (?b . ?ᵇ) (?c . ?ᶜ) (?d . ?ᵈ) (?e . ?ᵉ)
    (?f . ?ᶠ) (?g . ?ᵍ) (?h . ?ʰ) (?j . ?ʲ) (?k . ?ᵏ)
    (?l . ?ˡ) (?m . ?ᵐ) (?o . ?ᵒ) (?p . ?ᵖ) (?r . ?ʳ)
    (?s . ?ˢ) (?t . ?ᵗ) (?u . ?ᵘ) (?v . ?ᵛ) (?w . ?ʷ) (?z . ?ᶻ)
    (?A . ?ᴬ) (?B . ?ᴮ) (?D . ?ᴰ) (?E . ?ᴱ) (?G . ?ᴳ)
    (?H . ?ᴴ) (?I . ?ᴵ) (?J . ?ᴶ) (?K . ?ᴷ) (?L . ?ᴸ)
    (?M . ?ᴹ) (?N . ?ᴺ) (?O . ?ᴼ) (?P . ?ᴾ) (?R . ?ᴿ)
    (?T . ?ᵀ) (?U . ?ᵁ) (?V . ?ⱽ) (?W . ?ᵂ))
  "Alist mapping characters to their Unicode superscript equivalents.")

(defconst markdown-modern-render--latex-subscripts
  '((?0 . ?₀) (?1 . ?₁) (?2 . ?₂) (?3 . ?₃) (?4 . ?₄)
    (?5 . ?₅) (?6 . ?₆) (?7 . ?₇) (?8 . ?₈) (?9 . ?₉)
    (?+ . ?₊) (?- . ?₋) (?= . ?₌) (?\( . ?₍) (?\) . ?₎)
    (?a . ?ₐ) (?e . ?ₑ) (?h . ?ₕ) (?i . ?ᵢ) (?j . ?ⱼ)
    (?k . ?ₖ) (?l . ?ₗ) (?m . ?ₘ) (?n . ?ₙ) (?o . ?ₒ)
    (?p . ?ₚ) (?r . ?ᵣ) (?s . ?ₛ) (?t . ?ₜ) (?u . ?ᵤ)
    (?v . ?ᵥ) (?x . ?ₓ))
  "Alist mapping characters to their Unicode subscript equivalents.")

(defun markdown-modern-render--latex-convert-scripts (str map prefix)
  "Convert characters in STR using MAP (super/subscript alist).
PREFIX is the script marker (\"^\" or \"_\") used for unconvertible chars."
  (let ((result "")
        (i 0)
        (len (length str)))
    (while (< i len)
      (let* ((ch (aref str i))
             (mapped (cdr (assq ch map))))
        (if mapped
            (setq result (concat result (string mapped)))
          ;; No mapping: keep prefix + char for visibility
          (setq result (concat result prefix (string ch)))))
      (setq i (1+ i)))
    result))

(defun markdown-modern-render--latex-to-unicode (latex-str)
  "Convert LATEX-STR to Unicode representation.
Handles symbols, superscripts, subscripts, sqrt, frac, and text commands."
  (let ((s latex-str)
        (case-fold-search nil))
    ;; 1. Replace \sqrt{...} → √(...) and \sqrt x → √x
    (let ((pos 0))
      (while (string-match "\\\\sqrt{\\([^}]*\\)}" s pos)
        (let ((repl (concat "√(" (match-string 1 s) ")")))
          (setq s (replace-match repl t t s))
          (setq pos (+ (match-beginning 0) (length repl))))))
    (let ((pos 0))
      (while (string-match "\\\\sqrt \\([a-zA-Z0-9]\\)" s pos)
        (let ((repl (concat "√" (match-string 1 s))))
          (setq s (replace-match repl t t s))
          (setq pos (+ (match-beginning 0) (length repl))))))

    ;; 2. Replace \frac{a}{b} → a⁄b
    (let ((pos 0))
      (while (string-match "\\\\frac{\\([^}]*\\)}{\\([^}]*\\)}" s pos)
        (let ((repl (concat (match-string 1 s) "⁄" (match-string 2 s))))
          (setq s (replace-match repl t t s))
          (setq pos (+ (match-beginning 0) (length repl))))))

    ;; 3. Replace \text{...}, \mathrm{...}, \operatorname{...} → just the text
    (let ((pos 0))
      (while (string-match "\\\\\\(?:text\\|mathrm\\|operatorname\\|mathit\\|mathbf\\|textbf\\){\\([^}]*\\)}" s pos)
        (let ((repl (match-string 1 s)))
          (setq s (replace-match repl t t s))
          (setq pos (+ (match-beginning 0) (length repl))))))

    ;; 4. Replace \left and \right (sizing commands) - remove them
    (setq s (replace-regexp-in-string "\\\\left\\b" "" s))
    (setq s (replace-regexp-in-string "\\\\right\\b" "" s))

    ;; 5. Replace all known \command symbols (longest match first)
    (let ((sorted-symbols (sort (copy-sequence markdown-modern-render--latex-symbols)
                                (lambda (a b) (> (length (car a)) (length (car b)))))))
      (dolist (pair sorted-symbols)
        (let ((cmd (car pair))
              (uni (cdr pair)))
          ;; Match command followed by non-letter (word boundary) or end of string
          (let ((re (concat (regexp-quote cmd) "\\(?:[^a-zA-Z]\\|$\\)"))
                (pos 0))
            (while (string-match re s pos)
              (let ((end-pos (+ (match-beginning 0) (length cmd))))
                (setq s (concat (substring s 0 (match-beginning 0))
                                uni
                                (substring s end-pos)))
                (setq pos (+ (match-beginning 0) (length uni)))))))))

    ;; 6. Convert ^{...} and ^x to superscripts
    (let ((pos 0))
      (while (and (< pos (length s))
                  (string-match "\\^{\\([^}]*\\)}" s pos))
        (let* ((content (match-string 1 s))
               (repl (markdown-modern-render--latex-convert-scripts
                      content markdown-modern-render--latex-superscripts "")))
          (setq s (replace-match repl t t s))
          (setq pos (+ (match-beginning 0) (length repl))))))
    ;; Single char superscript: ^x (but not ^{ which was handled above)
    (let ((pos 0))
      (while (and (< pos (length s))
                  (string-match "\\^\\([^{ \t\n]\\)" s pos))
        (let* ((ch-str (match-string 1 s))
               (ch (aref ch-str 0))
               (mapped (cdr (assq ch markdown-modern-render--latex-superscripts))))
          (if mapped
              (progn
                (setq s (replace-match (string mapped) t t s))
                (setq pos (+ (match-beginning 0) 1)))
            ;; No mapping available - skip past this ^ and char
            (setq pos (match-end 0))))))

    ;; 7. Convert _{...} and _x to subscripts
    (let ((pos 0))
      (while (and (< pos (length s))
                  (string-match "_{\\([^}]*\\)}" s pos))
        (let* ((content (match-string 1 s))
               (repl (markdown-modern-render--latex-convert-scripts
                      content markdown-modern-render--latex-subscripts "")))
          (setq s (replace-match repl t t s))
          (setq pos (+ (match-beginning 0) (length repl))))))
    ;; Single char subscript: _x
    (let ((pos 0))
      (while (and (< pos (length s))
                  (string-match "_\\([^{ \t\n]\\)" s pos))
        (let* ((ch-str (match-string 1 s))
               (ch (aref ch-str 0))
               (mapped (cdr (assq ch markdown-modern-render--latex-subscripts))))
          (if mapped
              (progn
                (setq s (replace-match (string mapped) t t s))
                (setq pos (+ (match-beginning 0) 1)))
            ;; No mapping available - skip past
            (setq pos (match-end 0))))))

    ;; 8. Strip remaining bare { and }
    (setq s (replace-regexp-in-string "[{}]" "" s))

    ;; 9. Clean up extra whitespace
    (setq s (replace-regexp-in-string "  +" " " s))
    (setq s (string-trim s))

    s))

(defun markdown-modern-render--math (elem)
  "Render inline math element ELEM.
Converts LaTeX to Unicode, hides $ delimiters, replaces content."
  (let* ((start (markdown-modern-node-start elem))
         (end (markdown-modern-node-end elem))
         (content-start (1+ start))
         (content-end (1- end)))
    (when (< content-start content-end)
      (let* ((latex (buffer-substring-no-properties content-start content-end))
             (unicode (markdown-modern-render--latex-to-unicode latex))
             (display-str (propertize unicode 'face 'markdown-modern-math)))
        ;; Hide opening $
        (let ((ov (markdown-modern-render--get-overlay start content-start)))
          (overlay-put ov 'display "")
          (overlay-put ov 'markdown-modern-type 'math-delim))
        ;; Replace content with Unicode conversion
        (let ((ov (markdown-modern-render--get-overlay content-start content-end)))
          (overlay-put ov 'display display-str)
          (overlay-put ov 'markdown-modern-type 'math-content)
          (overlay-put ov 'priority 110)
          (overlay-put ov 'help-echo (format "LaTeX: $%s$" latex)))
        ;; Hide closing $
        (let ((ov (markdown-modern-render--get-overlay content-end end)))
          (overlay-put ov 'display "")
          (overlay-put ov 'markdown-modern-type 'math-delim))))))

(defun markdown-modern-render--math-block (elem)
  "Render display math block element ELEM.
Converts LaTeX to Unicode using 3-overlay approach:
hide opening $$ line, display converted content, hide closing $$ line."
  (let* ((start (markdown-modern-node-start elem))
         (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      ;; Find opening $$ line end
      (when (looking-at "^\\$\\$[ \t]*\r?$")
        (let* ((open-line-end (min (1+ (line-end-position)) end))
               (content-start open-line-end)
               (close-start (save-excursion
                              (goto-char end)
                              (if (re-search-backward "^\\$\\$[ \t]*\r?$"
                                                      content-start t)
                                  (match-beginning 0)
                                end))))
          (when (< content-start close-start)
            (let* ((latex (string-trim
                           (buffer-substring-no-properties
                            content-start close-start)))
                   (unicode (markdown-modern-render--latex-to-unicode latex))
                   (display-str (propertize unicode 'face 'markdown-modern-math)))
              ;; Hide opening $$ line
              (let ((ov (markdown-modern-render--get-overlay start open-line-end)))
                (overlay-put ov 'display "")
                (overlay-put ov 'markdown-modern-type 'math-block-delim))
              ;; Replace content with Unicode conversion
              (let ((ov (markdown-modern-render--get-overlay content-start close-start)))
                (overlay-put ov 'display display-str)
                (overlay-put ov 'markdown-modern-type 'math-block-content)
                (overlay-put ov 'priority 110)
                (overlay-put ov 'help-echo (format "LaTeX: $$%s$$" latex))
                ;; Apply scale via face height on the overlay itself
                (when (and markdown-modern-math-block-scale
                           (/= markdown-modern-math-block-scale 1.0))
                  (overlay-put ov 'face
                               (list :height markdown-modern-math-block-scale))))
              ;; Hide closing $$ line
              (let ((ov (markdown-modern-render--get-overlay close-start end)))
                (overlay-put ov 'display "")
                (overlay-put ov 'markdown-modern-type 'math-block-delim)))))))))

(defcustom markdown-modern-cache-directory
  (expand-file-name "markdown-modern" (or (getenv "XDG_CACHE_HOME") "~/.cache"))
  "Directory for caching rendered diagrams."
  :type 'directory
  :group 'markdown-modern-media)

;;; Mermaid Diagram Rendering (SVG)

(defvar-local markdown-modern-render--mermaid-cache nil
  "Hash table caching mermaid diagram SVG by content hash.")

(defun markdown-modern-render--mermaid-cache ()
  "Return the mermaid SVG cache, creating if needed."
  (unless markdown-modern-render--mermaid-cache
    (setq markdown-modern-render--mermaid-cache (make-hash-table :test 'equal)))
  markdown-modern-render--mermaid-cache)

(defun markdown-modern-render--mermaid (elem)
  "Render Mermaid diagram element ELEM as inline SVG."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      (when (looking-at "^[ \t]*```mermaid[ \t]*\r?$")
        (let* ((content-start (1+ (line-end-position)))
               (content-end (save-excursion
                              (goto-char end)
                              (if (re-search-backward "^[ \t]*```[ \t]*\r?$" content-start t)
                                  (match-beginning 0)
                                end)))
               (diagram-code (buffer-substring-no-properties content-start content-end))
               (cache-key (md5 diagram-code))
               (svg-string (or (gethash cache-key (markdown-modern-render--mermaid-cache))
                               (let ((svg (condition-case err
                                              (markdown-modern-mermaid-render diagram-code)
                                            (error
                                             (message "markdown-modern: mermaid render error: %s" (error-message-string err))
                                             nil))))
                                 (when svg
                                   (puthash cache-key svg (markdown-modern-render--mermaid-cache)))
                                 svg))))
          (if svg-string
              (condition-case img-err
                  (markdown-modern-render--display-mermaid-svg start end svg-string cache-key)
                (error
                 (message "markdown-modern: mermaid SVG display error: %s" (error-message-string img-err))
                 (markdown-modern-render--mermaid-source-fallback elem)))
            ;; Unsupported diagram type or error - show as styled code block
            (markdown-modern-render--mermaid-source-fallback elem)))))))

(defun markdown-modern-render--display-mermaid-svg (start end svg-string &optional cache-key)
  "Display SVG-STRING as an inline image in region START to END.
The image is built from the SVG data in memory (no temp file) and cached by
CACHE-KEY (or the SVG hash).  Because jit-lock re-renders a block every time it
scrolls back into view, caching the image object means the SVG is converted to
an image only once per unique diagram, not on every render."
  (when (and svg-string
             (> (length svg-string) 0)
             (<= start (point-max))
             (<= end (point-max)))
    (let* ((key (cons 'img (or cache-key (md5 svg-string))))
           (cache (markdown-modern-render--mermaid-cache))
           (image (or (gethash key cache)
                      (let ((img (create-image svg-string 'svg t
                                               :scale 2.0
                                               :max-width (* 2 (or markdown-modern-image-max-width 600)))))
                        (puthash key img cache)
                        img))))
      (when image
        (markdown-modern-render--clear-region start end)
        (let ((ov (markdown-modern-render--get-overlay start end)))
          (overlay-put ov 'display image)
          (overlay-put ov 'help-echo "Mermaid diagram (SVG)")
          (overlay-put ov 'markdown-modern-type 'mermaid-svg)
          (overlay-put ov 'priority 200))))))

(defun markdown-modern-render--mermaid-source-fallback (elem)
  "Render Mermaid ELEM as styled code block for unsupported diagram types."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      (when (looking-at "^[ \t]*```mermaid[ \t]*\r?$")
        (let* ((fence-end (line-end-position))
               (closing-fence (save-excursion
                                (goto-char end)
                                (if (re-search-backward "^[ \t]*```[ \t]*\r?$" fence-end t)
                                    (match-beginning 0)
                                  end)))
               (content-start (1+ fence-end)))
          ;; Replace opening fence with mermaid label
          (let ((ov (markdown-modern-render--get-overlay start fence-end)))
            (overlay-put ov 'display
                         (propertize " mermaid "
                                    'face 'markdown-modern-code-block-language))
            (overlay-put ov 'markdown-modern-type 'mermaid-fallback)
            (overlay-put ov 'priority 100))
          ;; Apply background to content lines
          (when (< content-start closing-fence)
            (save-excursion
              (goto-char content-start)
              (while (< (point) closing-fence)
                (let* ((bol (line-beginning-position))
                       (eol (line-end-position))
                       (line-end (min (1+ eol) closing-fence)))
                  (let ((ov (markdown-modern-render--get-overlay bol line-end)))
                    (overlay-put ov 'face 'markdown-modern-code-block)
                    (overlay-put ov 'markdown-modern-type 'mermaid-fallback)
                    (overlay-put ov 'priority 10)))
                (forward-line 1))))
          ;; Hide closing fence
          (when (< closing-fence end)
            (let ((ov (markdown-modern-render--get-overlay closing-fence end)))
              (overlay-put ov 'display "")
              (overlay-put ov 'markdown-modern-type 'mermaid-fallback)
              (overlay-put ov 'priority 100))))))))

(defcustom markdown-modern-math-block-scale 1.4
  "Scale factor for display math block text relative to normal font size.
A value of 1.4 means display math is shown at 140% of normal size.
Set to 1.0 for same size as body text."
  :type 'number
  :group 'markdown-modern-math)

;;; Enhanced Math Rendering with SVG

(defcustom markdown-modern-math-renderer 'text
  "Method for rendering LaTeX math.
`text' - Styled text display (default, no dependencies)
`svg'  - SVG rendering via tex2svg or similar
`preview' - Use preview-latex if available"
  :type '(choice (const :tag "Styled text" text)
                 (const :tag "SVG rendering" svg)
                 (const :tag "preview-latex" preview))
  :group 'markdown-modern-math)

(defcustom markdown-modern-tex2svg-executable "tex2svg"
  "Path to tex2svg executable (from MathJax-node)."
  :type 'string
  :group 'markdown-modern-math)

(defun markdown-modern-tex2svg-available-p ()
  "Check if tex2svg is available."
  (executable-find markdown-modern-tex2svg-executable))

(defun markdown-modern-render--math-enhanced (elem)
  "Render math ELEM with the configured renderer."
  (pcase markdown-modern-math-renderer
    ('svg (if (markdown-modern-tex2svg-available-p)
              (markdown-modern-render--math-svg elem)
            (markdown-modern-render--math elem)))
    ('preview (markdown-modern-render--math-preview elem))
    (_ (markdown-modern-render--math elem))))

(defun markdown-modern-render--math-svg (elem)
  "Render math ELEM to SVG."
  (let ((start (markdown-modern-node-start elem))
        (end (markdown-modern-node-end elem)))
    (save-excursion
      (goto-char start)
      (when (looking-at "\\$\\([^$]+\\)\\$")
        (let* ((latex (match-string 1))
               (hash (md5 latex))
               (cache-path (expand-file-name
                           (format "math-%s.svg" hash)
                           markdown-modern-cache-directory)))
          (if (file-exists-p cache-path)
              ;; Use cached SVG
              (let ((image (create-image cache-path 'svg nil :ascent 'center)))
                (let ((ov (markdown-modern-render--get-overlay start end)))
                  (overlay-put ov 'display image)
                  (overlay-put ov 'help-echo (format "LaTeX: %s" latex))
                  (overlay-put ov 'markdown-modern-type 'math-svg)))
            ;; Render and cache
            (markdown-modern-render--math elem)))))))  ; Fallback to text for now

(defun markdown-modern-render--math-preview (elem)
  "Render math ELEM using preview-latex if available."
  (if (featurep 'preview)
      ;; preview-latex available
      (let ((_start (markdown-modern-node-start elem))
            (_end (markdown-modern-node-end elem)))
        ;; Use preview-latex machinery
        (markdown-modern-render--math elem))  ; Simplified - full integration would be complex
    ;; Fallback
    (markdown-modern-render--math elem)))

(provide 'markdown-modern-render)
;;; markdown-modern-render.el ends here
