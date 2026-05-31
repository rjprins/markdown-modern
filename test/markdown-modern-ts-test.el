;;; markdown-modern-ts-test.el --- Tree-sitter parser-path tests -*- lexical-binding: t; -*-

;; This file is part of markdown-modern.

;;; Commentary:

;; Exercises the tree-sitter parsing path: element detection mirroring the
;; regex-fallback coverage, plus a re-run of the renderer overlay assertions
;; (from markdown-modern-render-test) under tree-sitter.  Every test is
;; `skip-unless' the markdown grammars are installed, so the suite still passes
;; in environments without them.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'markdown-modern)
(require 'markdown-modern-render-test)

(defmacro markdown-modern-ts-test--deftest (name &rest body)
  "Define ERT test NAME guarded on the markdown tree-sitter grammars."
  (declare (indent 1))
  `(ert-deftest ,name ()
     (skip-unless (and (treesit-language-available-p 'markdown)
                       (treesit-language-available-p 'markdown-inline)))
     ,@body))

(defmacro markdown-modern-ts-test--with (text &rest body)
  "Insert TEXT in a temp buffer with tree-sitter parsers, then run BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (setq-local markdown-modern-ts--use-tree-sitter t)
     (insert ,text)
     (markdown-modern-ts--init)
     ,@body))

(defun markdown-modern-ts-test--block-type-at (needle)
  "Return the block element type at the start of NEEDLE in the buffer."
  (goto-char (point-min))
  (search-forward needle)
  (goto-char (match-beginning 0))
  (let ((b (markdown-modern-ts--containing-block (point))))
    (and b (markdown-modern-node-type b))))

(defun markdown-modern-ts-test--inline-types ()
  "Return the list of inline element types found in the buffer."
  (mapcar #'markdown-modern-node-type
          (markdown-modern-ts--inline-elements-in (point-min) (point-max))))

;;; Element detection (mirrors regex coverage on the tree-sitter path)

(markdown-modern-ts-test--deftest ts/heading-detected
  (markdown-modern-ts-test--with "## A heading\n\nbody\n"
    (goto-char 4)
    (let ((b (markdown-modern-ts--containing-block (point))))
      (should (eq (markdown-modern-node-type b) 'heading))
      (should (eq (markdown-modern-node-level b) 2)))))

(markdown-modern-ts-test--deftest ts/paragraph-detected
  (markdown-modern-ts-test--with "## H\n\njust prose here\n"
    (should (eq (markdown-modern-ts-test--block-type-at "prose") 'paragraph))))

(markdown-modern-ts-test--deftest ts/code-block-language
  ;; Use the block query (elements-in-region), not containing-block: node-at
  ;; inside a fence returns a parentless block_continuation in this grammar.
  (markdown-modern-ts-test--with "```python\nprint(1)\n```\n"
    (let ((cb (cl-find 'code-block
                       (markdown-modern-ts--elements-in-region (point-min) (point-max))
                       :key #'markdown-modern-node-type)))
      (should cb)
      (should (equal (markdown-modern-node-language cb) "python")))))

(markdown-modern-ts-test--deftest ts/table-detected
  (markdown-modern-ts-test--with "| a | b |\n|---|---|\n| 1 | 2 |\n"
    (should (eq (markdown-modern-ts-test--block-type-at "1") 'table))))

(markdown-modern-ts-test--deftest ts/list-detected
  (markdown-modern-ts-test--with "- one\n- two\n"
    (should (memq (markdown-modern-ts-test--block-type-at "one")
                  '(list list-item paragraph)))))

(markdown-modern-ts-test--deftest ts/inline-emphasis-and-strong
  (markdown-modern-ts-test--with "a *em* and **bold** end\n"
    (let ((types (markdown-modern-ts-test--inline-types)))
      (should (memq 'emphasis types))
      (should (memq 'strong types)))))

(markdown-modern-ts-test--deftest ts/inline-code-and-strike-and-link
  (markdown-modern-ts-test--with "`c` ~~x~~ [t](http://x.com)\n"
    (let ((types (markdown-modern-ts-test--inline-types)))
      (should (memq 'code-span types))
      (should (memq 'strikethrough types))
      (should (memq 'link types)))))

(markdown-modern-ts-test--deftest ts/inline-image
  (markdown-modern-ts-test--with "![alt](img.png)\n"
    (should (memq 'image (markdown-modern-ts-test--inline-types)))))

;;; Block-bounds expansion

(markdown-modern-ts-test--deftest ts/containing-block-bounds-covers-table
  (markdown-modern-ts-test--with "before\n\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n\nafter\n"
    (goto-char (point-min))
    (search-forward "3")                ; a cell in the last data row
    (let* ((mid (match-beginning 0))
           (bounds (markdown-modern-ts--containing-block-bounds mid mid))
           (tbl-start (progn (goto-char (point-min)) (search-forward "| a") (match-beginning 0))))
      ;; Expanding from one cell must cover the whole table, back to row 1.
      (should (<= (car bounds) tbl-start)))))

;;; Literal content inside code spans (no nested inline parsing)

(markdown-modern-ts-test--deftest ts/code-span-content-is-literal
  (markdown-modern-ts-test--with "`*not emph*` and *really emph*\n"
    (let ((types (markdown-modern-ts-test--inline-types)))
      (should (memq 'code-span types))
      ;; Exactly one emphasis: the real one outside the code span, not the
      ;; asterisks inside it.
      (should (= 1 (cl-count 'emphasis types))))))

;;; Renderer overlay output, re-run under tree-sitter

(markdown-modern-ts-test--deftest ts/render-heading       (markdown-modern-render-test--assert-heading t))
(markdown-modern-ts-test--deftest ts/render-strong        (markdown-modern-render-test--assert-strong t))
(markdown-modern-ts-test--deftest ts/render-emphasis      (markdown-modern-render-test--assert-emphasis t))
(markdown-modern-ts-test--deftest ts/render-code-span     (markdown-modern-render-test--assert-code-span t))
(markdown-modern-ts-test--deftest ts/render-strikethrough (markdown-modern-render-test--assert-strikethrough t))
(markdown-modern-ts-test--deftest ts/render-link          (markdown-modern-render-test--assert-link t))
(markdown-modern-ts-test--deftest ts/render-code-block    (markdown-modern-render-test--assert-code-block t))
(markdown-modern-ts-test--deftest ts/render-table         (markdown-modern-render-test--assert-table t))

;;; Line-leading markers revealed at point

(markdown-modern-ts-test--deftest ts/marker-reveal-bullet
  (markdown-modern-ts-test--with "- item\n"
    (let ((r (markdown-modern--markup-element-at 1)))
      (should r)
      (should (= (char-after (car r)) ?-)))))

(markdown-modern-ts-test--deftest ts/marker-reveal-ordered
  (markdown-modern-ts-test--with "1. item\n"
    (let ((r (markdown-modern--markup-element-at 1)))
      (should r)
      (should (= (char-after (car r)) ?1)))))

(markdown-modern-ts-test--deftest ts/checkbox-not-revealed
  (markdown-modern-ts-test--with "- [ ] task\n"
    ;; A checkbox is a widget; neither it nor the task line's bullet reveals.
    (should-not (markdown-modern--markup-element-at 1))    ; the -
    (should-not (markdown-modern--markup-element-at 3))))  ; the [

(markdown-modern-ts-test--deftest ts/marker-reveal-blockquote
  (markdown-modern-ts-test--with "> quoted\n"
    (let ((r (markdown-modern--markup-element-at 1)))
      (should r)
      (should (= (char-after (car r)) ?>)))))

(markdown-modern-ts-test--deftest ts/marker-not-in-plain-text
  (markdown-modern-ts-test--with "- item text\n"
    ;; Point in the item's plain text reveals nothing.
    (should-not (markdown-modern--markup-element-at 6))))

(provide 'markdown-modern-ts-test)
;;; markdown-modern-ts-test.el ends here
