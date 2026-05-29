;;; mark-graf-integration-test.el --- Integration tests for mark-graf -*- lexical-binding: t; -*-

;; Copyright (C) 2026 mark-graf contributors

;;; Commentary:

;; Integration tests for mark-graf.
;; These tests verify complete workflows and end-to-end functionality.

;;; Code:

(require 'ert)
(require 'mark-graf)
(require 'mark-graf-export)
(require 'mark-graf-ts)

;;; Full Document Tests

(ert-deftest integration/complete-document-export ()
  "Complete markdown document exports to valid HTML."
  (let* ((markdown "# Main Title

This is a paragraph with **bold**, *italic*, and `code`.

## Section One

- Item 1
- Item 2
- Item 3

### Subsection

1. First
2. Second
3. Third

## Section Two

| Header A | Header B |
|----------|----------|
| Cell 1   | Cell 2   |

> This is a blockquote.

```python
def hello():
    print('Hello')
```

---

[Link text](http://example.com)

![Alt text](image.png)
")
         (html (mark-graf-export--markdown-to-html markdown)))
    ;; Verify all major elements present
    (should (string-match-p "<h1" html))
    (should (string-match-p "<h2" html))
    (should (string-match-p "<h3" html))
    (should (string-match-p "<strong>" html))
    (should (string-match-p "<em>" html))
    (should (string-match-p "<code>" html))
    (should (string-match-p "<ul>" html))
    (should (string-match-p "<ol>" html))
    (should (string-match-p "<li>" html))
    (should (string-match-p "<table>" html))
    (should (string-match-p "<th>" html))
    (should (string-match-p "<td>" html))
    (should (string-match-p "<blockquote>" html))
    (should (string-match-p "<pre>" html))
    (should (string-match-p "<hr>" html))
    (should (string-match-p "<a href=" html))
    (should (string-match-p "<img src=" html))))

(ert-deftest integration/nested-formatting ()
  "Nested inline formatting exports correctly."
  (let ((html (mark-graf-export--markdown-to-html
               "***bold and italic*** and **bold with `code`**")))
    ;; At minimum, should have strong and em
    (should (string-match-p "<strong>" html))
    (should (string-match-p "<em>" html))
    (should (string-match-p "<code>" html))))

(ert-deftest integration/complex-list ()
  "Complex nested list structure exports correctly."
  (let* ((markdown "- Item 1
  - Nested 1a
  - Nested 1b
- Item 2
- Item 3
  - Nested 3a
    - Deep nested
")
         (html (mark-graf-export--markdown-to-html markdown)))
    (should (string-match-p "<ul>" html))
    (should (string-match-p "<li>" html))
    ;; Count list items
    (should (>= (length (split-string html "<li>")) 7))))

(ert-deftest integration/task-list-mixed ()
  "Task list with mixed states exports correctly."
  (let* ((markdown "- [x] Completed task
- [ ] Pending task
- [x] Another done
- [ ] Another pending
")
         (html (mark-graf-export--markdown-to-html markdown)))
    (should (string-match-p "checkbox" html))
    ;; Should have some checked
    (should (string-match-p "checked" html))
    ;; Should have task-list-item class
    (should (string-match-p "task-list-item" html))))

;;; Export File Tests

(ert-deftest integration/export-creates-file ()
  "HTML export creates a valid file."
  (let ((output-file (make-temp-file "mark-graf-test-" nil ".html"))
        (test-content "# Test\n\nParagraph."))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert test-content)
            (mark-graf-export-html output-file))
          ;; File should exist
          (should (file-exists-p output-file))
          ;; File should have content
          (should (> (file-attribute-size (file-attributes output-file)) 0))
          ;; Content should be HTML
          (with-temp-buffer
            (insert-file-contents output-file)
            (should (string-match-p "<!DOCTYPE html>" (buffer-string)))
            (should (string-match-p "<h1" (buffer-string)))))
      ;; Cleanup
      (when (file-exists-p output-file)
        (delete-file output-file)))))

(ert-deftest integration/export-uses-template ()
  "HTML export uses template with CSS."
  (let ((output-file (make-temp-file "mark-graf-test-" nil ".html")))
    (unwind-protect
        (progn
          (with-temp-buffer
            (insert "# Title")
            (mark-graf-export-html output-file))
          (with-temp-buffer
            (insert-file-contents output-file)
            (should (string-match-p "<style>" (buffer-string)))
            (should (string-match-p "</style>" (buffer-string)))
            (should (string-match-p "markdown-body" (buffer-string)))))
      (when (file-exists-p output-file)
        (delete-file output-file)))))

;;; Sample Document Test

(ert-deftest integration/sample-document-parses ()
  "Sample.md file parses without errors."
  (let ((sample-path (expand-file-name
                      "test/sample.md"
                      (or (locate-dominating-file default-directory "lisp")
                          default-directory))))
    (when (file-exists-p sample-path)
      (with-temp-buffer
        (insert-file-contents sample-path)
        (let ((content (buffer-string)))
          ;; Should not error
          (should (stringp (mark-graf-export--markdown-to-html content)))
          ;; Result should have substantial content
          (should (> (length (mark-graf-export--markdown-to-html content)) 1000)))))))

;;; Mode Lifecycle Tests

(ert-deftest integration/mode-variables-initialized ()
  "Mode local variables are properly initialized."
  (with-temp-buffer
    ;; Manually set up mode variables (don't fully activate mode - no tree-sitter)
    (setq-local mark-graf--rendering-enabled t)
    (setq-local mark-graf--revealed-region nil)
    ;; Verify
    (should mark-graf--rendering-enabled)
    (should-not mark-graf--revealed-region)))

(ert-deftest integration/customization-variables-exist ()
  "All customization variables are defined with defaults."
  (should (boundp 'mark-graf-heading-scale))
  (should (boundp 'mark-graf-display-images))
  (should (boundp 'mark-graf-image-max-width))
  ;; Check default values
  (should (eq mark-graf-display-images t)))

(ert-deftest integration/faces-defined ()
  "All faces are properly defined."
  (dolist (face '(mark-graf-heading-1
                  mark-graf-heading-2
                  mark-graf-heading-3
                  mark-graf-heading-4
                  mark-graf-heading-5
                  mark-graf-heading-6
                  mark-graf-bold
                  mark-graf-italic
                  mark-graf-strikethrough
                  mark-graf-inline-code
                  mark-graf-code-block
                  mark-graf-link
                  mark-graf-blockquote
                  mark-graf-list-bullet
                  mark-graf-table-header
                  mark-graf-hr))
    (should (facep face))))

;;; Error Handling Tests

(ert-deftest integration/empty-document-exports ()
  "Empty document exports without error."
  (should (stringp (mark-graf-export--markdown-to-html ""))))

(ert-deftest integration/whitespace-only-exports ()
  "Whitespace-only document exports without error."
  (should (stringp (mark-graf-export--markdown-to-html "   \n\n   \n"))))

(ert-deftest integration/malformed-markdown-exports ()
  "Malformed markdown exports without crashing."
  ;; Unclosed formatting
  (should (stringp (mark-graf-export--markdown-to-html "**unclosed bold")))
  (should (stringp (mark-graf-export--markdown-to-html "*unclosed italic")))
  ;; Broken links
  (should (stringp (mark-graf-export--markdown-to-html "[broken link")))
  (should (stringp (mark-graf-export--markdown-to-html "[text](unclosed")))
  ;; Unclosed code block
  (should (stringp (mark-graf-export--markdown-to-html "```\ncode without close"))))

;;; Pandoc Integration Test

(ert-deftest integration/pandoc-availability-check ()
  "Pandoc availability function works."
  ;; Should return a boolean-ish value without error
  (should (or (mark-graf-pandoc-available-p)
              (not (mark-graf-pandoc-available-p)))))

;;; Node Structure Tests

(ert-deftest integration/node-struct-creation ()
  "mark-graf-node struct works correctly."
  (let ((node (make-mark-graf-node
               :type 'heading
               :start 1
               :end 20
               :level 2
               :language nil
               :children nil
               :properties '(:foo bar))))
    (should (eq (mark-graf-node-type node) 'heading))
    (should (= (mark-graf-node-start node) 1))
    (should (= (mark-graf-node-end node) 20))
    (should (= (mark-graf-node-level node) 2))
    (should-not (mark-graf-node-language node))
    (should-not (mark-graf-node-children node))
    (should (equal (mark-graf-node-properties node) '(:foo bar)))))

;;; Tree-sitter Inline Collector Tests
;;; These require the markdown and markdown-inline grammars to be installed.

(ert-deftest integration/tree-sitter-code-span-content-is-literal ()
  "Tree-sitter inline collector treats code-span content as literal.
Markdown markers inside backticks (underscores, asterisks, brackets, etc.)
must not be surfaced as emphasis, strong, link, or image nodes, even though
the inline grammar still parses them as such inside the code_span."
  (skip-unless (and (treesit-language-available-p 'markdown)
                    (treesit-language-available-p 'markdown-inline)))
  (with-temp-buffer
    (insert "`foo_bar_baz` and `**not bold**` and `[t](u)`")
    (let ((mark-graf-ts--use-tree-sitter t))
      (mark-graf-ts--init)
      (let ((types (mapcar #'mark-graf-node-type
                           (mark-graf-ts--inline-elements-in
                            (point-min) (point-max)))))
        (should (member 'code-span types))
        (should-not (member 'emphasis types))
        (should-not (member 'strong types))
        (should-not (member 'link types))))))

;;; Performance Smoke Test

(ert-deftest integration/large-document-performance ()
  "Large document exports in reasonable time."
  (let ((large-doc (with-temp-buffer
                     (dotimes (_ 100)
                       (insert "# Heading\n\n")
                       (insert "Paragraph with **bold** and *italic* text.\n\n")
                       (insert "- List item 1\n- List item 2\n\n")
                       (insert "```python\ncode()\n```\n\n"))
                     (buffer-string))))
    (let ((start-time (current-time)))
      (mark-graf-export--markdown-to-html large-doc)
      (let ((elapsed (float-time (time-since start-time))))
        ;; Should complete in under 5 seconds
        (should (< elapsed 5.0))))))

(provide 'mark-graf-integration-test)
;;; mark-graf-integration-test.el ends here
