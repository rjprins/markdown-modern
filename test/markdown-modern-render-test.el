;;; markdown-modern-render-test.el --- Overlay-output tests -*- lexical-binding: t; no-byte-compile: t; -*-

;; This file is part of markdown-modern.

;;; Commentary:

;; Tests that the element renderers produce the expected overlays: markers and
;; delimiters hidden (display ""), content carrying the right face.  The
;; tests exercise the required Tree-sitter parser.
;; Run the list-marker pixel-alignment tests in a graphical Emacs with
;; M-x ert RET ^render/list-marker- RET; batch mode skips pixel assertions.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'markdown-modern)

(defmacro markdown-modern-render-test--with (text &rest body)
  "Render TEXT in a temp buffer with Tree-sitter and run BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (setq-local markdown-modern--rendering-enabled t)
     (markdown-modern-render--init)
     (insert ,text)
     (markdown-modern-ts--init)
     (markdown-modern--jit-fontify (point-min) (point-max))
     ,@body))

(defun markdown-modern-render-test--ov (type)
  "Return the first overlay whose `markdown-modern-type' is TYPE, or nil."
  (cl-find-if (lambda (ov) (eq (overlay-get ov 'markdown-modern-type) type))
              (overlays-in (point-min) (point-max))))

(defun markdown-modern-render-test--count (type)
  "Return the number of overlays whose `markdown-modern-type' is TYPE."
  (cl-count-if (lambda (ov) (eq (overlay-get ov 'markdown-modern-type) type))
               (overlays-in (point-min) (point-max))))

(defun markdown-modern-render-test--move (pos)
  "Move point to POS and run the post-command update."
  (goto-char pos)
  (markdown-modern--update-reveal))

(defun markdown-modern-render-test--edit ()
  "Edit the text at point, keep it the same, and run the post-command update."
  (insert "x")
  (delete-char -1)
  (markdown-modern--update-reveal)
  (markdown-modern--jit-fontify (point-min) (point-max)))

(defun markdown-modern-render-test--type (string)
  "Type STRING at point like a user, redisplaying after each character.
Only the text that the edit marks for re-rendering is rendered again."
  (with-silent-modifications
    (put-text-property (point-min) (point-max) 'fontified t))
  (dolist (char (string-to-list string))
    (insert char)
    (markdown-modern--after-change (1- (point)) (point) 0)
    (markdown-modern--update-reveal)
    (let (start)
      (while (setq start (text-property-any (point-min) (point-max) 'fontified nil))
        (let ((end (or (next-single-property-change start 'fontified)
                       (point-max))))
          (markdown-modern--jit-fontify start end)
          (with-silent-modifications
            (put-text-property start end 'fontified t)))))))

(defun markdown-modern-render-test--settle ()
  "Check that a paragraph update is waiting for idle time, then run it."
  (should (memq markdown-modern--paragraph-timer timer-idle-list))
  (cancel-timer markdown-modern--paragraph-timer)
  (markdown-modern--paragraph-settle))

;;; Renderer assertions

(defun markdown-modern-render-test--assert-heading ()
  (markdown-modern-render-test--with "## A heading\n"
    (let ((marker (markdown-modern-render-test--ov 'heading-marker))
          (content (markdown-modern-render-test--ov 'heading-content)))
      (should marker)
      (should (equal (overlay-get marker 'display) ""))   ; ## hidden
      (should content)
      (should (eq (overlay-get content 'face) 'markdown-modern-heading-2)))))

(defun markdown-modern-render-test--assert-strong ()
  (markdown-modern-render-test--with "x **bold** y\n"
    (let ((delim (markdown-modern-render-test--ov 'strong-delim))
          (content (markdown-modern-render-test--ov 'strong-content)))
      (should delim)
      (should (equal (overlay-get delim 'display) ""))
      (should content)
      (should (eq (overlay-get content 'face) 'markdown-modern-bold)))))

(defun markdown-modern-render-test--assert-emphasis ()
  (markdown-modern-render-test--with "x *em* y\n"
    (let ((delim (markdown-modern-render-test--ov 'emphasis-delim))
          (content (markdown-modern-render-test--ov 'emphasis-content)))
      (should delim)
      (should (equal (overlay-get delim 'display) ""))
      (should content)
      (should (eq (overlay-get content 'face) 'markdown-modern-italic)))))

(defun markdown-modern-render-test--assert-code-span ()
  (markdown-modern-render-test--with "x `code` y\n"
    (let ((delim (markdown-modern-render-test--ov 'code-delim))
          (content (markdown-modern-render-test--ov 'code-content)))
      (should delim)
      (should (equal (overlay-get delim 'display) ""))
      (should content)
      (should (eq (overlay-get content 'face) 'markdown-modern-inline-code)))))

(defun markdown-modern-render-test--assert-strikethrough ()
  (markdown-modern-render-test--with "x ~~no~~ y\n"
    (let ((delim (markdown-modern-render-test--ov 'strike-delim))
          (content (markdown-modern-render-test--ov 'strike-content)))
      (should delim)
      (should (equal (overlay-get delim 'display) ""))
      (should content)
      (should (eq (overlay-get content 'face) 'markdown-modern-strikethrough)))))

(defun markdown-modern-render-test--assert-link ()
  (markdown-modern-render-test--with "see [text](http://x.com) ok\n"
    (let ((text (markdown-modern-render-test--ov 'link-text))
          (delim (markdown-modern-render-test--ov 'link-delim)))
      (should text)
      (should (eq (overlay-get text 'face) 'markdown-modern-link))
      (should delim)
      (should (equal (overlay-get delim 'display) "")))))   ; (url) hidden

(defmacro markdown-modern-render-test--with-local-file (&rest body)
  "Run BODY with a Markdown SOURCE buffer and a 400-line local TARGET file."
  (declare (indent 0))
  `(let* ((directory (make-temp-file "markdown-modern-link-" t))
          (target (expand-file-name "pkg/core/source.el" directory))
          (auto-mode-alist nil)
          (xref--history (xref--make-xref-history)))
     (unwind-protect
         (progn
           (make-directory (file-name-directory target) t)
           (with-temp-file target
             (dotimes (line 400)
               (insert (format ";; Line %d\n" (1+ line)))))
           (save-window-excursion
             (with-temp-buffer
               (let ((source (current-buffer)))
                 (setq buffer-file-name (expand-file-name "walkthrough.md" directory)
                       default-directory "/")
                 (insert "see [Source](pkg/core/source.el#L352) end\n")
                 (markdown-modern-mode)
                 (switch-to-buffer source)
                 (markdown-modern--jit-fontify (point-min) (point-max))
                 ,@body))))
       (when-let* ((buffer (get-file-buffer target)))
         (kill-buffer buffer))
       (delete-directory directory t))))

(ert-deftest render/local-link-follow-and-return ()
  "Rendered and revealed local links visit the exact line and allow return."
  (markdown-modern-render-test--with-local-file
    (dolist (revealed '(nil t))
      (goto-char 8)
      (when revealed
        (markdown-modern--update-reveal)
        (search-forward "source.el"))
      (let ((origin (point)))
        (markdown-modern-follow-link-at-point)
        (should (equal buffer-file-name target))
        (should (= (line-number-at-pos) 352))
        (should (= (current-column) 0))
        (xref-go-back)
        (should (eq (current-buffer) source))
        (should (= (point) origin))))))

(ert-deftest render/local-link-paths-and-ranges ()
  "Absolute paths, file URLs, encoded names and ranges use local navigation."
  (markdown-modern-render-test--with-local-file
    (let ((encoded-target (expand-file-name "pkg/core/café source.el" directory)))
      (rename-file target encoded-target)
      (setq target encoded-target)
      (dolist (url (list "pkg/core/caf%C3%A9%20source.el#L352-L365"
                         (concat target "#L352")
                         (concat "file://" target "#L352")
                         (concat "file://localhost" target "#L352")))
        (markdown-modern-render--follow-link url)
        (should (equal buffer-file-name target))
        (should (= (line-number-at-pos) 352))
        (xref-go-back)
        (should (eq (current-buffer) source))))))

(ert-deftest render/local-link-missing-file ()
  "A missing target reports an error without creating a buffer."
  (markdown-modern-render-test--with-local-file
    (should-error (markdown-modern-render--follow-link "pkg/missing.el#L352")
                  :type 'user-error)
    (should (eq (current-buffer) source))
    (should-not (get-file-buffer (expand-file-name "pkg/missing.el" directory)))))

(ert-deftest render/local-link-heading-and-line-fragments ()
  "Heading anchors still work, and line anchors use absolute buffer lines."
  (save-window-excursion
    (with-temp-buffer
      (insert "intro\n\n## Installation\n\nbody\n")
      (switch-to-buffer (current-buffer))
      (markdown-modern-render--follow-link "#installation")
      (should (= (line-number-at-pos) 3))
      (narrow-to-region (point) (point-max))
      (markdown-modern-render--follow-link "#L2")
      (should-not (buffer-narrowed-p))
      (should (= (line-number-at-pos) 2))
      (should-error (markdown-modern-render--follow-link "#L100")
                    :type 'user-error)
      (erase-buffer)
      (insert "one\ntwo")
      (should-error (markdown-modern-render--follow-link "#L3")
                    :type 'user-error))))

(ert-deftest render/local-link-without-fragment ()
  "Plain file links open locally, using default-directory for unsaved notes."
  (markdown-modern-render-test--with-local-file
    (setq buffer-file-name nil
          default-directory directory)
    (markdown-modern-render--follow-link "pkg/core/source.el")
    (should (equal buffer-file-name target))
    (xref-go-back)
    (should (eq (current-buffer) source))))

(ert-deftest render/link-other-schemes-use-browser ()
  "Browser URLs and non-file schemes keep their existing handler."
  (dolist (url '("https://example.com/source.el#L352"
                 "HTTP://example.com" "mailto:user@example.com"
                 "ftp://example.com/file" "//example.com/file"))
    (let (visited)
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (target &rest _) (setq visited target))))
        (markdown-modern-render--follow-link url))
      (should (equal visited url)))))

(ert-deftest render/local-link-mouse-in-other-window ()
  "Mouse navigation uses the clicked window's buffer and leaves an origin."
  (markdown-modern-render-test--with-local-file
    (let* ((source-window (selected-window))
           (other-window (split-window-below))
           (position (list source-window 8 '(0 . 0) 0)))
      (set-window-buffer other-window (get-buffer-create " *link-other-window*"))
      (unwind-protect
          (progn
            (select-window other-window)
            (markdown-modern-render--follow-link-at-mouse
             (list 'mouse-1 position))
            (should (eq (selected-window) source-window))
            (should (equal (window-buffer source-window) (get-file-buffer target)))
            (with-current-buffer (window-buffer source-window)
              (should (= (line-number-at-pos) 352)))
            (xref-go-back)
            (should (eq (current-buffer) source))
            (should (= (point) 8)))
        (kill-buffer " *link-other-window*")))))

(ert-deftest render/link-mouse-down-and-overlay-reuse ()
  "Mouse-down keeps the label stable; pooled overlays lose link actions."
  (markdown-modern-render-test--with "see [Source](source.el#L352) end\n"
    (let ((link (markdown-modern-render-test--ov 'link-text)))
      (goto-char (point-max))
      (call-interactively
       (lookup-key (overlay-get link 'keymap) [down-mouse-1]))
      (markdown-modern--update-reveal)
      (should-not markdown-modern--revealed-region)
      (should (markdown-modern-render-test--ov 'link-delim))
      (markdown-modern-render--release-overlay link)
      (let ((reused (markdown-modern-render--get-overlay 1 4)))
        (should (eq reused link))
        (should-not (overlay-get reused 'keymap))
        (should-not (overlay-get reused 'mouse-face))
        (should-not (overlay-get reused 'follow-link))
        (should-not (overlay-get reused 'markdown-modern-url))))))

(defun markdown-modern-render-test--link-urls ()
  "Return (LABEL . URL) for each rendered link, in buffer order."
  (mapcar (lambda (ov)
            (cons (buffer-substring-no-properties (overlay-start ov) (overlay-end ov))
                  (overlay-get ov 'markdown-modern-url)))
          (sort (cl-remove-if-not
                 (lambda (ov) (eq (overlay-get ov 'markdown-modern-type) 'link-text))
                 (overlays-in (point-min) (point-max)))
                (lambda (a b) (< (overlay-start a) (overlay-start b))))))

(ert-deftest render/reference-links ()
  "Reference links render when their label is defined, in any of three forms.
Undefined labels, footnotes and definitions inside code stay plain text."
  (markdown-modern-render-test--with
      (concat "- [Full][Log] and [Collapsed][] and [Short].\n"
              "- [none][missing] [^1] [in code][code]\n\n"
              "[log]: ../CHANGELOG.md \"Changes\"\n"
              "[collapsed]: <https://c.example>\n"
              "[SHORT]:\n  https://s.example\n\n"
              "```\n[code]: https://code.example\n```\n")
    (should (equal (markdown-modern-render-test--link-urls)
                   '(("Full" . "../CHANGELOG.md")
                     ("Collapsed" . "https://c.example")
                     ("Short" . "https://s.example"))))
    ;; The brackets and the label are hidden.
    (goto-char (point-min))
    (search-forward "][Log]")
    (should (cl-some (lambda (ov)
                       (and (eq (overlay-get ov 'markdown-modern-type) 'link-delim)
                            (equal (overlay-get ov 'display) "")
                            (= (overlay-end ov) (point))))
                     (overlays-at (1- (point)))))))

(ert-deftest render/reference-link-definitions-dimmed ()
  "Definitions are dimmed, also where the parser reads them as a paragraph."
  ;; After a list and after a title, the parser reads a definition as a
  ;; paragraph.  It must not be joined into one line or shown as a link.
  (markdown-modern-render-test--with
      "- item [a][]\n\n[a]: https://a.example \"A\"\n[b]: https://b.example\n"
    (should (equal (markdown-modern-render-test--link-urls)
                   '(("a" . "https://a.example"))))
    (dolist (label '("[a]:" "[b]:"))
      (goto-char (point-min))
      (search-forward label)
      (should (cl-some (lambda (ov)
                         (eq (overlay-get ov 'face) 'markdown-modern-link-url))
                       (overlays-at (line-beginning-position)))))
    (should (= (markdown-modern-render-test--count 'soft-break) 0))))

(ert-deftest render/reference-link-follows-new-definition ()
  "Typing a definition renders the links that use it elsewhere."
  (markdown-modern-render-test--with "See [the log][log].\n\n"
    (should-not (markdown-modern-render-test--link-urls))
    (goto-char (point-max))
    (markdown-modern-render-test--type "[log]: https://log.example")
    (should (equal (markdown-modern-render-test--link-urls)
                   '(("the log" . "https://log.example"))))))

(ert-deftest render/reference-link-follow-at-point ()
  "`C-c C-o' on the revealed label of a reference link follows its URL."
  (markdown-modern-render-test--with "See [the log][log] now.\n\n[log]: https://log.example\n"
    (goto-char (point-min))
    (search-forward "[lo")
    (markdown-modern-render-test--move (point))
    (let (visited)
      (cl-letf (((symbol-function 'browse-url)
                 (lambda (target &rest _) (setq visited target))))
        (markdown-modern-follow-link-at-point))
      (should (equal visited "https://log.example")))))

(defun markdown-modern-render-test--assert-code-block ()
  (markdown-modern-render-test--with "```python\nprint(1)\n```\n"
    ;; The opening/closing fences are hidden.
    (should (> (markdown-modern-render-test--count 'code-fence) 0))))

(defun markdown-modern-render-test--assert-table ()
  (markdown-modern-render-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n"
    (let ((tbl (markdown-modern-render-test--ov 'table)))
      (should tbl)
      ;; The table row is replaced by a rendered display string.
      (should (stringp (overlay-get tbl 'display))))))

(defun markdown-modern-render-test--assert-soft-breaks ()
  "Ordinary newlines flow as spaces, without changing source."
  (dolist (text '("required by\nthis project.\n"
                  "required by \n  this project.\n"
                  "required by\r\nthis project.\r\n"
                  "escaped\\\\\nbackslash\n"
                  "one\n    continuation\n"))
    (markdown-modern-render-test--with text
      (goto-char (point-min))
      (search-forward "\n")
      (should (equal (get-char-property (1- (point)) 'display) " "))
      (should (equal (buffer-substring-no-properties (point-min) (point-max))
                     text))
      ;; The final newline is a block boundary, not a soft break.
      (should-not (get-char-property (1- (point-max)) 'display)))))

(defun markdown-modern-render-test--assert-unjoined-lines ()
  "With joining off, paragraphs keep their lines and editing adds no mark."
  (let ((markdown-modern-join-paragraph-lines nil))
    (markdown-modern-render-test--with "one\ntwo **bold**\n"
      (should-not (markdown-modern-render-test--ov 'soft-break))
      ;; Inline markup still renders.
      (should (markdown-modern-render-test--ov 'strong-content))
      (markdown-modern-render-test--move 4)
      (markdown-modern-render-test--edit)
      (should-not (get-char-property 4 'display))
      (should-not (get-char-property 4 'before-string)))))

(defun markdown-modern-render-test--assert-break-boundaries ()
  "Paragraph boundaries and explicit hard breaks stay visible."
  (dolist (text '("one\n\ntwo\n" "one\n \t\ntwo\n"
                  "one  \ntwo\n" "one\\\ntwo\n"
                  "one  \r\ntwo\r\n" "one\\\r\ntwo\r\n"
                  "# Heading\nbody\n" "body\n# Heading\n"
                  "body\n---\nafter\n" "Title\n===\n"
                  "- one\n- two\n" "1. one\n2. two\n"
                  "```text\none\ntwo\n```\n"
                  "~~~\none\ntwo\n~~~\n"
                  "```text\none\ntwo\n"
                  "    one\n    two\n"
                  ">     one\n>     two\n"
                  "<div>\none\ntwo\n</div>\n"
                  "<span\nclass=\"x\">one</span>\n"
                  "text <span\nclass=\"x\">one</span>\n"
                  "text `one\ntwo` end\n"
                  "```text\none\n\ntwo\nthree\n"
                  "[ref]: https://example.com\nbody\n"))
    (markdown-modern-render-test--with text
      (goto-char (point-min))
      (while (search-forward "\n" nil t)
        (should-not (equal (get-char-property (1- (point)) 'display) " "))))))

(defun markdown-modern-render-test--assert-container-soft-breaks ()
  "Continuation lines flow within lists and quotes."
  (dolist (text '("- one\n  two\n- three\n"
                  "1. one\n   two\n2. three\n"
                  "> one\n> two\n\n> three\n"
                  "> one\ntwo\n"))
    (markdown-modern-render-test--with text
      (goto-char (point-min))
      (search-forward "one\n")
      (should (equal (get-char-property (1- (point)) 'display) " "))
      ;; Continuation indentation/quote markers are part of the hidden break.
      (when (memq (char-after) '(?\s ?>))
        (should (equal (get-char-property (point) 'display) " ")))
      (search-forward "two\n")
      (should-not (get-char-property (1- (point)) 'display)))))

(defun markdown-modern-render-test--assert-prose-after-blocks ()
  "Prose after a block still flows."
  (dolist (text '("Title\n===\none\ntwo\n"
                  "[ref]: https://example.com\none\ntwo\n"
                  "```text\ncode\n\n```\none\ntwo\n"
                  "    code\none\ntwo\n"
                  "<script>\ncode\n</script>\none\ntwo\n"
                  "<https://example.com>\none\ntwo\n"))
    (markdown-modern-render-test--with text
      (goto-char (point-min))
      (search-forward "one\n")
      (should (equal (get-char-property (1- (point)) 'display) " ")))))

(defun markdown-modern-render-test--assert-soft-break-editing ()
  "Editing a paragraph shows its source newlines."
  (dolist (text '("one\ntwo\n" "> one\n> two\n" "one \n  two\n"
                  "*one\ntwo*\n" "[one\ntwo](https://example.com)\n"))
    (markdown-modern-render-test--with text
      (goto-char (point-min))
      (search-forward "\n")
      (backward-char)
      (let ((newline (point)))
        ;; Moving into the paragraph keeps it flowed.
        (markdown-modern-render-test--move newline)
        (should (equal (get-char-property newline 'display) " "))
        (should-not (get-char-property newline 'before-string))
        (markdown-modern-render-test--edit)
        (should-not (get-char-property newline 'display))
        ;; A mark shows where the source lines will join.
        (should (equal (get-char-property newline 'before-string)
                       markdown-modern-render--newline-mark))
        (when (string-prefix-p "one" text)
          (should-not markdown-modern--revealed-region))
        ;; A re-render keeps the edited paragraph revealed.
        (markdown-modern--jit-fontify newline (1+ newline))
        (should-not (get-char-property newline 'display))
        ;; Moving within the paragraph keeps its newlines.
        (markdown-modern-render-test--move (+ newline 4))
        (should-not (get-char-property newline 'display))
        ;; Leaving the paragraph flows it again, but only after a pause.
        (markdown-modern-render-test--move (point-max))
        (should-not (get-char-property newline 'display))
        (markdown-modern-render-test--settle)
        (should (equal (get-char-property newline 'display) " "))
        (should-not (get-char-property newline 'before-string)))))
  (markdown-modern-render-test--with "one\ntwo\n"
    (goto-char 5)
    (delete-backward-char 1)
    (markdown-modern--jit-fontify (point-min) (point-max))
    (should (equal (buffer-substring-no-properties (point-min) (point-max)) "onetwo\n"))
    (should (= 0 (markdown-modern-render-test--count 'soft-break))))
  (markdown-modern-render-test--with "one\ntwo\n"
    (goto-char 4)
    (insert "  ")
    (markdown-modern--jit-fontify (point-min) (point-max))
    ;; Turning a soft break into a hard break removes the space replacement.
    (should-not (get-char-property 6 'display))
    (delete-char -1)
    (goto-char (point-max))
    (markdown-modern--jit-fontify (point-min) (point-max))
    (should (equal (get-char-property 5 'display) " "))))

(defun markdown-modern-render-test--assert-soft-break-navigation ()
  "Motion keeps a paragraph flowed, and typing shows its source lines."
  (dolist (text '("one \n  two\n" "one\n  two\n" "one\r\ntwo\r\n"))
    (markdown-modern-render-test--with text
      (save-window-excursion
        (switch-to-buffer (current-buffer))
        (add-hook 'post-command-hook #'markdown-modern--update-reveal nil t)
        (goto-char 3)
        (let ((noninteractive nil)) (execute-kbd-macro (kbd "C-f")))
        (should (eq (char-after) ?\n))
        (should (equal (get-char-property (point) 'display) " "))
        (let ((noninteractive nil)) (execute-kbd-macro (kbd "x DEL")))
        (should (equal (buffer-substring-no-properties (point-min) (point-max))
                       text))
        (should-not (get-char-property (point) 'display))
        ;; Inside the revealed paragraph, motion follows the source text.
        (search-forward "two")
        (backward-char 3)
        (let ((start (point)))
          (let ((noninteractive nil)) (execute-kbd-macro (kbd "C-b")))
          (should (= (point) (1- start))))))))

(defun markdown-modern-render-test--assert-paragraph-reveal ()
  "Only the edited paragraph shows its source newlines."
  (markdown-modern-render-test--with "one\ntwo\nthree\n\nfour\nfive\n"
    (markdown-modern-render-test--move 6)
    (should (equal (get-char-property 4 'display) " "))
    (markdown-modern-render-test--edit)
    (should-not (get-char-property 4 'display))
    (should-not (get-char-property 8 'display))
    (should (equal (get-char-property 20 'display) " "))
    ;; Coming back before the pause keeps the paragraph revealed.
    (markdown-modern-render-test--move 22)
    (markdown-modern-render-test--move 10)
    (markdown-modern-render-test--settle)
    (should-not (get-char-property 4 'display))
    ;; After a pause outside it, the paragraph flows again.
    (markdown-modern-render-test--move 22)
    (should-not (get-char-property 8 'display))
    (markdown-modern-render-test--settle)
    (should (equal (get-char-property 4 'display) " "))
    (should (equal (get-char-property 8 'display) " "))
    (should (equal (get-char-property 20 'display) " "))
    ;; Without an edit, nothing waits for a pause.
    (markdown-modern-render-test--move 6)
    (should-not (memq markdown-modern--paragraph-timer timer-idle-list))))

(defun markdown-modern-render-test--assert-paragraph-reveal-delay ()
  "With a delay, the paragraph where point rests shows its source newlines."
  (let ((markdown-modern-paragraph-reveal-delay 1))
    (markdown-modern-render-test--with "one\ntwo\nthree\n\nfour\nfive\n"
      (markdown-modern-render-test--move 22)
      (should (equal (get-char-property 20 'display) " "))
      (markdown-modern-render-test--settle)
      (should-not (get-char-property 20 'display))
      (markdown-modern-render-test--move 6)
      (should-not (get-char-property 20 'display))
      (should (equal (get-char-property 4 'display) " "))
      (markdown-modern-render-test--settle)
      (should (equal (get-char-property 20 'display) " "))
      (should-not (get-char-property 4 'display))
      (should-not (get-char-property 8 'display)))))

(defun markdown-modern-render-test--assert-list-after-paragraph ()
  "A list typed right below a paragraph does not join it."
  (markdown-modern-render-test--with "one\ntwo\n"
    (markdown-modern-render-test--move (point-max))
    (markdown-modern-render-test--type "1. bla\n")
    (should-not (get-char-property 8 'display))
    (markdown-modern-render-test--move (point-min))
    (markdown-modern-render-test--move (point-max))
    (markdown-modern-render-test--settle)
    (should (equal (get-char-property 4 'display) " "))
    (should-not (get-char-property 8 'display))))

(defun markdown-modern-render-test--assert-typing-list-item ()
  "A list item stays on its own line while it is typed."
  (markdown-modern-render-test--with "1. bla\n"
    (markdown-modern-render-test--move (point-max))
    (dolist (char (string-to-list "2. bla"))
      (insert char)
      (markdown-modern--update-reveal)
      (markdown-modern--jit-fontify (point-min) (point-max))
      (should-not (equal (get-char-property 7 'display) " ")))))

;;; Rendering tests

(ert-deftest render/math-survives-parser-migration ()
  "Both inline and display math still render through the required parser."
  (markdown-modern-render-test--with "$\\alpha$\n\n$$\nx^2\n$$\n"
    (should (markdown-modern-render-test--ov 'math-content))
    (should (markdown-modern-render-test--ov 'math-block-content))
    (should-not (markdown-modern-render-test--ov 'soft-break))))

(ert-deftest render/heading ()        (markdown-modern-render-test--assert-heading))
(ert-deftest render/strong ()         (markdown-modern-render-test--assert-strong))
(ert-deftest render/emphasis ()       (markdown-modern-render-test--assert-emphasis))
(ert-deftest render/code-span ()      (markdown-modern-render-test--assert-code-span))
(ert-deftest render/link ()           (markdown-modern-render-test--assert-link))
(ert-deftest render/code-block ()     (markdown-modern-render-test--assert-code-block))
(ert-deftest render/table ()          (markdown-modern-render-test--assert-table))
(ert-deftest render/soft-breaks ()    (markdown-modern-render-test--assert-soft-breaks))
(ert-deftest render/unjoined-lines () (markdown-modern-render-test--assert-unjoined-lines))
(ert-deftest render/break-boundaries () (markdown-modern-render-test--assert-break-boundaries))
(ert-deftest render/container-soft-breaks () (markdown-modern-render-test--assert-container-soft-breaks))
(ert-deftest render/soft-break-editing () (markdown-modern-render-test--assert-soft-break-editing))
(ert-deftest render/soft-breaks-after-blocks () (markdown-modern-render-test--assert-prose-after-blocks))
(ert-deftest render/soft-break-navigation () (markdown-modern-render-test--assert-soft-break-navigation))
(ert-deftest render/paragraph-reveal () (markdown-modern-render-test--assert-paragraph-reveal))
(ert-deftest render/paragraph-reveal-delay () (markdown-modern-render-test--assert-paragraph-reveal-delay))
(ert-deftest render/typing-list-item () (markdown-modern-render-test--assert-typing-list-item))
(ert-deftest render/list-after-paragraph () (markdown-modern-render-test--assert-list-after-paragraph))
(ert-deftest render/strikethrough () (markdown-modern-render-test--assert-strikethrough))

(ert-deftest render/soft-breaks-next-to-code ()
  "A newline right before or after inline code joins; one inside it does not."
  (dolist (case '(("one and\n`TAB` two\n" . 1)
                  ("with a `x`\nat each\n" . 1)
                  ("a `multi\nline` b\n" . 0)))
    (markdown-modern-render-test--with (car case)
      (should (= (markdown-modern-render-test--count 'soft-break) (cdr case))))))

(defun markdown-modern-render-test--visible-text ()
  "Return the buffer text that no overlay hides."
  (apply #'string
         (cl-loop for pos from (point-min) below (point-max)
                  unless (cl-some (lambda (ov) (equal (overlay-get ov 'display) ""))
                                  (overlays-at pos))
                  collect (char-after pos))))

(ert-deftest render/nested-emphasis ()
  "Bold italic, and bold inside italic, keep their text and both faces."
  (dolist (case '(("a ***both*** b\n" "a both b\n" "both")
                  ("a *it **bold** it* b\n" "a it bold it b\n" "bold")
                  ("a __bold _it_ bold__ b\n" "a bold it bold b\n" "it")))
    (markdown-modern-render-test--with (nth 0 case)
      (should (equal (markdown-modern-render-test--visible-text) (nth 1 case)))
      (goto-char (point-min))
      (search-forward (nth 2 case))
      (let ((faces (mapcar (lambda (ov) (overlay-get ov 'face))
                           (overlays-at (match-beginning 0)))))
        (should (memq 'markdown-modern-bold faces))
        (should (memq 'markdown-modern-italic faces))))))

(ert-deftest render/code-block-syntax-highlight ()
  "A code block gets per-token syntax faces when highlighting is enabled."
  (skip-unless (fboundp 'python-mode))
  (markdown-modern-render-test--with "```python\ndef greet():\n    return 1\n```\n"
    (let ((n 0))
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when (eq (overlay-get ov 'markdown-modern-type) 'code-highlight)
          (setq n (1+ n))))
      (should (> n 0)))))

(ert-deftest render/heading-marker-keeps-size ()
  "A revealed heading marker carries the heading face, not the default."
  (markdown-modern-render-test--with "## Heading\n"
    (setq markdown-modern--revealed-region (markdown-modern--markup-element-at 4))
    (markdown-modern--jit-fontify (point-min) (point-max))
    (let ((faces nil) (display nil))
      (dolist (ov (overlays-in 1 2))           ; the first #
        (when (overlay-get ov 'markdown-modern)
          (when (overlay-get ov 'face) (push (overlay-get ov 'face) faces))
          (when (overlay-get ov 'display) (setq display t))))
      (should (memq 'markdown-modern-heading-2 faces))
      (should-not display))))

(ert-deftest render/marker-reveal-bullet ()
  "Point on a list bullet reveals the source marker."
  (markdown-modern-render-test--with "- an item\n"
    (let ((r (markdown-modern--markup-element-at 1)))
      (should r)
      (should (= (char-after (car r)) ?-)))))

(defun markdown-modern-render-test--markers-at (pos)
  "Return the number of list marker overlays that start at POS."
  (cl-count-if (lambda (ov)
                 (and (eq (overlay-get ov 'markdown-modern-type) 'list-marker)
                      (= (overlay-start ov) pos)))
               (overlays-at pos)))

(ert-deftest render/list-markers-once-while-moving ()
  "Moving through a list leaves one marker per item that is not at point.
Re-hiding the bullet that point left re-renders the whole list, so each
item must lose its old marker first."
  (markdown-modern-render-test--with
      "Philosophy:  \n- Stay close.\n- Provide a way out.\n- Stay small.\n---\n"
    (let ((bullets (save-excursion
                     (goto-char (point-min))
                     (cl-loop while (re-search-forward "^- " nil t)
                              collect (match-beginning 0)))))
      (dolist (line '(1 2 3 4 5 4 3 2 1))
        (markdown-modern-render-test--move
         (save-excursion (goto-char (point-min))
                         (forward-line (1- line))
                         (point)))
        (dolist (pos bullets)
          (should (= (markdown-modern-render-test--markers-at pos)
                     (if (= pos (line-beginning-position)) 0 1))))))))

(ert-deftest render/list-item-re-render-keeps-list-whole ()
  "Re-rendering one list item renders its list once and keeps point revealed."
  (markdown-modern-render-test--with "- one\n- two\n- three\n"
    (markdown-modern-render-test--move 1)
    (should (= (markdown-modern-render-test--markers-at 1) 0))
    (let ((third (save-excursion (goto-char (point-min))
                                 (search-forward "- three")
                                 (match-beginning 0))))
      (markdown-modern--jit-fontify third (+ third 3))
      (should (= (markdown-modern-render-test--markers-at 1) 0))
      (should (= (markdown-modern-render-test--markers-at 7) 1))
      (should (= (markdown-modern-render-test--markers-at third) 1)))))

(ert-deftest render/nested-list-items ()
  "Nested items get their own marker, and bullets change glyph per level."
  (markdown-modern-render-test--with
      (concat "- one\n  - two\n    - three\n- back\n\n"
              "1. First\n   1. Nested\n\n"
              "- [ ] task\n  - [x] nested task\n")
    (let ((glyphs nil))
      (dolist (item '("- one" "- two" "- three" "- back"))
        (goto-char (point-min))
        (search-forward item)
        (let ((pos (match-beginning 0)))
          (should (= (markdown-modern-render-test--markers-at pos) 1))
          (push (cl-some (lambda (ov) (overlay-get ov 'before-string))
                         (overlays-at pos))
                glyphs)))
      (setq glyphs (mapcar (lambda (s) (string-trim (substring-no-properties s)))
                           (nreverse glyphs)))
      (should (equal (nth 0 glyphs) (nth 3 glyphs)))
      (should-not (equal (nth 0 glyphs) (nth 1 glyphs)))
      (should-not (equal (nth 1 glyphs) (nth 2 glyphs))))
    (goto-char (point-min))
    (search-forward "   1. Nested")
    (should (= (markdown-modern-render-test--markers-at (+ (match-beginning 0) 3)) 1))
    (should (= (markdown-modern-render-test--count 'checkbox) 2))))

(ert-deftest render/list-markers-stable-during-cursor-motion ()
  "Walking through lists repeatedly must not accumulate rendered markers."
  (dolist (text '("- first\n- second\n- third\n\n"
                  "- first **bold**\n- second *emphasis*\n- [ ] task\n\n"
                  "- parent **bold**\n  - nested *emphasis*\n- sibling\n\n"
                  "> - **first**\n> - second\n\n"))
    (markdown-modern-render-test--with text
      (set-buffer-modified-p nil)
      (let ((count (length markdown-modern-render--overlays))
            (tick (buffer-chars-modified-tick))
            (positions (append (number-sequence (point-min) (point-max))
                               (number-sequence (point-max) (point-min) -1))))
        (dotimes (_ 3)
          (dolist (pos positions)
            (markdown-modern-render-test--move pos)
            ;; Reveal can remove overlays, but must never add extra copies.
            (should (<= (length markdown-modern-render--overlays) count)))
          (markdown-modern-render-test--move (point-max))
          (should (= (length markdown-modern-render--overlays) count)))
        (should (equal (buffer-substring-no-properties (point-min) (point-max))
                       text))
        (should (= (buffer-chars-modified-tick) tick))
        (should-not (buffer-modified-p))))))

(ert-deftest render/partial-list-render-keeps-one-marker-per-item ()
  "Refreshing one list item must preserve sibling styling without duplicates."
  (dolist (render '(markdown-modern--jit-fontify
                    markdown-modern-render--render-region))
    (markdown-modern-render-test--with
        "- first **bold**\n- second *emphasis*\n- [ ] task\n\n"
      (let ((count (length markdown-modern-render--overlays)))
        (goto-char (point-min))
        (search-forward "emphasis")
        (dotimes (_ 3)
          (funcall render (1- (point)) (point))
          (should (= (markdown-modern-render-test--count 'list-marker) 3))
          (should (= (markdown-modern-render-test--count 'checkbox) 1))
          (should (= (markdown-modern-render-test--count 'strong-delim) 2))
          (should (= (markdown-modern-render-test--count 'emphasis-delim) 2))
          (should (= (length markdown-modern-render--overlays) count)))))))

(ert-deftest render/list-marker-pixel-alignment ()
  "Bullets and both checkbox states start their text at the same pixel."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (insert "- [x] Item\n- [ ] Item\n- Item\n\n")
      (markdown-modern-mode)
      ;; Make differences between the prose and marker fonts visible.
      (face-remap-add-relative 'variable-pitch :height 1.3)
      (goto-char (point-max))
      (markdown-modern--jit-fontify (point-min) (point-max))
      (dolist (scale '(0 2 -1))
        (text-scale-set scale)
        (redisplay t)
        (let ((positions nil))
          (save-excursion
            (goto-char (point-min))
            (while (search-forward "Item" nil t)
              (push (car (posn-x-y (posn-at-point (- (point) 4))))
                    positions)))
          (should (= (length positions) 3))
          (should (apply #'= positions))
          ;; Toggling must preserve the same layout after redisplay.
          (goto-char 3)
          (markdown-modern-space-or-toggle-checkbox 1)
          (redisplay t)
          (should (= (car positions) (car (posn-x-y (posn-at-point 7))))))))))

(ert-deftest render/list-marker-wrap-pixel-alignment ()
  "Wrapped bullet and checkbox text aligns with its first visual line."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (dolist (marker '("- " "- [ ] " "- [x] "))
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (insert marker (apply #'concat (make-list 100 "word ")) "\n\n")
        (markdown-modern-mode)
        (face-remap-add-relative 'variable-pitch :height 1.3)
        (goto-char (1+ (length marker)))
        (markdown-modern--jit-fontify (point-min) (point-max))
        (redisplay t)
        (let ((first-x (car (posn-x-y (posn-at-point)))))
          (vertical-motion 1)
          (should (= first-x (car (posn-x-y (posn-at-point))))))))))

(ert-deftest render/list-marker-reveal-pixel-alignment ()
  "Revealing an unordered marker does not move its text."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (insert "- Item\n\n")
      (markdown-modern-mode)
      (face-remap-add-relative 'variable-pitch :height 1.3)
      (goto-char (point-max))
      (markdown-modern--jit-fontify (point-min) (point-max))
      (redisplay t)
      (let ((rendered-x (car (posn-x-y (posn-at-point 3)))))
        (goto-char 1)
        (markdown-modern--update-reveal)
        (redisplay t)
        (should (= rendered-x (car (posn-x-y (posn-at-point 3)))))))))

(ert-deftest render/checkbox-not-revealed ()
  "A task checkbox is a widget, so point on it reveals no markup.
Neither the checkbox nor the task line's leading bullet is revealed."
  (markdown-modern-render-test--with "- [x] done\n"
    (should-not (markdown-modern--markup-element-at 1))   ; the -
    (should-not (markdown-modern--markup-element-at 3))   ; the [
    (should-not (markdown-modern--markup-element-at 4)))) ; the x

(ert-deftest render/checkbox-space-toggles ()
  "SPC on a rendered checkbox toggles it instead of inserting a space."
  (markdown-modern-render-test--with "- [ ] task\n"
    (goto-char 3)                        ; on the checkbox glyph
    (markdown-modern-space-or-toggle-checkbox 1)
    (should (equal (buffer-string) "- [x] task\n"))))

(ert-deftest render/checkbox-space-inserts-off-checkbox ()
  "SPC inserts a space normally when point is not on a checkbox."
  (markdown-modern-render-test--with "- [ ] task\n"
    (goto-char 9)                        ; the s of task
    (let ((last-command-event ?\s))
      (markdown-modern-space-or-toggle-checkbox 1))
    (should (equal (buffer-string) "- [ ] ta sk\n"))))

(ert-deftest render/checkbox-delete-backward-removes-checkbox ()
  "Backspace on a checkbox removes the whole checkbox, leaving a plain item."
  (markdown-modern-render-test--with "- [x] done\n"
    (goto-char 3)                        ; on the checkbox glyph
    (markdown-modern-checkbox-delete-backward 1)
    (should (equal (buffer-string) "- done\n"))))

(ert-deftest render/checkbox-delete-forward-removes-checkbox ()
  "Delete on a checkbox removes the whole checkbox, leaving a plain item."
  (markdown-modern-render-test--with "- [x] done\n"
    (goto-char 5)                        ; within the checkbox glyph
    (markdown-modern-checkbox-delete-forward 1)
    (should (equal (buffer-string) "- done\n"))))

(ert-deftest render/checkbox-delete-backward-normal-off-checkbox ()
  "Backspace off a checkbox deletes one character backward as usual."
  (markdown-modern-render-test--with "- [x] done\n"
    (goto-char 9)                        ; before the n of done
    (markdown-modern-checkbox-delete-backward 1)
    (should (equal (buffer-string) "- [x] dne\n"))))

;;; Table editing: row-level reveal, fit-to-window, pixel alignment

(ert-deftest render/table-reveal-narrows-to-row ()
  "Point inside a table reveals just the current row, not the whole block."
  (markdown-modern-render-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n"
    (let ((r (markdown-modern--markup-element-at 23)))   ; the 1 on the data row
      (should r)
      (should (markdown-modern--table-row-region-p r))
      ;; The region stays on the data row; it must not reach the earlier rows.
      (should (>= (car r) 21)))))

(ert-deftest render/non-table-block-not-narrowed ()
  "Revealing a non-table block still returns the whole multi-line block."
  (markdown-modern-render-test--with "```\nx\n```\n"
    (let ((r (markdown-modern--markup-element-at 5)))    ; the x inside the fence
      (should r)
      (should-not (markdown-modern--table-row-region-p r))
      ;; Spans more than one line (the whole fenced block).
      (should (> (- (cdr r) (car r)) 4)))))

(ert-deftest render/table-row-reveal-keeps-box ()
  "Revealing a row keeps the other rows boxed and draws the active row editable."
  (markdown-modern-render-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n"
    (setq markdown-modern--revealed-region (markdown-modern--markup-element-at 23))
    (markdown-modern--jit-fontify (point-min) (point-max))
    ;; The active row is rendered as an editable grid row, not a box string.
    (should (> (markdown-modern-render-test--count 'table-edit) 0))
    ;; The remaining rows keep their boxed display string.
    (should (> (markdown-modern-render-test--count 'table) 0))))

(ert-deftest render/table-grid-lines-have-no-display ()
  "Horizontal grid lines are independent overlays that survive reveal.
They carry a `before-string'/`after-string' and no `display', so the generic
reveal-at-point logic leaves them intact while a neighbouring row is edited."
  (markdown-modern-render-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n"
    (let ((line (markdown-modern-render-test--ov 'table-grid-line)))
      (should line)
      (should-not (overlay-get line 'display))
      (should (or (overlay-get line 'before-string)
                  (overlay-get line 'after-string))))))

(ert-deftest render/table-column-widths-fit-available ()
  "Column widths are scaled so the rendered box fits the available width."
  (let ((markdown-modern-table-max-width 24))
    (let* ((rows '(("aaaaaaaaaaaaaaaa" "bbbbbbbbbbbbbbbb")
                   ("c" "d")))
           (widths (markdown-modern-render--table-column-widths rows))
           (num-cols (length widths))
           ;; left border + one right border per column + two pad spaces per cell
           (overhead (+ 1 num-cols (* 2 num-cols))))
      (should (= num-cols 2))
      (should (<= (+ (apply #'+ widths) overhead) markdown-modern-table-max-width)))))

(ert-deftest render/table-active-row-pads-with-spaces ()
  "The active row aligns by padding cells with literal table-face spaces.
Padding with real spaces (a virtual `before-string'), rather than pixel
`:align-to', keeps columns aligned to the box at any `text-scale' zoom, where
`window-font-width' is unreliable."
  (markdown-modern-render-test--with "| name | x |\n|---|---|\n| a | b |\n"
    (goto-char (point-min))
    (forward-line 2)
    (setq markdown-modern--revealed-region
          (markdown-modern--markup-element-at (+ (point) 2)))
    (markdown-modern--jit-fontify (point-min) (point-max))
    (let ((pad nil) (align nil))
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when (eq (overlay-get ov 'markdown-modern-type) 'table-edit)
          (let ((bs (overlay-get ov 'before-string))
                (d (overlay-get ov 'display)))
            (when (and (stringp bs) (string-match-p "\\` +\\'" bs)) (setq pad t))
            (when (and (consp d) (eq (car d) 'space)) (setq align t)))))
      (should pad)              ; padding is literal spaces
      (should-not align))))     ; not pixel :align-to

(ert-deftest render/table-cell-wraps-when-narrow ()
  "A cell wider than its column wraps onto multiple lines instead of eliding."
  (let ((markdown-modern-table-max-cell-lines nil)
        (markdown-modern-table-min-column-width 4))
    (let ((block (markdown-modern-render--table-format-row '("hello world") '(6) nil)))
      (should (string-match-p "\n" block))      ; multi-line
      (should-not (string-match-p "…" block))   ; nothing elided
      ;; every visual line stays within the column's box width
      (dolist (line (split-string block "\n"))
        (should (<= (string-width line) (+ 6 2 2)))))))

(ert-deftest render/table-cell-line-cap ()
  "`markdown-modern-table-max-cell-lines' caps cell height and adds an ellipsis."
  (let ((markdown-modern-table-max-cell-lines 1))
    (let ((block (markdown-modern-render--table-format-row '("hello world foo") '(6) nil)))
      (should-not (string-match-p "\n" block))  ; capped to one line
      (should (string-match-p "…" block)))))     ; truncation marked

(ert-deftest render/table-widths-shrink-to-min-then-wrap ()
  "Wide columns shrink only to the configured minimum, leaving wrapping to fit."
  (let ((markdown-modern-table-max-width 30)
        (markdown-modern-table-min-column-width 8))
    (let ((widths (markdown-modern-render--table-column-widths
                   '(("a very long heading here" "another long heading")
                     ("x" "y")))))
      (should (= (length widths) 2))
      ;; neither column is narrowed below the configured minimum
      (should (cl-every (lambda (w) (>= w 8)) widths)))))

(ert-deftest render/table-ascii-punctuation-fold ()
  "With ASCII folding on, wide glyphs become ASCII in cells; off keeps them."
  (let ((markdown-modern-table-max-cell-lines nil))
    (let ((markdown-modern-table-ascii-punctuation t))
      (let ((block (markdown-modern-render--table-format-row '("a — b → c") '(20) nil)))
        (should (string-match-p "--" block))
        (should (string-match-p "->" block))
        (should-not (string-match-p "—" block))))
    (let ((markdown-modern-table-ascii-punctuation nil))
      (let ((block (markdown-modern-render--table-format-row '("a — b → c") '(20) nil)))
        (should (string-match-p "—" block))))))

(ert-deftest render/table-ascii-fold-keeps-width-consistent ()
  "Folding feeds both the width calc and the formatter, so columns still align."
  (let ((markdown-modern-table-ascii-punctuation t)
        (markdown-modern-table-max-width 200)
        (markdown-modern-table-min-column-width 8))
    (let* ((rows '(("x — y" "plain"))))
      ;; widths see the folded (longer) content, so the box reserves room for it
      (should (markdown-modern-render--table-column-widths rows)))))

(ert-deftest render/table-inherits-left-margin ()
  "Table overlays must not pin `line-prefix'/`wrap-prefix'.
The buffer's left-margin `wrap-prefix' reaches the embedded continuation lines
of a multi-line cell regardless of overlay overrides, so the table instead
inherits the margin uniformly (first and continuation lines alike) to stay
aligned.  Pinning it to \"\" would un-indent only the first line and skew the
wrapped lines."
  (markdown-modern-render-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n"
    (let ((ov (markdown-modern-render-test--ov 'table)))
      (should ov)
      (should (null (overlay-get ov 'line-prefix)))
      (should (null (overlay-get ov 'wrap-prefix))))))

(ert-deftest render/code-fences-preserve-line-count ()
  "Hiding the code fences must not swallow their newlines.
Both fences render as blank lines (display \"\" over the fence text only), so the
rendered block has the same number of lines as its raw source -- otherwise the
text below would shift when the fence is revealed at point."
  (markdown-modern-render-test--with "```python\nprint(1)\n```\nafter\n"
    (let ((swallowed 0) (fences 0))
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when (eq (overlay-get ov 'markdown-modern-type) 'code-fence)
          (setq fences (1+ fences))
          (when (string-match-p "\n" (buffer-substring-no-properties
                                      (overlay-start ov) (overlay-end ov)))
            (setq swallowed (1+ swallowed)))))
      (should (= fences 2))         ; opening + closing
      (should (= swallowed 0)))))   ; neither hides a line break

(ert-deftest render/table-edit-cursor-tracks-text ()
  "The active cell's text/spaces stay real; only fill is a virtual before-string.
Nothing must `display' over the cell's interior text -- if it did, point inside
it (e.g. on a space typed between words) would draw the cursor at the cell's
edge instead of next to the text.  Padding is virtual `before-string' before the
closing pipe.  Only the pipe glyphs (`│') may carry a `display'."
  (markdown-modern-render-test--with "| name | x |\n|---|---|\n| a | b |\n"
    (goto-char (point-min))
    (forward-line 2)                    ; the "| a | b |" data row
    (setq markdown-modern--revealed-region
          (markdown-modern--markup-element-at (+ (point) 2)))
    (markdown-modern--jit-fontify (point-min) (point-max))
    (let ((fill-before-strings 0) (display-over-text 0))
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when (eq (overlay-get ov 'markdown-modern-type) 'table-edit)
          (let ((bs (overlay-get ov 'before-string))
                (d (overlay-get ov 'display)))
            (when (and (stringp bs) (string-match-p "\\` +\\'" bs))
              (setq fill-before-strings (1+ fill-before-strings)))
            ;; the only display overlays may be the pipe glyphs
            (when (and (stringp d) (not (string-match-p "│" d)))
              (setq display-over-text (1+ display-over-text))))))
      (should (> fill-before-strings 0))    ; padding is virtual
      (should (= display-over-text 0)))))   ; cell text is never covered

(ert-deftest render/mermaid-fence-variants ()
  "Tree-sitter Mermaid fences deliver only the body to the SVG renderer."
  (dolist (fence '("```mermaid" "~~~mermaid" "````mermaid" "~~~ MERMAID"))
    (let ((closing (if (string-prefix-p "~" fence) "~~~~" "````")) captured)
      (cl-letf (((symbol-function 'markdown-modern-render--display-mermaid-svg)
                 (lambda (_start _end svg &optional _key) (setq captured svg))))
        (markdown-modern-render-test--with (concat fence "\nflowchart LR\nA --> B\n" closing "\n")
          (should (string-prefix-p "<svg" captured))
          (should (string-match-p ">A</text>" captured))
          (should (string-match-p ">B</text>" captured)))))))

(ert-deftest render/mermaid-unsupported-source-fallback ()
  "Unsupported Mermaid remains readable under every supported fence spelling."
  (dolist (fence '("```mermaid" "~~~mermaid" "````mermaid" "~~~ MERMAID"))
    (let* ((closing (if (string-prefix-p "~" fence) "~~~~" "````"))
           (text (concat fence "\npie\n\"Cats\" : 5\n" closing "\n")))
      (markdown-modern-render-test--with text
        (should (markdown-modern-render-test--ov 'mermaid-fallback))
        (should (equal (buffer-string) text))
        (goto-char (point-min))
        (forward-line 1)
        (should-not (cl-some (lambda (ov) (overlay-get ov 'display)) (overlays-at (point))))))))

(ert-deftest render/mermaid-theme-cache ()
  "The same diagram is rendered again after its theme colors change."
  (let ((colors '(:bg "#ffffff" :fg "#000000" :surface "#eeeeee" :border "#888888" :accent "#0000ff"))
        outputs)
    (cl-letf (((symbol-function 'markdown-modern-mermaid--theme-colors) (lambda () colors))
              ((symbol-function 'markdown-modern-render--display-mermaid-svg)
               (lambda (_start _end svg &optional _key) (push svg outputs))))
      (markdown-modern-render-test--with "```mermaid\nflowchart TD\nA --> B\n```\n"
        (let ((element (markdown-modern-ts--containing-block 16)))
          (setq colors '(:bg "#111111" :fg "#ffffff" :surface "#222222" :border "#888888" :accent "#00ffff"))
          (markdown-modern-render--mermaid element)
          (should (= 2 (length outputs)))
          (should-not (equal (car outputs) (cadr outputs))))))))

(ert-deftest render/mermaid-display-error-preserves-source ()
  "A missing SVG image backend does not hide the diagram's source."
  (cl-letf (((symbol-function 'markdown-modern-render--display-mermaid-svg)
             (lambda (&rest _) (error "No SVG backend"))))
    (markdown-modern-render-test--with "~~~mermaid\nflowchart TD\nA --> B\n~~~\n"
      (should (markdown-modern-render-test--ov 'mermaid-fallback)))))

(ert-deftest render/mermaid-failure-reported-once ()
  "A diagram that cannot be drawn is parsed and reported once, not per render."
  (let ((calls 0))
    (cl-letf* ((render (symbol-function 'markdown-modern-mermaid-render))
               ((symbol-function 'markdown-modern-mermaid-render)
                (lambda (code) (cl-incf calls) (funcall render code)))
               ((symbol-function 'message) #'ignore))
      (markdown-modern-render-test--with
          "```mermaid\nflowchart TD\nsubgraph S\nA --> B\nend\n```\n"
        (should (markdown-modern-render-test--ov 'mermaid-fallback))
        (dotimes (_ 3)
          (markdown-modern--jit-fontify (point-min) (point-max)))
        (should (markdown-modern-render-test--ov 'mermaid-fallback))
        (should (= calls 1))))))

(provide 'markdown-modern-render-test)
;;; markdown-modern-render-test.el ends here
