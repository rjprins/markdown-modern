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

(ert-deftest render/marker-reveal-checkbox ()
  "Point on a task checkbox reveals it (fallback)."
  (markdown-modern-render-test--with "- [x] done\n" nil
    (let ((r (markdown-modern--markup-element-at 3)))   ; the [
      (should r)
      (should (= (char-after (car r)) ?\[)))))

(provide 'markdown-modern-render-test)
;;; markdown-modern-render-test.el ends here
