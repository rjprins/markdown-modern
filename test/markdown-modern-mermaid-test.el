;;; markdown-modern-mermaid-test.el --- Mermaid regression tests -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:

;; Check all five diagram families, SVG geometry and source fallback behavior.

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

(defconst markdown-modern-mermaid-test--states
  "stateDiagram-v2
  [*] --> REQUESTED
  REQUESTED --> PENDING
  REQUESTED --> ACCEPTED
  PENDING --> ACCEPTED
  REQUESTED --> REJECTED
  PENDING --> REJECTED
  REQUESTED --> EXPIRED
  PENDING --> EXPIRED
  ACCEPTED --> REWARD
  REWARD --> REWARDED
  REWARD --> REFUSED
  REWARD --> ERROR
  ERROR --> REQUESTED: republished
  REWARDED --> [*]
  REFUSED --> [*]
  REJECTED --> [*]
  EXPIRED --> [*]"
  "Branching state diagram with a cycle and a shared final state.")

(defun markdown-modern-mermaid-test--state-layout (code)
  "Parse and lay out state diagram CODE."
  (markdown-modern-mermaid--layout-state
   (markdown-modern-mermaid--parse-state (split-string code "\n" t "[ \t]+"))))

(defun markdown-modern-mermaid-test--inside-box-p (point box)
  "Return non-nil if POINT is strictly inside BOX, allowing edge rounding."
  (and (< (+ (plist-get box :x) 1) (car point)
          (- (+ (plist-get box :x) (plist-get box :w)) 1))
       (< (+ (plist-get box :y) 1) (cdr point)
          (- (+ (plist-get box :y) (plist-get box :h)) 1))))

