;;; markdown-modern-export-test.el --- Export tests for markdown-modern -*- lexical-binding: t; no-byte-compile: t; -*-

;; Copyright (C) 2026 markdown-modern contributors

;;; Commentary:

;; Unit tests for markdown-modern HTML export functionality.
;; These tests verify pure transformation functions with no side effects.

;;; Code:

(require 'ert)
(require 'markdown-modern-export)

;;; Helper Functions

(defun mg-export (markdown)
  "Convert MARKDOWN to HTML for testing."
  (markdown-modern-export--markdown-to-html markdown))

(defun mg-html-contains (markdown &rest patterns)
  "Test that MARKDOWN export contains all PATTERNS."
  (let ((html (mg-export markdown)))
    (dolist (pat patterns)
      (should (string-match-p (regexp-quote pat) html)))))

(defun mg-html-matches (markdown regex)
  "Test that MARKDOWN export matches REGEX."
  (should (string-match-p regex (mg-export markdown))))

;;; Heading Tests

(ert-deftest export/heading-h1 ()
  "H1 heading converts correctly."
  (mg-html-contains "# Title" "<h1" ">Title</h1>"))

(ert-deftest export/heading-h2 ()
  "H2 heading converts correctly."
  (mg-html-contains "## Subtitle" "<h2" ">Subtitle</h2>"))

(ert-deftest export/heading-h3 ()
  "H3 heading converts correctly."
  (mg-html-contains "### Section" "<h3" ">Section</h3>"))

(ert-deftest export/heading-h4 ()
  "H4 heading converts correctly."
  (mg-html-contains "#### Subsection" "<h4" ">Subsection</h4>"))

(ert-deftest export/heading-h5 ()
  "H5 heading converts correctly."
  (mg-html-contains "##### Minor" "<h5" ">Minor</h5>"))

(ert-deftest export/heading-h6 ()
  "H6 heading converts correctly."
  (mg-html-contains "###### Smallest" "<h6" ">Smallest</h6>"))

(ert-deftest export/heading-id-generation ()
  "Headings get appropriate IDs."
  (mg-html-matches "# Hello World" "id=\"hello-world\""))

(ert-deftest export/heading-id-special-chars ()
  "Heading IDs handle special characters."
  (let ((id (markdown-modern-export--heading-id "Test: Special (Chars)!")))
    (should (string-match-p "^[a-z0-9-]+$" id))
    (should-not (string-match-p "[^a-z0-9-]" id))))

;;; Inline Formatting Tests

(ert-deftest export/bold-asterisks ()
  "Bold with ** converts correctly."
  (mg-html-contains "**bold**" "<strong>bold</strong>"))

(ert-deftest export/bold-underscores ()
  "Bold with __ converts correctly."
  (mg-html-contains "__bold__" "<strong>bold</strong>"))

(ert-deftest export/italic-asterisk ()
  "Italic with * converts correctly."
  (mg-html-contains "*italic*" "<em>italic</em>"))

(ert-deftest export/italic-underscore ()
  "Italic with _ converts correctly."
  (mg-html-contains "_italic_" "<em>italic</em>"))

(ert-deftest export/strikethrough ()
  "Strikethrough converts correctly."
  (mg-html-contains "~~struck~~" "<del>struck</del>"))

(ert-deftest export/inline-code ()
  "Inline code converts correctly."
  (mg-html-contains "`code`" "<code>code</code>"))

(ert-deftest export/inline-code-escapes-html ()
  "Inline code escapes HTML entities."
  (mg-html-contains "`<div>`" "&lt;div&gt;"))

(ert-deftest export/mixed-inline ()
  "Mixed inline formatting in paragraph."
  (let ((html (mg-export "Text with **bold** and *italic* and `code`.")))
    (should (string-match-p "<strong>bold</strong>" html))
    (should (string-match-p "<em>italic</em>" html))
    (should (string-match-p "<code>code</code>" html))))

;;; Link Tests

(ert-deftest export/inline-link ()
  "Inline link converts correctly."
  (mg-html-contains "[text](http://example.com)"
                    "<a href=\"http://example.com\">text</a>"))

(ert-deftest export/link-with-title ()
  "Link text preserved correctly."
  (mg-html-matches "[Click here](http://x)" ">Click here</a>"))

(ert-deftest export/multiple-links ()
  "Multiple links in same paragraph."
  (let ((html (mg-export "[a](http://a) and [b](http://b)")))
    (should (string-match-p "href=\"http://a\"" html))
    (should (string-match-p "href=\"http://b\"" html))))

;;; Image Tests

(ert-deftest export/image-basic ()
  "Basic image converts correctly."
  (mg-html-contains "![alt](image.png)"
                    "<img src=\"image.png\" alt=\"alt\">"))

(ert-deftest export/image-empty-alt ()
  "Image with empty alt text."
  (mg-html-contains "![](image.png)"
                    "<img src=\"image.png\" alt=\"\">"))

(ert-deftest export/image-url ()
  "Image with URL source."
  (mg-html-contains "![logo](https://example.com/logo.png)"
                    "src=\"https://example.com/logo.png\""))

;;; Code Block Tests

(ert-deftest export/fenced-code-no-language ()
  "Fenced code block without language."
  (let ((html (mg-export "```\ncode here\n```")))
    (should (string-match-p "<pre><code>" html))
    (should (string-match-p "code here" html))))

(ert-deftest export/fenced-code-with-language ()
  "Fenced code block with language."
  (mg-html-contains "```python\nprint('hi')\n```"
                    "<code class=\"language-python\">"))

(ert-deftest export/fenced-code-escapes-html ()
  "Code block escapes HTML."
  (mg-html-contains "```\n<script>alert('xss')</script>\n```"
                    "&lt;script&gt;"))

(ert-deftest export/fenced-code-preserves-content ()
  "Code block preserves content."
  (let ((html (mg-export "```js\nfunction() {\n  return 42;\n}\n```")))
    (should (string-match-p "function" html))
    (should (string-match-p "return 42" html))))

;;; List Tests

(ert-deftest export/unordered-list-dash ()
  "Unordered list with - markers."
  (let ((html (mg-export "- Item 1\n- Item 2\n- Item 3")))
    (should (string-match-p "<ul>" html))
    (should (string-match-p "<li>Item 1</li>" html))
    (should (string-match-p "<li>Item 2</li>" html))
    (should (string-match-p "</ul>" html))))

(ert-deftest export/unordered-list-asterisk ()
  "Unordered list with * markers."
  (mg-html-contains "* Item 1\n* Item 2" "<ul>" "<li>Item 1</li>"))

(ert-deftest export/ordered-list ()
  "Ordered list converts correctly."
  (let ((html (mg-export "1. First\n2. Second\n3. Third")))
    (should (string-match-p "<ol>" html))
    (should (string-match-p "<li>First</li>" html))
    (should (string-match-p "</ol>" html))))

(ert-deftest export/task-list-unchecked ()
  "Task list with unchecked items."
  (mg-html-contains "- [ ] Todo"
                    "task-list-item"
                    "type=\"checkbox\""))

(ert-deftest export/task-list-checked ()
  "Task list with checked items."
  (mg-html-contains "- [x] Done"
                    "checked"
                    "type=\"checkbox\""))

;;; Table Tests

(ert-deftest export/table-basic ()
  "Basic table structure."
  (let ((html (mg-export "| A | B |\n|---|---|\n| 1 | 2 |")))
    (should (string-match-p "<table>" html))
    (should (string-match-p "<th>A</th>" html))
    (should (string-match-p "<td>1</td>" html))
    (should (string-match-p "</table>" html))))

(ert-deftest export/table-header ()
  "Table header row marked correctly."
  (mg-html-contains "| H1 | H2 |\n|---|---|\n| D1 | D2 |"
                    "<thead>" "<th>H1</th>" "</thead>"))

(ert-deftest export/table-body ()
  "Table body rows marked correctly."
  (mg-html-contains "| H |\n|---|\n| D |"
                    "<tbody>" "<td>D</td>" "</tbody>"))

;;; Blockquote Tests

(ert-deftest export/blockquote-single-line ()
  "Single line blockquote."
  (mg-html-contains "> Quote" "<blockquote>" "Quote" "</blockquote>"))

(ert-deftest export/blockquote-multi-line ()
  "Multi-line blockquote."
  (let ((html (mg-export "> Line 1\n> Line 2")))
    (should (string-match-p "<blockquote>" html))
    (should (string-match-p "Line 1" html))
    (should (string-match-p "Line 2" html))))

;;; Horizontal Rule Tests

(ert-deftest export/hr-dashes ()
  "HR with dashes."
  (mg-html-contains "---" "<hr>"))

(ert-deftest export/hr-asterisks ()
  "HR with asterisks."
  (mg-html-contains "***" "<hr>"))

(ert-deftest export/hr-underscores ()
  "HR with underscores."
  (mg-html-contains "___" "<hr>"))

;;; Paragraph Tests

(ert-deftest export/paragraph-basic ()
  "Basic paragraph wrapping."
  (mg-html-matches "Plain text" "<p>Plain text</p>"))

(ert-deftest export/paragraph-multiple ()
  "Multiple paragraphs separated by blank lines."
  (let ((html (mg-export "Para 1\n\nPara 2")))
    (should (string-match-p "<p>Para 1</p>" html))
    (should (string-match-p "<p>Para 2</p>" html))))

;;; HTML Escaping Tests

(ert-deftest export/escape-ampersand ()
  "Ampersand escaped correctly."
  (should (equal (markdown-modern-export--escape-html "A & B") "A &amp; B")))

(ert-deftest export/escape-less-than ()
  "Less-than escaped correctly."
  (should (equal (markdown-modern-export--escape-html "a < b") "a &lt; b")))

(ert-deftest export/escape-greater-than ()
  "Greater-than escaped correctly."
  (should (equal (markdown-modern-export--escape-html "a > b") "a &gt; b")))

(ert-deftest export/escape-quotes ()
  "Quotes escaped correctly."
  (should (equal (markdown-modern-export--escape-html "say \"hi\"") "say &quot;hi&quot;")))

(ert-deftest export/escape-combined ()
  "Multiple special chars escaped."
  (should (equal (markdown-modern-export--escape-html "<a & b>")
                 "&lt;a &amp; b&gt;")))

;;; Block Structure Tests

(defconst mg-export-test-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory of this test file.")

(defun mg-balanced-p (html)
  "Return non-nil when the tags in HTML that the exporter writes nest properly."
  (let ((case-fold-search nil)
        (stack '())
        (pos 0)
        (ok t))
    (while (and ok (string-match
                    "<\\(/?\\)\\(p\\|blockquote\\|ul\\|ol\\|li\\|pre\\|code\\|table\\|thead\\|tbody\\|tr\\|th\\|td\\|h[1-6]\\|em\\|strong\\|del\\|a\\)[ >]"
                    html pos))
      (setq pos (match-end 0))
      (let ((tag (match-string 2 html)))
        (if (string-empty-p (match-string 1 html))
            (push tag stack)
          (if (equal (car stack) tag)
              (pop stack)
            (setq ok nil)))))
    (and ok (null stack))))

(ert-deftest export/fenced-code-in-list-item ()
  "A fenced code block inside a list item does not break the rest."
  (let ((html (mg-export "- An item:\n\n  ```sh\n  echo \"hi\"\n  ```\n\n## After\n\nText.")))
    (should (string-match-p
             (regexp-quote "<pre><code class=\"language-sh\">echo &quot;hi&quot;</code></pre>")
             html))
    (should (string-match-p (regexp-quote "<h2 id=\"after\">After</h2>") html))
    (should (string-match-p (regexp-quote "<p>Text.</p>") html))
    (should-not (string-match-p "&lt;" html))
    (should (mg-balanced-p html))))

(ert-deftest export/tilde-fence ()
  "A ~~~ fence is a code block, not strikethrough."
  (let ((html (mg-export "~~~javascript\nconst a = 1;\n~~~")))
    (should (equal html "<pre><code class=\"language-javascript\">const a = 1;</code></pre>"))))

(ert-deftest export/fence-longer-closing ()
  "A fence closes only on a fence of the same kind, at least as long."
  (let ((html (mg-export "````md\n```\ninner\n```\n````")))
    (should (equal html "<pre><code class=\"language-md\">```\ninner\n```</code></pre>"))))

(ert-deftest export/indented-code ()
  "Four-space indented lines are a code block."
  (let ((html (mg-export "Text.\n\n    line one\n      line two\n\nAfter.")))
    (should (string-match-p
             (regexp-quote "<pre><code>line one\n  line two</code></pre>")
             html))
    (should-not (string-match-p "<p>line" html))))

(ert-deftest export/fenced-code-keeps-indented-lines ()
  "Indented lines inside a fence stay in the code block."
  (let ((html (mg-export "```elisp\n(defun f ()\n  \"Doc.\"\n  1)\n```")))
    (should (equal html "<pre><code class=\"language-elisp\">(defun f ()\n  &quot;Doc.&quot;\n  1)</code></pre>"))))

(ert-deftest export/fenced-code-keeps-markup ()
  "Markdown inside a fence is not converted."
  (let ((html (mg-export "```\n# not a heading\n- not a list\n> not a quote\n**not bold**\n```")))
    (should (equal html "<pre><code># not a heading\n- not a list\n&gt; not a quote\n**not bold**</code></pre>"))))

(ert-deftest export/blockquote-paragraph ()
  "A blockquote holds a paragraph, closed inside it."
  (should (equal (mg-export "> Line 1\n> Line 2")
                 "<blockquote>\n<p>Line 1\nLine 2</p>\n</blockquote>")))

(ert-deftest export/blockquote-nested ()
  "A >> line nests a quote."
  (should (equal (mg-export "> Outer\n>> Nested")
                 "<blockquote>\n<p>Outer</p>\n<blockquote>\n<p>Nested</p>\n</blockquote>\n</blockquote>")))

(ert-deftest export/blockquote-with-list ()
  "A quote can hold a list and more paragraphs."
  (let ((html (mg-export "> A list:\n> - first\n> - second\n>\n> And **bold**.")))
    (should (equal html
                   "<blockquote>\n<p>A list:</p>\n<ul>\n<li>first</li>\n<li>second</li>\n</ul>\n<p>And <strong>bold</strong>.</p>\n</blockquote>"))))

(ert-deftest export/nested-list ()
  "An indented list nests inside the item above it."
  (should (equal (mg-export "- one\n  - two\n- three")
                 "<ul>\n<li>one\n<ul>\n<li>two</li>\n</ul></li>\n<li>three</li>\n</ul>")))

(ert-deftest export/list-item-continuation ()
  "Indented lines continue a list item."
  (should (equal (mg-export "- a long\n  item\n- b")
                 "<ul>\n<li>a long\nitem</li>\n<li>b</li>\n</ul>")))

(ert-deftest export/ordered-list-start ()
  "An ordered list keeps its start number."
  (mg-html-contains "3. three\n4. four" "<ol start=\"3\">"))

(ert-deftest export/loose-list ()
  "Items separated by blank lines get paragraphs."
  (should (equal (mg-export "- a\n\n- b")
                 "<ul>\n<li><p>a</p></li>\n<li><p>b</p></li>\n</ul>")))

(ert-deftest export/list-then-rule ()
  "A rule right after a list ends the list."
  (should (equal (mg-export "Text\n- a\n- b\n---")
                 "<p>Text</p>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n<hr>")))

(ert-deftest export/table-alignment ()
  "Table columns keep their alignment, and cells get inline markup."
  (let ((html (mg-export "| L | C | R |\n|:--|:-:|--:|\n| **a** | `b` | c |")))
    (should (string-match-p (regexp-quote "<th style=\"text-align: center\">C</th>") html))
    (should (string-match-p (regexp-quote "<td style=\"text-align: left\"><strong>a</strong></td>") html))
    (should (string-match-p (regexp-quote "<td style=\"text-align: right\">c</td>") html))))

;;; Inline Escape and Break Tests

(ert-deftest export/backslash-escapes ()
  "Backslash escapes give the literal character."
  (let ((html (mg-export "\\*not italic\\*, \\`not code\\`, \\_x\\_")))
    (should (equal html "<p>*not italic*, `not code`, _x_</p>"))))

(ert-deftest export/escaped-heading-marker ()
  "An escaped # does not start a heading."
  (should (equal (mg-export "\\# not a heading") "<p># not a heading</p>")))

(ert-deftest export/hard-break-spaces ()
  "Two trailing spaces make a hard line break."
  (should (equal (mg-export "one  \ntwo") "<p>one<br>\ntwo</p>")))

(ert-deftest export/hard-break-backslash ()
  "A trailing backslash makes a hard line break."
  (should (equal (mg-export "one\\\ntwo") "<p>one<br>\ntwo</p>")))

(ert-deftest export/text-is-escaped ()
  "Plain < and & are escaped, entities are kept."
  (should (equal (mg-export "a < b & c &amp; d") "<p>a &lt; b &amp; c &amp; d</p>")))

(ert-deftest export/intraword-underscore ()
  "Underscores inside words are not emphasis."
  (should (equal (mg-export "snake_case_name") "<p>snake_case_name</p>")))

(ert-deftest export/emphasis-pairs-each-span ()
  "Two emphasis spans in one paragraph stay two spans."
  (dolist (case '(("*a* and *b*" . "<em>a</em> and <em>b</em>")
                  ("_a_ and _b_" . "<em>a</em> and <em>b</em>")
                  ("**a** and **b**" . "<strong>a</strong> and <strong>b</strong>")
                  ("__a__ and __b__" . "<strong>a</strong> and <strong>b</strong>")
                  ("~~a~~ and ~~b~~" . "<del>a</del> and <del>b</del>")
                  ("_a_ _b_" . "<em>a</em> <em>b</em>")))
    (should (equal (mg-export (car case)) (concat "<p>" (cdr case) "</p>")))))

(ert-deftest export/emphasis-nesting ()
  "Emphasis nests, and spans that overlap still give nested HTML."
  (dolist (case '(("***a***" . "<strong><em>a</em></strong>")
                  ("**a *b* c**" . "<strong>a <em>b</em> c</strong>")
                  ("*a **b** c*" . "<em>a <strong>b</strong> c</em>")
                  ("_a_b c_" . "<em>a_b c</em>")
                  ("__init__" . "<strong>init</strong>")
                  ("2*3*4" . "2<em>3</em>4")
                  ("a * b * c" . "a * b * c")))
    (should (equal (mg-export (car case)) (concat "<p>" (cdr case) "</p>"))))
  (dolist (text '("**a *b** c*" "*a **b* c**" "*a *b* c*"))
    (should (mg-balanced-p (mg-export text)))))

(ert-deftest export/link-destination-is-literal ()
  "Math, emphasis and escapes are not applied inside a link destination."
  (should (equal (mg-export "[a](http://x/$foo$bar)")
                 "<p><a href=\"http://x/$foo$bar\">a</a></p>"))
  (should (equal (mg-export "[a](http://x/*b*_c_ \"t $x$ *y*\")")
                 "<p><a href=\"http://x/*b*_c_\" title=\"t $x$ *y*\">a</a></p>"))
  (should (equal (mg-export "[a](http://x/?a=1&b=2&amp;c=\\_)")
                 "<p><a href=\"http://x/?a=1&amp;b=2&amp;c=_\">a</a></p>")))

(ert-deftest export/emphasis-stays-out-of-links ()
  "Emphasis does not pair across a link, but works inside its text."
  (should (equal (mg-export "[*a](u) b*") "<p><a href=\"u\">*a</a> b*</p>"))
  (should (equal (mg-export "*b [a*](u)") "<p>*b <a href=\"u\">a*</a></p>"))
  (should (equal (mg-export "*[a](u)* and [*b* $x$](v)")
                 "<p><em><a href=\"u\">a</a></em> and <a href=\"v\"><em>b</em> <span class=\"math inline\">$x$</span></a></p>"))
  (should (equal (mg-export "[![i](p.png) *t*](u)")
                 "<p><a href=\"u\"><img src=\"p.png\" alt=\"i\"> <em>t</em></a></p>")))

(ert-deftest export/link-title ()
  "A link title becomes a title attribute."
  (mg-html-contains "[GitHub](https://github.com \"GitHub home\")"
                    "<a href=\"https://github.com\" title=\"GitHub home\">GitHub</a>"))

(ert-deftest export/reference-link ()
  "Reference links use their definition, which is not shown."
  (let ((html (mg-export "See [the log][log] and [log].\n\n[log]: ../CHANGELOG.md")))
    (should (equal html "<p>See <a href=\"../CHANGELOG.md\">the log</a> and <a href=\"../CHANGELOG.md\">log</a>.</p>"))))

(ert-deftest export/autolink ()
  "An autolink becomes a link."
  (mg-html-contains "<https://example.com/a_b>"
                    "<a href=\"https://example.com/a_b\">https://example.com/a_b</a>"))

;;; Math Tests

(ert-deftest export/display-math-untouched ()
  "Display math keeps its source, with no emphasis inside."
  (let ((html (mg-export "$$\n\\int_{-\\infty}^{\\infty} e^{-x_1^2} dx\n$$")))
    (should-not (string-match-p "<em>" html))
    (should (string-match-p (regexp-quote "\\int_{-\\infty}^{\\infty} e^{-x_1^2} dx") html))))

(ert-deftest export/inline-math-untouched ()
  "Inline math keeps its source, with no emphasis inside."
  (let ((html (mg-export "Sum $a_1 + b_1$ and $x*y*z$.")))
    (should-not (string-match-p "<em>" html))
    (should (string-match-p (regexp-quote "$a_1 + b_1$") html))
    (should (string-match-p (regexp-quote "$x*y*z$") html))))

(ert-deftest export/dollar-amounts-not-math ()
  "Prices are not math, and emphasis next to them still works."
  (should (equal (mg-export "From $5 to $10, *cheap*.")
                 "<p>From $5 to $10, <em>cheap</em>.</p>")))

;;; Raw HTML and Mermaid Tests

(ert-deftest export/html-block-passes-through ()
  "An HTML block is kept as is, with Markdown between its tags."
  (let ((html (mg-export "<details>\n<summary>More</summary>\n\nHidden **text**.\n\n</details>")))
    (should (equal html "<details>\n<summary>More</summary>\n<p>Hidden <strong>text</strong>.</p>\n</details>"))))

(ert-deftest export/inline-html-passes-through ()
  "Inline tags such as <kbd> are kept."
  (should (equal (mg-export "Press <kbd>Ctrl</kbd> + <kbd>C</kbd>.")
                 "<p>Press <kbd>Ctrl</kbd> + <kbd>C</kbd>.</p>")))

(ert-deftest export/mermaid-as-code ()
  "Mermaid blocks export as code."
  (should (equal (mg-export "```mermaid\nflowchart TD\nA --> B\n```")
                 "<pre><code class=\"language-mermaid\">flowchart TD\nA --&gt; B</code></pre>")))

(ert-deftest export/manual-file ()
  "The manual test file exports to well-nested HTML."
  (let ((html (with-temp-buffer
                (insert-file-contents (expand-file-name "manual.md" mg-export-test-dir))
                (mg-export (buffer-string)))))
    (should (mg-balanced-p html))
    (should-not (string-match-p "&lt;h[1-6]\\|&lt;/\\?p&gt;" html))
    (should-not (string-match-p "<p>\\(<pre\\|<ul\\|<blockquote\\|>\\)" html))
    (should (string-match-p "<h2 id=\"export\">Export</h2>" html))))

(provide 'markdown-modern-export-test)
;;; markdown-modern-export-test.el ends here
