;;; markdown-modern-jit-test.el --- Tests for jit-lock rendering and reveal -*- lexical-binding: t; -*-

;; This file is part of markdown-modern.

;;; Commentary:

;; Tests for the jit-lock fontify entry point, block-level region extension,
;; reveal-at-point element detection, the reveal guard, and the mermaid image
;; cache.  These exercise the regex-fallback parser (the default), so they run
;; without the markdown tree-sitter grammar installed.

;;; Code:

(require 'ert)
(require 'markdown-modern)

(defmacro markdown-modern-jit-test--with-buffer (text &rest body)
  "Insert TEXT in a temp buffer in regex-fallback mode and run BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (setq-local markdown-modern-ts--use-tree-sitter nil)
     (setq-local markdown-modern--rendering-enabled t)
     (markdown-modern-render--init)
     (insert ,text)
     (goto-char (point-min))
     ,@body))

(defun markdown-modern-jit-test--markdown-modern-overlays (start end)
  "Return markdown-modern overlays overlapping START..END."
  (seq-filter (lambda (ov) (overlay-get ov 'markdown-modern))
              (overlays-in start end)))

;;; jit-lock fontify entry

(ert-deftest jit/fontify-returns-bounds-and-renders ()
  "`markdown-modern--jit-fontify' renders overlays and returns a jit-lock-bounds cons."
  (markdown-modern-jit-test--with-buffer "# Heading\n\nSome **bold** text.\n"
    (let ((result (markdown-modern--jit-fontify (point-min) (point-max))))
      (should (eq (car result) 'jit-lock-bounds))
      (should (integerp (cadr result)))
      (should (integerp (cddr result)))
      (should (> (length (markdown-modern-jit-test--markdown-modern-overlays
                          (point-min) (point-max)))
                 0)))))

(ert-deftest jit/fontify-disabled-renders-nothing ()
  "With rendering disabled the fontify function does no work."
  (markdown-modern-jit-test--with-buffer "# Heading\n"
    (setq-local markdown-modern--rendering-enabled nil)
    (should-not (markdown-modern--jit-fontify (point-min) (point-max)))
    (should (= 0 (length (markdown-modern-jit-test--markdown-modern-overlays
                          (point-min) (point-max)))))))

;;; Block-level region extension

(ert-deftest jit/extend-region-covers-fenced-block ()
  "A sub-range inside a fenced code block expands to the whole block."
  (markdown-modern-jit-test--with-buffer
      "before\n\n```python\nline1\nline2\nline3\n```\n\nafter\n"
    (let* ((fence-open (progn (goto-char (point-min))
                              (search-forward "```python")
                              (match-beginning 0)))
           (mid (progn (search-forward "line2") (match-beginning 0)))
           (bounds (markdown-modern--extend-region-to-blocks mid mid)))
      ;; The extended region must include the opening fence and the closing one.
      (should (<= (car bounds) fence-open))
      (should (>= (cdr bounds)
                  (progn (goto-char (point-max))
                         (search-backward "```")
                         (match-end 0)))))))

;;; Reveal-at-point granularity (fallback parser)

(ert-deftest jit/markup-element-at-heading ()
  "Point on a heading reveals the whole heading block."
  (markdown-modern-jit-test--with-buffer "# Heading One\n\nbody\n"
    (goto-char 4) ;; inside "Heading"
    (let ((r (markdown-modern--markup-element-at (point))))
      (should r)
      (should (= (car r) 1))
      ;; spans at least through the heading text
      (should (>= (cdr r) 13)))))

(ert-deftest jit/markup-element-at-emphasis ()
  "Point inside emphasis reveals just that inline span, not the paragraph."
  (markdown-modern-jit-test--with-buffer "plain *emph* word\n"
    (let ((star (progn (goto-char (point-min)) (search-forward "*emph") (match-beginning 0))))
      (goto-char (1+ star)) ;; inside the emphasis run
      (let ((r (markdown-modern--markup-element-at (point))))
        (should r)
        ;; The span is the emphasis element, much smaller than the whole line.
        (should (< (- (cdr r) (car r)) 10))
        (should (<= (car r) star))))))

(ert-deftest jit/markup-element-at-plain-prose-is-nil ()
  "Point in plain prose reveals nothing."
  (markdown-modern-jit-test--with-buffer "just some plain words here\n"
    (goto-char 6)
    (should-not (markdown-modern--markup-element-at (point)))))

;;; Reveal keeps styling

(ert-deftest jit/reveal-shows-markup-but-keeps-styling ()
  "Revealing an element shows its raw markers but preserves its face.
After reveal there must be no marker-hiding (display) overlays in the span,
but the styling face overlay (bold) must remain."
  (markdown-modern-jit-test--with-buffer "text **bold** end\n"
    (let* ((pos (progn (goto-char (point-min)) (search-forward "bold") (match-beginning 0)))
           (region (markdown-modern--markup-element-at pos)))
      (should region)
      (setq markdown-modern--revealed-region region)
      ;; Re-render the whole buffer the way jit-lock would on scroll; the
      ;; reveal guard should re-reveal markup while keeping faces.
      (markdown-modern--jit-fontify (point-min) (point-max))
      (let ((display-ovs 0) (face-ovs 0))
        (dolist (ov (markdown-modern-jit-test--markdown-modern-overlays (car region) (cdr region)))
          (when (overlay-get ov 'display) (setq display-ovs (1+ display-ovs)))
          (when (and (overlay-get ov 'face) (not (overlay-get ov 'display)))
            (setq face-ovs (1+ face-ovs))))
        ;; Markers are visible (no display overlays hide them) ...
        (should (= display-ovs 0))
        ;; ... but the bold styling is preserved.
        (should (> face-ovs 0))))))

;;; Mermaid image cache idempotency

(ert-deftest jit/mermaid-image-is-cached ()
  "Rendering the same SVG twice reuses the cached image object."
  (markdown-modern-jit-test--with-buffer "xxxxx\n"
    (let ((svg "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")
          img1 img2)
      (markdown-modern-render--display-mermaid-svg 1 2 svg "k")
      (setq img1 (overlay-get (car (markdown-modern-jit-test--markdown-modern-overlays 1 2)) 'display))
      (markdown-modern-render--display-mermaid-svg 1 2 svg "k")
      (setq img2 (overlay-get (car (markdown-modern-jit-test--markdown-modern-overlays 1 2)) 'display))
      (should img1)
      (should (eq img1 img2)))))

;;; Inline markup inside headings (tree-sitter path)

(ert-deftest jit/heading-renders-inline-code-span ()
  "Inline code spans inside a heading are rendered (backticks hidden).
This is the tree-sitter path: the regex fallback emits the span separately,
but under tree-sitter the heading must descend into its own inline markup."
  (skip-unless (and (treesit-language-available-p 'markdown)
                    (treesit-language-available-p 'markdown-inline)))
  (with-temp-buffer
    (setq-local markdown-modern--rendering-enabled t)
    (markdown-modern-render--init)
    (insert "## A `code` and `more` heading\n")
    (setq-local markdown-modern-ts--use-tree-sitter t)
    (markdown-modern-ts--init)
    (markdown-modern--jit-fontify (point-min) (point-max))
    (let ((delims 0) (contents 0))
      (dolist (ov (overlays-in (point-min) (point-max)))
        (pcase (overlay-get ov 'markdown-modern-type)
          ('code-delim (setq delims (1+ delims)))
          ('code-content (setq contents (1+ contents)))))
      ;; Two spans: 4 hidden delimiter overlays, 2 styled content overlays.
      (should (= delims 4))
      (should (= contents 2)))))

(provide 'markdown-modern-jit-test)
;;; markdown-modern-jit-test.el ends here