(defun markdown-modern-mermaid-test--path-points (path)
  "Sample SVG PATH's actual line and cubic curve geometry."
  (let ((tokens (split-string (dom-attr path 'd))) current points)
    (while tokens
      (let* ((command (pop tokens))
             (count (if (equal command "C") 3 1)) coords)
        (dotimes (_ count)
          (push (cons (string-to-number (pop tokens))
                      (string-to-number (pop tokens))) coords))
        (setq coords (nreverse coords))
        (if (equal command "M")
            (setq current (car coords))
          ;; A degenerate segment can give an arrowhead the wrong direction.
          (should-not (equal current (car (last coords))))
          (dotimes (step 21)
            (let* ((fraction (/ step 20.0)) (remaining (- 1 fraction))
                   (weights (if (equal command "C")
                                (list (expt remaining 3) (* 3 remaining remaining fraction)
                                      (* 3 remaining fraction fraction) (expt fraction 3))
                              (list remaining fraction)))
                   (vertices (cons current coords)))
              (push (cons (cl-loop for p in vertices for w in weights sum (* w (car p)))
                          (cl-loop for p in vertices for w in weights sum (* w (cdr p)))) points)))
          (setq current (car (last coords))))))
    points))

(defun markdown-modern-mermaid-test--state-geometry (code)
  "Check CODE's rendered arrows, nodes and labels for clipping and collisions."
  (let* ((layout (markdown-modern-mermaid-test--state-layout code))
         (svg (markdown-modern-mermaid-test--svg code))
         (nodes (plist-get layout :nodes))
         (routes (plist-get layout :routes))
         (paths (cl-remove-if-not (lambda (p) (dom-attr p 'marker-end)) (dom-by-tag svg 'path)))
         (width (markdown-modern-mermaid-test--number svg 'width))
         (height (markdown-modern-mermaid-test--number svg 'height))
         boxes)
    (should (= (length paths) (length routes)))
    (maphash (lambda (_ box) (push box boxes)) nodes)
    (dolist (route routes)
      (when (plist-get route :label-box) (push (plist-get route :label-box) boxes)))
    (dolist (box boxes)
      (should (<= 0 (plist-get box :x)))
      (should (<= 0 (plist-get box :y)))
      (should (<= (+ (plist-get box :x) (plist-get box :w)) width))
      (should (<= (+ (plist-get box :y) (plist-get box :h)) height))
      (dolist (other (remq box boxes))
        (should-not (and (< (plist-get box :x) (+ (plist-get other :x) (plist-get other :w)))
                         (< (plist-get other :x) (+ (plist-get box :x) (plist-get box :w)))
                         (< (plist-get box :y) (+ (plist-get other :y) (plist-get other :h)))
                         (< (plist-get other :y) (+ (plist-get box :y) (plist-get box :h)))))))
    (cl-loop for route in routes for path in paths do
             (dolist (point (markdown-modern-mermaid-test--path-points path))
               (should (<= 0 (car point) width))
               (should (<= 0 (cdr point) height))
               (maphash
                (lambda (id box)
                  ;; Circular endpoints lie within their bounding rectangles.
                  (unless (memq id '(start end))
                    (should-not (markdown-modern-mermaid-test--inside-box-p point box)))) nodes)
               (dolist (other routes)
                 (when (and (not (eq route other)) (plist-get other :label-box))
                   (should-not (markdown-modern-mermaid-test--inside-box-p
                                point (plist-get other :label-box)))))))))

(ert-deftest mermaid/state-example-identities-labels-and-geometry ()
  "The reported diagram has nine named states, one start, one end and 17 arrows."
  (let* ((svg (markdown-modern-mermaid-test--svg markdown-modern-mermaid-test--states))
         (texts (mapcar #'dom-text (dom-by-tag svg 'text)))
         (parsed (markdown-modern-mermaid--parse-state
                  (split-string markdown-modern-mermaid-test--states "\n" t "[ \t]+"))))
    (should (= 11 (hash-table-count (plist-get parsed :states))))
    (should (= 17 (length (plist-get parsed :transitions))))
    (should (= 3 (length (dom-by-tag svg 'circle))))
    (dolist (name '("REQUESTED" "PENDING" "ACCEPTED" "REJECTED" "EXPIRED"
                    "REWARD" "REWARDED" "REFUSED" "ERROR" "republished"))
      (should (= 1 (cl-count name texts :test #'equal))))
    (should-not (member "REQUESTED:" texts))
    (markdown-modern-mermaid-test--state-geometry markdown-modern-mermaid-test--states)))

(ert-deftest mermaid/state-colons-comments-and-aliases ()
  "Colon spacing never changes identity, and later descriptions update aliases."
  (let* ((parsed (markdown-modern-mermaid--parse-state
                  '("stateDiagram-v2" "%% Ghost --> Phantom: ignored"
                    "client-app-->server:request: retry" "server --> client-app : reply"
                    "server-->client-app:compact" "server --> client-app: spaced"
                    "state \"Client\" as client-app" "client-app: Mobile app"
                    "state server" "server: API" "server" "server --> [*] %% done")))
         (states (plist-get parsed :states))
         (edges (plist-get parsed :transitions)))
    (should (= 3 (hash-table-count states)))
    (should (equal (plist-get (gethash "client-app" states) :label) "Mobile app"))
    (should (equal (plist-get (gethash "server" states) :label) "API"))
    (should (equal (mapcar (lambda (edge) (plist-get edge :label)) edges)
                   '("request: retry" "reply" "compact" "spaced" nil)))
    (should (equal (mapcar (lambda (edge) (plist-get edge :to)) edges)
                   '("server" "client-app" "client-app" "client-app" end)))))

(ert-deftest mermaid/state-start-end-and-shared-display-labels ()
  "Pseudostate identity is independent of statement order and real state labels."
  (let* ((code "stateDiagram-v2\nB --> [*]\n[*] --> A\nA --> B\nstate \"Shared\" as A\nstate \"Shared\" as B")
         (svg (markdown-modern-mermaid-test--svg code))
         (layout (markdown-modern-mermaid-test--state-layout code))
         (nodes (plist-get layout :nodes)))
    (should (= 2 (cl-count "Shared" (dom-by-tag svg 'text) :key #'dom-text :test #'equal)))
    (should (< (plist-get (gethash 'start nodes) :y)
               (plist-get (gethash "A" nodes) :y)
               (plist-get (gethash "B" nodes) :y)
               (plist-get (gethash 'end nodes) :y)))
    (markdown-modern-mermaid-test--state-geometry code)))

(ert-deftest mermaid/state-parallel-cyclic-and-self-transitions ()
  "Parallel transitions, returns and self-loops have distinct paths and labels."
  (let* ((code "stateDiagram-v2\n[*] --> A\nA --> B:first\nA --> B:second\nB --> C:next\nC --> A:retry\nB --> A:back\nA --> A:local\nA --> A:again\nC --> [*]")
         (svg (markdown-modern-mermaid-test--svg code))
         (paths (cl-remove-if-not (lambda (p) (dom-attr p 'marker-end)) (dom-by-tag svg 'path))))
    (should (= 9 (length (delete-dups (mapcar (lambda (p) (dom-attr p 'd)) paths)))))
    (dolist (text '("first" "second" "next" "retry" "back" "local" "again"))
      (should (markdown-modern-mermaid-test--text svg text)))
    (markdown-modern-mermaid-test--state-geometry code)))

(ert-deftest mermaid/state-directions-and-multiline-labels ()
  "Directions keep text upright and reserve space for long and multiline labels."
  (dolist (direction '("TB" "BT" "LR" "RL"))
    (let* ((code (concat "stateDiagram-v2\ndirection " direction
                         "\nstate \"First<br/>state\" as A\n[*] --> A\nA --> B: a long transition label<br/>with < & > characters\nB --> A: retry<br/>later\nB --> B: another long transition label<br/>second<br/>third<br/>fourth\nB --> [*]"))
           (svg (markdown-modern-mermaid-test--svg code))
           (axis (if (member direction '("LR" "RL")) 'x 'y))
           (a (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "First") axis))
           (b (markdown-modern-mermaid-test--number (markdown-modern-mermaid-test--text svg "B") axis)))
      (should (markdown-modern-mermaid-test--text svg "with < & > characters"))
      (should (if (member direction '("BT" "RL")) (> a b) (< a b)))
      (markdown-modern-mermaid-test--state-geometry code))))

(ert-deftest mermaid/state-empty-isolated-and-disconnected ()
  "Empty diagrams fall back to source; isolated and disconnected states render."
  (should-not (markdown-modern-mermaid-render "stateDiagram-v2\n%% comment"))
  (should (markdown-modern-mermaid-test--text
           (markdown-modern-mermaid-test--svg "stateDiagram-v2\nLone") "Lone"))
  (markdown-modern-mermaid-test--state-geometry
   "stateDiagram-v2\nA --> B\nC --> D\nD --> C:retry\nE\nstate F"))

(ert-deftest mermaid/state-long-edges-avoid-tall-siblings ()
  "Edges crossing a layer stay outside its states, regardless of box height."
  (markdown-modern-mermaid-test--state-geometry
   "stateDiagram-v2\n[*] --> A\nA --> B\nA --> C\nB --> D\nA --> D:shortcut\nC --> D\nD --> [*]\nstate \"Tall<br/>state<br/>with<br/>several<br/>lines\" as C"))

;;; Audit fixtures are also regression tests, independent of the HTML report.
(require 'json)

(defconst markdown-modern-mermaid-test--audit-cases
  (let ((json-object-type 'alist) (json-array-type 'list))
    (json-read-file (expand-file-name "fixtures/mermaid-audit.json"
                                     (file-name-directory (or load-file-name buffer-file-name))))))

(defun markdown-modern-mermaid-test--audit (case)
  "Check the output contract declared by audit CASE."
  (let* ((code (alist-get 'code case)) (checks (alist-get 'checks case))
         (result (markdown-modern-mermaid-render code)))
    (if (alist-get 'fallback checks)
        (should-not result)
      (let* ((svg (markdown-modern-mermaid-test--svg code))
             (children (cl-remove-if-not #'listp (dom-children svg)))
             (connections (cl-remove-if-not
                           (lambda (node) (and (memq (dom-tag node) '(line path))
                                               (or (dom-attr node 'marker-start)
                                                   (dom-attr node 'marker-end)))) children)))
        (dolist (text (alist-get 'texts checks))
          (should (markdown-modern-mermaid-test--text svg text)))
        (dolist (text (alist-get 'absent checks))
          (should-not (markdown-modern-mermaid-test--text svg text)))
        (dolist (dim '(width height))
          (should (> (markdown-modern-mermaid-test--number svg dim) 0)))
        (when-let* ((expected (alist-get 'edges checks)))
          (should (= expected
                     (if (equal (alist-get 'family case) "Flowchart")
                         (cl-count 'path children :key #'dom-tag)
                       (length connections)))))
        (when-let* ((expected (alist-get 'arrows checks)))
          (should (= expected (length connections))))
        (when (alist-get 'circle checks) (should (dom-by-tag svg 'circle)))
        (when (alist-get 'dashed checks)
          (should (cl-some (lambda (node) (dom-attr node 'stroke-dasharray)) children)))
        (when (alist-get 'thick checks)
          (should (cl-some (lambda (node) (equal (dom-attr node 'stroke-width) "3")) children)))
        (when-let* ((order (alist-get 'order checks)))
          (let* ((direction (car order))
                 (axis (if (member direction '("LR" "RL")) 'x 'y))
                 (values (mapcar (lambda (text) (markdown-modern-mermaid-test--number
                                                (markdown-modern-mermaid-test--text svg text) axis))
                                 (cdr order))))
            (should (apply (if (member direction '("RL" "BT")) #'> #'<) values))))
        (when-let* ((markers (alist-get 'markers checks)))
          (let (actual done)
            (dolist (node children)
              (when (and (eq (dom-tag node) 'rect) (not (equal (dom-attr node 'x) "0")))
                (setq done t))
              (when (and (not done) (eq (dom-tag node) 'line))
                (push (list (dom-attr node 'marker-start) (dom-attr node 'marker-end)
                            (dom-attr node 'stroke-dasharray)) actual)))
            (should (equal markers (nreverse actual)))))
        (when (alist-get 'nondegenerate checks)
          (let ((paths (cl-remove-if-not (lambda (node) (eq (dom-tag node) 'path)) children)))
            (dolist (path paths)
              (let ((points (markdown-modern-mermaid-test--path-points path)))
                (should (> (length (delete-dups (mapcar #'cdr points))) 1))))))))))

(dolist (case markdown-modern-mermaid-test--audit-cases)
  (eval `(ert-deftest ,(intern (concat "mermaid/audit-" (alist-get 'id case))) ()
           ,(alist-get 'description case)
           (markdown-modern-mermaid-test--audit ',case)) t))

(ert-deftest mermaid/er-all-cardinality-pairs ()
  "Every pair of the four endpoint cardinalities preserves both entities."
  (dolist (left '("||" "|o" "}|" "}o"))
    (dolist (right '("||" "o|" "|{" "o{"))
      (dolist (style '("--" ".."))
        (let* ((parsed (markdown-modern-mermaid--parse-er
                        (list "erDiagram" (format "A %s%s%s B : related" left style right))))
               (rels (plist-get parsed :relationships)))
          (should (= 2 (hash-table-count (plist-get parsed :entities))))
          (should (= 1 (length rels)))
          (should (equal (plist-get (car rels) :card-from) left))
          (should (equal (plist-get (car rels) :card-to) right)))))))

(ert-deftest mermaid/flowchart-invalid-input-preserves-source ()
  "Incomplete nodes and unknown syntax must not produce a partial diagram."
  (dolist (code '("flowchart TD\nA[" "flowchart TD\nA -->"
                  "flowchart TD\nA --> B\nnot valid syntax"
                  "classDiagram\nclass A {\n+x" "erDiagram\nA {\nint id"))
    (should-not (markdown-modern-mermaid-render code))))

(ert-deftest mermaid/flowchart-shape-endpoints ()
  "Diamond and circle arrows meet the perimeter rather than their bounding box."
  (dolist (direction '("LR" "RL" "TB" "BT"))
    (let* ((svg (markdown-modern-mermaid-test--svg
                 (concat "flowchart " direction "\nA[Start] --> B{Decision}\nC[Other] --> B\nB --> D((End))")))
           (paths (cl-remove-if-not (lambda (p) (dom-attr p 'marker-end)) (dom-by-tag svg 'path))))
      (should (= 3 (length paths)))
      (dolist (path paths)
        (dolist (point (markdown-modern-mermaid-test--path-points path))
          (should (<= 0 (car point) (markdown-modern-mermaid-test--number svg 'width)))
          (should (<= 0 (cdr point) (markdown-modern-mermaid-test--number svg 'height))))))))

(ert-deftest mermaid/er-crows-foot-nearest-entity ()
  "Many cardinalities put the crow's foot at the entity and minimum farther out."
  (let* ((svg (with-temp-buffer
                (insert (markdown-modern-mermaid--svg-wrap
                         60 40 nil (mapconcat #'identity
                          (markdown-modern-mermaid--er-draw-notation
                           10 20 1 0 "o{" "#000000" "#ffffff") "")))
                (car (xml-parse-region (point-min) (point-max)))))
         (lines (dom-by-tag svg 'line))
         (circle (car (dom-by-tag svg 'circle))))
    (should (cl-find-if (lambda (line)
                         (and (equal (dom-attr line 'x1) "10")
                              (equal (dom-attr line 'y1) "13")
                              (equal (dom-attr line 'x2) "22")
                              (equal (dom-attr line 'y2) "20"))) lines))
    (should (equal (dom-attr circle 'cx) "28"))
    (should (equal (dom-attr circle 'fill) "#ffffff"))))

(provide 'markdown-modern-mermaid-test)
;;; markdown-modern-mermaid-test.el ends here
