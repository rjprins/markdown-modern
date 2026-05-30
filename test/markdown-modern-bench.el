;;; markdown-modern-bench.el --- Rendering benchmarks -*- lexical-binding: t; -*-

;; This file is part of markdown-modern.

;;; Commentary:

;; Not an ERT suite -- a manual benchmark.  Run with:
;;
;;   make bench
;;
;; or:  emacs -Q -batch -L lisp -L test -l markdown-modern-bench \
;;            --eval '(markdown-modern-bench)'
;;
;; It generates synthetic Markdown of increasing size and reports, for each
;; parser:
;;   viewport(ms) - time to fontify a ~60-line window (what jit-lock runs on
;;                  open/scroll).  This is the number that matters in practice
;;                  and should stay ~flat as the file grows.
;;   full(ms)     - time to render the WHOLE buffer at once (export-like worst
;;                  case; grows with size, and includes code-block syntax
;;                  highlighting).
;;   reveal(ms)   - time to compute the markup element at point (the per-command
;;                  reveal cost).

;;; Code:

(require 'markdown-modern)
(require 'benchmark)
(require 'cl-lib)

(defun markdown-modern-bench--section (i)
  "Return one representative Markdown section numbered I (~20 lines)."
  (format "## Section %d

This is a paragraph with **bold**, *italic*, `inline code`, ~~strike~~ and a
[link](https://example.com/%d) plus some trailing prose to fill the line out
to a realistic width for a documentation paragraph.

- first bullet with `code`
- second bullet with *emphasis*
- third bullet with a [link](https://example.com/x)

| Name  | Kind | Note     |
|-------|------|----------|
| alpha | %d   | rendered |
| beta  | %d   | rendered |

```python
def f_%d(x):
    return x * %d
```

" i i i i i i))

(defun markdown-modern-bench--doc (sections)
  "Return a Markdown string of SECTIONS sections."
  (mapconcat #'markdown-modern-bench--section
             (number-sequence 1 sections) ""))

(defun markdown-modern-bench--prep (text ts)
  "Return a fresh buffer containing TEXT, parser ready (TS non-nil = tree-sitter)."
  (let ((buf (generate-new-buffer " *mm-bench*")))
    (with-current-buffer buf
      (setq-local markdown-modern-ts--use-tree-sitter ts)
      (setq-local markdown-modern--rendering-enabled t)
      (markdown-modern-render--init)
      (insert text)
      (when ts (markdown-modern-ts--init)))
    buf))

(defun markdown-modern-bench--viewport ()
  "Return (START . END) for ~60 lines around the middle of the buffer."
  (save-excursion
    (goto-char (/ (point-max) 2))
    (forward-line 0)
    (let ((start (point)))
      (forward-line 60)
      (cons start (point)))))

(defun markdown-modern-bench--one (sections ts)
  "Benchmark a SECTIONS-section doc with parser TS; return a result plist."
  (let ((buf (markdown-modern-bench--prep (markdown-modern-bench--doc sections) ts)))
    (unwind-protect
        (with-current-buffer buf
          (let* ((lines (count-lines (point-min) (point-max)))
                 (kb (/ (buffer-size) 1024.0))
                 (vp (markdown-modern-bench--viewport))
                 ;; Warm the parser once, then average several viewport renders.
                 (_ (markdown-modern--jit-fontify (car vp) (cdr vp)))
                 (t-view (/ (car (benchmark-run 20
                                   (markdown-modern--jit-fontify (car vp) (cdr vp))))
                            20.0))
                 (t-reveal (progn
                             (goto-char (car vp))
                             (/ (car (benchmark-run 200
                                       (markdown-modern--markup-element-at (point))))
                                200.0)))
                 (t-full (car (benchmark-run 1
                                (markdown-modern--jit-fontify (point-min) (point-max))))))
            (list :lines lines :kb kb :view t-view :reveal t-reveal :full t-full)))
      (kill-buffer buf))))

;;;###autoload
(defun markdown-modern-bench (&optional sizes)
  "Run the rendering benchmark over SIZES (section counts) and print a table."
  (interactive)
  (let ((sizes (or sizes '(25 125 500 1250))))   ; ~500, 2.5k, 10k, 25k lines
    (dolist (ts '(nil t))
      (when (or (not ts)
                (and (treesit-language-available-p 'markdown)
                     (treesit-language-available-p 'markdown-inline)))
        (princ (format "\n=== parser: %s ===\n"
                       (if ts "tree-sitter" "regex fallback")))
        (princ (format "%8s %7s | %13s %11s %11s\n"
                       "lines" "KB" "viewport(ms)" "full(ms)" "reveal(ms)"))
        (princ (make-string 60 ?-)) (princ "\n")
        (dolist (n sizes)
          (let ((r (markdown-modern-bench--one n ts)))
            (princ (format "%8d %7d | %13.2f %11.0f %11.3f\n"
                           (plist-get r :lines)
                           (round (plist-get r :kb))
                           (* 1000 (plist-get r :view))
                           (* 1000 (plist-get r :full))
                           (* 1000 (plist-get r :reveal))))))))
    (princ "\n")))

(provide 'markdown-modern-bench)
;;; markdown-modern-bench.el ends here
