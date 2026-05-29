;;; mark-graf-jit-test.el --- Tests for jit-lock rendering and reveal -*- lexical-binding: t; -*-

;; This file is part of mark-graf.

;;; Commentary:

;; Tests for the jit-lock fontify entry point, block-level region extension,
;; reveal-at-point element detection, the reveal guard, and the mermaid image
;; cache.  These exercise the regex-fallback parser (the default), so they run
;; without the markdown tree-sitter grammar installed.

;;; Code:

(require 'ert)
(require 'mark-graf)

(defmacro mark-graf-jit-test--with-buffer (text &rest body)
  "Insert TEXT in a temp buffer in regex-fallback mode and run BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (setq-local mark-graf-ts--use-tree-sitter nil)
     (setq-local mark-graf--rendering-enabled t)
     (mark-graf-render--init)
     (insert ,text)
     (goto-char (point-min))
     ,@body))

(defun mark-graf-jit-test--mark-graf-overlays (start end)
  "Return mark-graf overlays overlapping START..END."
  (seq-filter (lambda (ov) (overlay-get ov 'mark-graf))
              (overlays-in start end)))

;;; jit-lock fontify entry

(ert-deftest jit/fontify-returns-bounds-and-renders ()
  "`mark-graf--jit-fontify' renders overlays and returns a jit-lock-bounds cons."
  (mark-graf-jit-test--with-buffer "# Heading\n\nSome **bold** text.\n"
    (let ((result (mark-graf--jit-fontify (point-min) (point-max))))
      (should (eq (car result) 'jit-lock-bounds))
      (should (integerp (cadr result)))
      (should (integerp (cddr result)))
      (should (> (length (mark-graf-jit-test--mark-graf-overlays
                          (point-min) (point-max)))
                 0)))))

(ert-deftest jit/fontify-disabled-renders-nothing ()
  "With rendering disabled the fontify function does no work."
  (mark-graf-jit-test--with-buffer "# Heading\n"
    (setq-local mark-graf--rendering-enabled nil)
    (should-not (mark-graf--jit-fontify (point-min) (point-max)))
    (should (= 0 (length (mark-graf-jit-test--mark-graf-overlays
                          (point-min) (point-max)))))))

;;; Block-level region extension

(ert-deftest jit/extend-region-covers-fenced-block ()
  "A sub-range inside a fenced code block expands to the whole block."
  (mark-graf-jit-test--with-buffer
      "before\n\n```python\nline1\nline2\nline3\n```\n\nafter\n"
    (let* ((fence-open (progn (goto-char (point-min))
                              (search-forward "```python")
                              (match-beginning 0)))
           (mid (progn (search-forward "line2") (match-beginning 0)))
           (bounds (mark-graf--extend-region-to-blocks mid mid)))
      ;; The extended region must include the opening fence and the closing one.
      (should (<= (car bounds) fence-open))
      (should (>= (cdr bounds)
                  (progn (goto-char (point-max))
                         (search-backward "```")
                         (match-end 0)))))))

;;; Reveal-at-point granularity (fallback parser)

(ert-deftest jit/markup-element-at-heading ()
  "Point on a heading reveals the whole heading block."
  (mark-graf-jit-test--with-buffer "# Heading One\n\nbody\n"
    (goto-char 4) ;; inside "Heading"
    (let ((r (mark-graf--markup-element-at (point))))
      (should r)
      (should (= (car r) 1))
      ;; spans at least through the heading text
      (should (>= (cdr r) 13)))))

(ert-deftest jit/markup-element-at-emphasis ()
  "Point inside emphasis reveals just that inline span, not the paragraph."
  (mark-graf-jit-test--with-buffer "plain *emph* word\n"
    (let ((star (progn (goto-char (point-min)) (search-forward "*emph") (match-beginning 0))))
      (goto-char (1+ star)) ;; inside the emphasis run
      (let ((r (mark-graf--markup-element-at (point))))
        (should r)
        ;; The span is the emphasis element, much smaller than the whole line.
        (should (< (- (cdr r) (car r)) 10))
        (should (<= (car r) star))))))

(ert-deftest jit/markup-element-at-plain-prose-is-nil ()
  "Point in plain prose reveals nothing."
  (mark-graf-jit-test--with-buffer "just some plain words here\n"
    (goto-char 6)
    (should-not (mark-graf--markup-element-at (point)))))

;;; Reveal guard under re-render

(ert-deftest jit/reveal-guard-keeps-element-raw ()
  "A revealed element stays markup-visible after a jit-lock re-render."
  (mark-graf-jit-test--with-buffer "text **bold** end\n"
    (let* ((pos (progn (goto-char (point-min)) (search-forward "bold") (match-beginning 0)))
           (region (mark-graf--markup-element-at pos)))
      (should region)
      (setq mark-graf--revealed-region region)
      ;; Re-render the whole buffer the way jit-lock would on scroll.
      (mark-graf--jit-fontify (point-min) (point-max))
      ;; The guard must have cleared overlays inside the revealed span, so the
      ;; raw markup (** delimiters) is visible there.
      (should (= 0 (length (mark-graf-jit-test--mark-graf-overlays
                            (car region) (cdr region))))))))

;;; Mermaid image cache idempotency

(ert-deftest jit/mermaid-image-is-cached ()
  "Rendering the same SVG twice reuses the cached image object."
  (mark-graf-jit-test--with-buffer "xxxxx\n"
    (let ((svg "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>")
          img1 img2)
      (mark-graf-render--display-mermaid-svg 1 2 svg "k")
      (setq img1 (overlay-get (car (mark-graf-jit-test--mark-graf-overlays 1 2)) 'display))
      (mark-graf-render--display-mermaid-svg 1 2 svg "k")
      (setq img2 (overlay-get (car (mark-graf-jit-test--mark-graf-overlays 1 2)) 'display))
      (should img1)
      (should (eq img1 img2)))))

(provide 'mark-graf-jit-test)
;;; mark-graf-jit-test.el ends here
