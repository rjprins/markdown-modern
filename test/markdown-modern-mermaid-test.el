;;; markdown-modern-mermaid-test.el --- Mermaid regression tests -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:

;; Check sequence diagram identities, SVG geometry and message semantics.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'dom)
(require 'xml)
(require 'markdown-modern-mermaid)

(defconst markdown-modern-mermaid-test--campaign
  "sequenceDiagram
  autonumber
  participant A as Mobile app
  participant B as BFF
  participant P as CMS
  A->>B: GET /mob/content
  B->>P: query mob
  P-->>B: labels + campain
  alt campaign exists and start <= today ,= end
    B-->>A: 200 content, campaign block
  else no campaign exists
    B-->>A: 200 content, no campaign block
  end
  Note over B,A: CMS unavailable: behaviour as today"
  "Sequence diagram that previously produced six participants and a clipped note.")

(defun markdown-modern-mermaid-test--svg (code)
  "Render CODE and parse the resulting SVG as XML."
  (let ((svg (markdown-modern-mermaid-render code)))
    (should (stringp svg))
    (with-temp-buffer
      (insert svg)
      (car (xml-parse-region (point-min) (point-max))))))

(defun markdown-modern-mermaid-test--number (node attr)
  "Read numeric ATTR from SVG NODE."
  (string-to-number (dom-attr node attr)))

(defun markdown-modern-mermaid-test--text (svg text)
  "Find the text element in SVG with exact content TEXT."
  (cl-find text (dom-by-tag svg 'text) :key #'dom-text :test #'equal))

(defun markdown-modern-mermaid-test--messages (svg)
  "Return horizontal message lines from SVG."
  (cl-remove-if-not
   (lambda (line) (and (equal (dom-attr line 'y1) (dom-attr line 'y2))
                       (equal (dom-attr line 'stroke-width) "1.5")
                       (not (equal (dom-attr line 'stroke-dasharray) "4,4"))))
   (dom-by-tag svg 'line)))

(ert-deftest mermaid/sequence-aliases-and-message-endpoints ()
  "Aliases label three lifelines, and every arrow connects the intended pair."
  (let* ((svg (markdown-modern-mermaid-test--svg markdown-modern-mermaid-test--campaign))
         (texts (mapcar #'dom-text (dom-by-tag svg 'text)))
         (lines (cl-remove-if-not (lambda (line) (dom-attr line 'marker-end))
                                  (dom-by-tag svg 'line)))
         (a (dom-attr (markdown-modern-mermaid-test--text svg "Mobile app") 'x))
         (b (dom-attr (markdown-modern-mermaid-test--text svg "BFF") 'x))
         (p (dom-attr (markdown-modern-mermaid-test--text svg "CMS") 'x)))
    (dolist (id '("A" "B" "P")) (should-not (member id texts)))
    (dolist (label '("Mobile app" "BFF" "CMS"))
      (should (= 2 (cl-count label texts :test #'equal))))
    (should (= 3 (cl-count "4,4" (dom-by-tag svg 'line)
                           :key (lambda (line) (dom-attr line 'stroke-dasharray))
                           :test #'equal)))
    (should (equal (mapcar (lambda (line) (list (dom-attr line 'x1) (dom-attr line 'x2))) lines)
                   (list (list a b) (list b p) (list p b) (list b a) (list b a))))
    (should (equal (mapcar (lambda (line) (dom-attr line 'stroke-dasharray)) lines)
                   '(nil nil "5,5" "5,5" "5,5")))
    (should (markdown-modern-mermaid-test--text svg "1. GET /mob/content"))
    (should (markdown-modern-mermaid-test--text svg "5. 200 content, no campaign block"))))

(ert-deftest mermaid/sequence-branches-and-spanning-note ()
  "Conditions, branches and the reversed two-participant note stay in bounds."
  (let* ((svg (markdown-modern-mermaid-test--svg markdown-modern-mermaid-test--campaign))
         (condition (markdown-modern-mermaid-test--text svg "[campaign exists and start <= today ,= end]"))
         (branch (markdown-modern-mermaid-test--text svg "[no campaign exists]"))
         (first (markdown-modern-mermaid-test--text svg "4. 200 content, campaign block"))
         (second (markdown-modern-mermaid-test--text svg "5. 200 content, no campaign block"))
         (note (markdown-modern-mermaid-test--text svg "CMS unavailable: behaviour as today"))
         (a (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "Mobile app") 'x))
         (b (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "BFF") 'x))
         (frame (cl-find "1" (dom-by-tag svg 'rect)
                         :key (lambda (rect) (dom-attr rect 'stroke-width)) :test #'equal)))
    (should condition)
    (should frame)
    (should (< (markdown-modern-mermaid-test--number condition 'y)
               (markdown-modern-mermaid-test--number first 'y)
               (markdown-modern-mermaid-test--number branch 'y)
               (markdown-modern-mermaid-test--number second 'y)))
    (should (< (markdown-modern-mermaid-test--number second 'y)
               (+ (markdown-modern-mermaid-test--number frame 'y)
                  (markdown-modern-mermaid-test--number frame 'height))
               (markdown-modern-mermaid-test--number note 'y)))
    (should (= (/ (+ a b) 2) (markdown-modern-mermaid-test--number note 'x)))
    (dolist (rect (dom-by-tag svg 'rect))
      (should (>= (markdown-modern-mermaid-test--number rect 'x) 0))
      (should (<= (+ (markdown-modern-mermaid-test--number rect 'x)
                     (markdown-modern-mermaid-test--number rect 'width))
                  (markdown-modern-mermaid-test--number svg 'width))))))

(ert-deftest mermaid/sequence-distinct-ids-may-share-a-label ()
  "Display labels never collapse distinct IDs, even after implicit declarations."
  (let* ((parsed (markdown-modern-mermaid--parse-sequence
                  '("sequenceDiagram" "A->>B: request"
                    "participant A as Service" "actor B as Service"
                    "participant A" "B-->>A: reply")))
         (labels (plist-get parsed :labels)))
    (should (equal (plist-get parsed :participants) '("A" "B")))
    (should (equal (gethash "A" labels) "Service"))
    (should (equal (gethash "B" labels) "Service"))))

(ert-deftest mermaid/sequence-note-placement-and-numbering ()
  "Notes create lifelines, honor their placement and do not consume numbers."
  (let* ((svg (markdown-modern-mermaid-test--svg
               "sequenceDiagram
autonumber
Note left of A: before
A->>B: request
Note right of B: aside
Note over A: centered
B-->>A: reply"))
         (a (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "A") 'x))
         (b (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "B") 'x)))
    (should (< (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "before") 'x) a))
    (should (> (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "aside") 'x) b))
    (should (= (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "centered") 'x) a))
    (should (markdown-modern-mermaid-test--text svg "1. request"))
    (should (markdown-modern-mermaid-test--text svg "2. reply"))))

(ert-deftest mermaid/sequence-arrow-styles-and-self-messages ()
  "Arrowheads and dashes follow the arrow syntax, including self-messages."
  (let* ((svg (markdown-modern-mermaid-test--svg
               "sequenceDiagram
client-app->>server: solid
server-->>client-app: dashed
client-app->server: plain
server-->client-app: dotted
client-app-)server: async
server--)client-app: dashed async
server-->>server: retry
server->server: local"))
         (lines (markdown-modern-mermaid-test--messages svg))
         (paths (cl-remove-if-not (lambda (node) (and (listp node) (eq (dom-tag node) 'path)))
                                  (dom-children svg))))
    (should (= 6 (length lines)))
    (should (equal (mapcar (lambda (line) (dom-attr line 'marker-end)) lines)
                   '("url(#seq-arrow)" "url(#seq-arrow)" nil nil "url(#seq-open)" "url(#seq-open)")))
    (should (equal (mapcar (lambda (line) (dom-attr line 'stroke-dasharray)) lines)
                   '(nil "5,5" nil "5,5" nil "5,5")))
    (should (= 2 (length paths)))
    (should (equal (dom-attr (car paths) 'marker-end) "url(#seq-arrow)"))
    (should (equal (dom-attr (car paths) 'stroke-dasharray) "5,5"))
    (should-not (dom-attr (cadr paths) 'marker-end))))

(ert-deftest mermaid/sequence-empty-and-nested-branches ()
  "Empty and nested branches get separate space instead of sharing an index."
  (let* ((svg (markdown-modern-mermaid-test--svg
               "sequenceDiagram
participant A
alt outer
else empty branch
loop inner
A->>A: work
end
else final branch
end
A->>A: after"))
         (texts '("[outer]" "[empty branch]" "[inner]" "work" "[final branch]" "after"))
         (ys (mapcar (lambda (text) (markdown-modern-mermaid-test--number
                                     (markdown-modern-mermaid-test--text svg text) 'y)) texts)))
    (should (apply #'< ys))
    (should (= 2 (cl-count "1" (dom-by-tag svg 'rect)
                           :key (lambda (rect) (dom-attr rect 'stroke-width)) :test #'equal)))))

(ert-deftest mermaid/sequence-multiline-and-comment ()
  "Line breaks reserve height and commented arrows do not create participants."
  (let* ((svg (markdown-modern-mermaid-test--svg
               "sequenceDiagram
participant A as Mobile<br/>app
%% Ghost->>Other: ignored
A->>B: first<br>second
Note over B, A: safe < & >\nB-->>A: last"))
         (texts (mapcar #'dom-text (dom-by-tag svg 'text))))
    (should (member "Mobile" texts))
    (should (member "app" texts))
    (should (member "safe < & >" texts))
    (should-not (member "Ghost" texts))
    (should (< (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "first") 'y)
               (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "second") 'y)
               (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "safe < & >") 'y)))))

(ert-deftest mermaid/sequence-empty-and-participant-only ()
  "Empty diagrams fall back to source; a lone participant still renders."
  (should-not (markdown-modern-mermaid-render "sequenceDiagram\nautonumber"))
  (should (markdown-modern-mermaid-test--text
           (markdown-modern-mermaid-test--svg "sequenceDiagram\nparticipant A as App") "App")))

(provide 'markdown-modern-mermaid-test)
;;; markdown-modern-mermaid-test.el ends here
