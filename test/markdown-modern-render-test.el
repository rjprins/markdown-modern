;;; markdown-modern-render-test.el --- Overlay-output tests -*- lexical-binding: t; -*-

;; This file is part of markdown-modern.

;;; Commentary:

;; Tests that the element renderers produce the expected overlays: markers and
;; delimiters hidden (display ""), content carrying the right face.  The
;; assertions are parametrized by parser so the tree-sitter test file can reuse
;; them (see markdown-modern-ts-test.el); the tests here run them in the
;; regex-fallback mode that `make test' uses by default.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'markdown-modern)

(defmacro markdown-modern-render-test--with (text tree-sitter &rest body)
  "Render TEXT in a temp buffer and run BODY.
TREE-SITTER non-nil selects the tree-sitter parser, otherwise the regex
fallback is used."
  (declare (indent 2))
  `(with-temp-buffer
     (setq-local markdown-modern-ts--use-tree-sitter ,tree-sitter)
     (setq-local markdown-modern--rendering-enabled t)
     (markdown-modern-render--init)
     (insert ,text)
     (when ,tree-sitter (markdown-modern-ts--init))
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

;;; Parametrized assertions (TS = use tree-sitter)

(defun markdown-modern-render-test--assert-heading (ts)
  (markdown-modern-render-test--with "## A heading\n" ts
    (let ((marker (markdown-modern-render-test--ov 'heading-marker))
          (content (markdown-modern-render-test--ov 'heading-content)))
      (should marker)
      (should (equal (overlay-get marker 'display) ""))   ; ## hidden
      (should content)
      (should (eq (overlay-get content 'face) 'markdown-modern-heading-2)))))

(defun markdown-modern-render-test--assert-strong (ts)
  (markdown-modern-render-test--with "x **bold** y\n" ts
    (let ((delim (markdown-modern-render-test--ov 'strong-delim))
          (content (markdown-modern-render-test--ov 'strong-content)))
      (should delim)
      (should (equal (overlay-get delim 'display) ""))
      (should content)
      (should (eq (overlay-get content 'face) 'markdown-modern-bold)))))

(defun markdown-modern-render-test--assert-emphasis (ts)
  (markdown-modern-render-test--with "x *em* y\n" ts
    (let ((delim (markdown-modern-render-test--ov 'emphasis-delim))
          (content (markdown-modern-render-test--ov 'emphasis-content)))
      (should delim)
      (should (equal (overlay-get delim 'display) ""))
      (should content)
      (should (eq (overlay-get content 'face) 'markdown-modern-italic)))))

(defun markdown-modern-render-test--assert-code-span (ts)
  (markdown-modern-render-test--with "x `code` y\n" ts
    (let ((delim (markdown-modern-render-test--ov 'code-delim))
          (content (markdown-modern-render-test--ov 'code-content)))
      (should delim)
      (should (equal (overlay-get delim 'display) ""))
      (should content)
      (should (eq (overlay-get content 'face) 'markdown-modern-inline-code)))))

(defun markdown-modern-render-test--assert-strikethrough (ts)
  (markdown-modern-render-test--with "x ~~no~~ y\n" ts
    (let ((delim (markdown-modern-render-test--ov 'strike-delim))
          (content (markdown-modern-render-test--ov 'strike-content)))
      (should delim)
      (should (equal (overlay-get delim 'display) ""))
      (should content)
      (should (eq (overlay-get content 'face) 'markdown-modern-strikethrough)))))

(defun markdown-modern-render-test--assert-link (ts)
  (markdown-modern-render-test--with "see [text](http://x.com) ok\n" ts
    (let ((text (markdown-modern-render-test--ov 'link-text))
          (delim (markdown-modern-render-test--ov 'link-delim)))
      (should text)
      (should (eq (overlay-get text 'face) 'markdown-modern-link))
      (should delim)
      (should (equal (overlay-get delim 'display) "")))))   ; (url) hidden

(defun markdown-modern-render-test--assert-code-block (ts)
  (markdown-modern-render-test--with "```python\nprint(1)\n```\n" ts
    ;; The opening/closing fences are hidden.
    (should (> (markdown-modern-render-test--count 'code-fence) 0))))

(defun markdown-modern-render-test--assert-table (ts)
  (markdown-modern-render-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n" ts
    (let ((tbl (markdown-modern-render-test--ov 'table)))
      (should tbl)
      ;; The table row is replaced by a rendered display string.
      (should (stringp (overlay-get tbl 'display))))))

;;; Fallback-mode tests (always run)

(ert-deftest render/heading ()        (markdown-modern-render-test--assert-heading nil))
(ert-deftest render/strong ()         (markdown-modern-render-test--assert-strong nil))
(ert-deftest render/emphasis ()       (markdown-modern-render-test--assert-emphasis nil))
(ert-deftest render/code-span ()      (markdown-modern-render-test--assert-code-span nil))
(ert-deftest render/link ()           (markdown-modern-render-test--assert-link nil))
(ert-deftest render/code-block ()     (markdown-modern-render-test--assert-code-block nil))
(ert-deftest render/table ()          (markdown-modern-render-test--assert-table nil))
;; Strikethrough is only parsed on the tree-sitter path; see ts/render-* in
;; markdown-modern-ts-test.el.

(ert-deftest render/code-block-syntax-highlight ()
  "A code block gets per-token syntax faces when highlighting is enabled."
  (skip-unless (fboundp 'python-mode))
  (markdown-modern-render-test--with "```python\ndef greet():\n    return 1\n```\n" nil
    (let ((n 0))
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when (eq (overlay-get ov 'markdown-modern-type) 'code-highlight)
          (setq n (1+ n))))
      (should (> n 0)))))

(ert-deftest render/heading-marker-keeps-size ()
  "A revealed heading marker carries the heading face, not the default."
  (markdown-modern-render-test--with "## Heading\n" nil
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
  "Point on a list bullet reveals the source marker (fallback)."
  (markdown-modern-render-test--with "- an item\n" nil
    (let ((r (markdown-modern--markup-element-at 1)))
      (should r)
      (should (= (char-after (car r)) ?-)))))

(ert-deftest render/checkbox-not-revealed ()
  "A task checkbox is a widget, so point on it reveals no markup (fallback).
Neither the checkbox nor the task line's leading bullet is revealed."
  (markdown-modern-render-test--with "- [x] done\n" nil
    (should-not (markdown-modern--markup-element-at 1))   ; the -
    (should-not (markdown-modern--markup-element-at 3))   ; the [
    (should-not (markdown-modern--markup-element-at 4)))) ; the x

(ert-deftest render/checkbox-space-toggles ()
  "SPC on a rendered checkbox toggles it instead of inserting a space."
  (markdown-modern-render-test--with "- [ ] task\n" nil
    (goto-char 3)                        ; on the checkbox glyph
    (markdown-modern-space-or-toggle-checkbox 1)
    (should (equal (buffer-string) "- [x] task\n"))))

(ert-deftest render/checkbox-space-inserts-off-checkbox ()
  "SPC inserts a space normally when point is not on a checkbox."
  (markdown-modern-render-test--with "- [ ] task\n" nil
    (goto-char 9)                        ; the s of task
    (let ((last-command-event ?\s))
      (markdown-modern-space-or-toggle-checkbox 1))
    (should (equal (buffer-string) "- [ ] ta sk\n"))))

(ert-deftest render/checkbox-delete-backward-removes-checkbox ()
  "Backspace on a checkbox removes the whole checkbox, leaving a plain item."
  (markdown-modern-render-test--with "- [x] done\n" nil
    (goto-char 3)                        ; on the checkbox glyph
    (markdown-modern-checkbox-delete-backward 1)
    (should (equal (buffer-string) "- done\n"))))

(ert-deftest render/checkbox-delete-forward-removes-checkbox ()
  "Delete on a checkbox removes the whole checkbox, leaving a plain item."
  (markdown-modern-render-test--with "- [x] done\n" nil
    (goto-char 5)                        ; within the checkbox glyph
    (markdown-modern-checkbox-delete-forward 1)
    (should (equal (buffer-string) "- done\n"))))

(ert-deftest render/checkbox-delete-backward-normal-off-checkbox ()
  "Backspace off a checkbox deletes one character backward as usual."
  (markdown-modern-render-test--with "- [x] done\n" nil
    (goto-char 9)                        ; before the n of done
    (markdown-modern-checkbox-delete-backward 1)
    (should (equal (buffer-string) "- [x] dne\n"))))

;;; Table editing: row-level reveal, fit-to-window, pixel alignment

(ert-deftest render/table-reveal-narrows-to-row ()
  "Point inside a table reveals just the current row, not the whole block."
  (markdown-modern-render-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n" nil
    (let ((r (markdown-modern--markup-element-at 23)))   ; the 1 on the data row
      (should r)
      (should (markdown-modern--table-row-region-p r))
      ;; The region stays on the data row; it must not reach the earlier rows.
      (should (>= (car r) 21)))))

(ert-deftest render/non-table-block-not-narrowed ()
  "Revealing a non-table block still returns the whole multi-line block."
  (markdown-modern-render-test--with "```\nx\n```\n" nil
    (let ((r (markdown-modern--markup-element-at 5)))    ; the x inside the fence
      (should r)
      (should-not (markdown-modern--table-row-region-p r))
      ;; Spans more than one line (the whole fenced block).
      (should (> (- (cdr r) (car r)) 4)))))

(ert-deftest render/table-row-reveal-keeps-box ()
  "Revealing a row keeps the other rows boxed and draws the active row editable."
  (markdown-modern-render-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n" nil
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
  (markdown-modern-render-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n" nil
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
Padding with real spaces (rather than pixel `:align-to') keeps columns aligned
to the box at any `text-scale' zoom, where `window-font-width' is unreliable."
  (markdown-modern-render-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n" nil
    (setq markdown-modern--revealed-region (markdown-modern--markup-element-at 23))
    (markdown-modern--jit-fontify (point-min) (point-max))
    (let ((pad nil) (align nil))
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when (eq (overlay-get ov 'markdown-modern-type) 'table-edit)
          (let ((d (overlay-get ov 'display)))
            (cond ((and (stringp d) (string-match-p "\\` +\\'" d)) (setq pad t))
                  ((and (consp d) (eq (car d) 'space)) (setq align t))))))
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
  (markdown-modern-render-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n" nil
    (let ((ov (markdown-modern-render-test--ov 'table)))
      (should ov)
      (should (null (overlay-get ov 'line-prefix)))
      (should (null (overlay-get ov 'wrap-prefix))))))

(ert-deftest render/code-fences-preserve-line-count ()
  "Hiding the code fences must not swallow their newlines.
Both fences render as blank lines (display \"\" over the fence text only), so the
rendered block has the same number of lines as its raw source -- otherwise the
text below would shift when the fence is revealed at point."
  (markdown-modern-render-test--with "```python\nprint(1)\n```\nafter\n" nil
    (let ((swallowed 0) (fences 0))
      (dolist (ov (overlays-in (point-min) (point-max)))
        (when (eq (overlay-get ov 'markdown-modern-type) 'code-fence)
          (setq fences (1+ fences))
          (when (string-match-p "\n" (buffer-substring-no-properties
                                      (overlay-start ov) (overlay-end ov)))
            (setq swallowed (1+ swallowed)))))
      (should (= fences 2))         ; opening + closing
      (should (= swallowed 0)))))   ; neither hides a line break

(provide 'markdown-modern-render-test)
;;; markdown-modern-render-test.el ends here
