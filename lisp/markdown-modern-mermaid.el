;;; markdown-modern-mermaid.el --- Pure Elisp Mermaid SVG renderer -*- lexical-binding: t; -*-

;; Copyright (C) 2026 markdown-modern contributors

;; This file is part of markdown-modern.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Pure Elisp SVG generator for Mermaid diagrams.
;; Generates SVG XML strings displayed inline via Emacs 30's
;; (create-image svg-string 'svg t).  Theme-aware using Emacs face colors.
;; Supports flowchart, sequence, state, class, and ER diagrams.

;;; Code:

(require 'cl-lib)
(require 'color)

;;; ============================================================
;;; Theme Integration
;;; ============================================================

(defun markdown-modern-mermaid--color-blend (c1 c2 alpha)
  "Blend color C1 with C2 by ALPHA (0.0 = all C1, 1.0 = all C2).
C1 and C2 are hex strings like \"#rrggbb\"."
  (let ((r1 (string-to-number (substring c1 1 3) 16))
        (g1 (string-to-number (substring c1 3 5) 16))
        (b1 (string-to-number (substring c1 5 7) 16))
        (r2 (string-to-number (substring c2 1 3) 16))
        (g2 (string-to-number (substring c2 3 5) 16))
        (b2 (string-to-number (substring c2 5 7) 16)))
    (format "#%02x%02x%02x"
            (round (+ (* r1 (- 1 alpha)) (* r2 alpha)))
            (round (+ (* g1 (- 1 alpha)) (* g2 alpha)))
            (round (+ (* b1 (- 1 alpha)) (* b2 alpha))))))

(defun markdown-modern-mermaid--face-color (face attr)
  "Get color ATTR from FACE, returning hex string.
Falls back to default face if unspecified."
  (let* ((color (face-attribute face attr nil t))
         (vals (when (and color (not (eq color 'unspecified)))
                 (color-values color))))
    (if vals
        (apply #'format "#%02x%02x%02x"
               (mapcar (lambda (x) (/ x 256)) vals))
      (if (eq attr :background) "#1e1e2e" "#cdd6f4"))))

(defun markdown-modern-mermaid--theme-colors ()
  "Extract theme colors from current Emacs faces.
Returns plist with :bg :fg :surface :border :accent."
  (let* ((bg (markdown-modern-mermaid--face-color 'default :background))
         (fg (markdown-modern-mermaid--face-color 'default :foreground))
         (surface (markdown-modern-mermaid--color-blend bg fg 0.08))
         (border (markdown-modern-mermaid--color-blend bg fg 0.3))
         (accent (markdown-modern-mermaid--face-color 'font-lock-keyword-face :foreground)))
    (list :bg bg :fg fg :surface surface :border border :accent accent)))

;;; ============================================================
;;; SVG Primitives
;;; ============================================================

(defun markdown-modern-mermaid--svg-escape (text)
  "Escape TEXT for safe inclusion in SVG XML."
  (let ((s (if (stringp text) text (format "%s" text))))
    (setq s (replace-regexp-in-string "&" "&amp;" s))
    (setq s (replace-regexp-in-string "<" "&lt;" s))
    (setq s (replace-regexp-in-string ">" "&gt;" s))
    (setq s (replace-regexp-in-string "\"" "&quot;" s))
    s))

(defun markdown-modern-mermaid--svg-rect (x y w h rx fill stroke &optional stroke-width)
  "SVG rectangle at X Y with dimensions W H and corner radius RX.
FILL and STROKE are colours; STROKE-WIDTH defaults to 1.5."
  (format "<rect x=\"%d\" y=\"%d\" width=\"%d\" height=\"%d\" rx=\"%d\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>"
          x y w h rx fill stroke (or stroke-width "1.5")))

(defun markdown-modern-mermaid--svg-text (x y text font-size fill &optional anchor weight)
  "SVG TEXT at X Y with FONT-SIZE and FILL color.
ANCHOR is text-anchor (start, middle, end).  WEIGHT is font-weight."
  (format "<text x=\"%d\" y=\"%d\" font-family=\"sans-serif\" font-size=\"%d\" fill=\"%s\" text-anchor=\"%s\"%s>%s</text>"
          x y font-size fill
          (or anchor "middle")
          (if weight (format " font-weight=\"%s\"" weight) "")
          (markdown-modern-mermaid--svg-escape text)))

(defun markdown-modern-mermaid--svg-line (x1 y1 x2 y2 stroke &optional dash stroke-width)
  "SVG line from X1 Y1 to X2 Y2 in colour STROKE.
DASH sets stroke-dasharray; STROKE-WIDTH defaults to 1.5."
  (format "<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"%s\" stroke-width=\"%s\"%s/>"
          x1 y1 x2 y2 stroke (or stroke-width "1.5")
          (if dash (format " stroke-dasharray=\"%s\"" dash) "")))

(defun markdown-modern-mermaid--svg-path (d stroke fill &optional stroke-width dash)
  "SVG path with data D, colour STROKE and FILL.
DASH sets stroke-dasharray; STROKE-WIDTH defaults to 1.5."
  (format "<path d=\"%s\" stroke=\"%s\" fill=\"%s\" stroke-width=\"%s\"%s/>"
          d stroke fill (or stroke-width "1.5")
          (if dash (format " stroke-dasharray=\"%s\"" dash) "")))

(defun markdown-modern-mermaid--svg-circle (cx cy r fill stroke &optional stroke-width)
  "SVG circle at CX CY with radius R.
FILL and STROKE are colours; STROKE-WIDTH defaults to 1.5."
  (format "<circle cx=\"%d\" cy=\"%d\" r=\"%d\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>"
          cx cy r fill stroke (or stroke-width "1.5")))

(defun markdown-modern-mermaid--svg-diamond (cx cy w h fill stroke)
  "SVG diamond centered at CX CY with width W and height H.
FILL and STROKE are colours."
  (let ((hw (/ w 2))
        (hh (/ h 2)))
    (format "<polygon points=\"%d,%d %d,%d %d,%d %d,%d\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1.5\"/>"
            cx (- cy hh)
            (+ cx hw) cy
            cx (+ cy hh)
            (- cx hw) cy
            fill stroke)))

(defun markdown-modern-mermaid--svg-arrow-marker (id color &optional marker-type)
  "SVG <marker> definition for arrowhead with ID and COLOR.
MARKER-TYPE can be `arrow' (default), `open', `diamond', `circle'."
  (pcase (or marker-type 'arrow)
    ('arrow
     (format "<marker id=\"%s\" viewBox=\"0 0 10 10\" refX=\"10\" refY=\"5\" markerWidth=\"8\" markerHeight=\"8\" orient=\"auto-start-reverse\"><path d=\"M 0 0 L 10 5 L 0 10 z\" fill=\"%s\"/></marker>"
             id color))
    ('open
     (format "<marker id=\"%s\" viewBox=\"0 0 10 10\" refX=\"10\" refY=\"5\" markerWidth=\"8\" markerHeight=\"8\" orient=\"auto-start-reverse\"><path d=\"M 0 0 L 10 5 L 0 10\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.5\"/></marker>"
             id color))
    ('diamond
     (format "<marker id=\"%s\" viewBox=\"0 0 12 12\" refX=\"6\" refY=\"6\" markerWidth=\"10\" markerHeight=\"10\" orient=\"auto-start-reverse\"><polygon points=\"6,0 12,6 6,12 0,6\" fill=\"%s\"/></marker>"
             id color))
    ('circle
     (format "<marker id=\"%s\" viewBox=\"0 0 10 10\" refX=\"5\" refY=\"5\" markerWidth=\"8\" markerHeight=\"8\" orient=\"auto-start-reverse\"><circle cx=\"5\" cy=\"5\" r=\"4\" fill=\"%s\"/></marker>"
             id color))))

(defun markdown-modern-mermaid--svg-wrap (width height defs body)
  "Wrap BODY in SVG root element with WIDTH, HEIGHT, DEFS."
  (format "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">\n%s%s\n</svg>"
          width height width height
          (if defs (format "<defs>%s</defs>\n" defs) "")
          body))

(defun markdown-modern-mermaid--text-width (text font-size)
  "Estimate pixel width of TEXT at FONT-SIZE.
Uses average character width of 0.6 * font-size for sans-serif."
  (round (* (length text) font-size 0.6)))

;;; ============================================================
;;; Main Entry Point
;;; ============================================================

(defun markdown-modern-mermaid-render (diagram-code)
  "Render mermaid DIAGRAM-CODE to an SVG string.
Returns SVG XML string or nil if diagram type is unsupported."
  (let* ((lines (split-string diagram-code "\n" t "[ \t\r]+"))
         (first (car lines))
         (type (cond
                ((and first (string-match "^\\(?:graph\\|flowchart\\)" first)) 'flowchart)
                ((and first (string-match "^sequenceDiagram" first)) 'sequence)
                ((and first (string-match "^stateDiagram" first)) 'state)
                ((and first (string-match "^classDiagram" first)) 'class)
                ((and first (string-match "^erDiagram" first)) 'er)
                (t nil))))
    (when type
      (condition-case err
          (let ((colors (markdown-modern-mermaid--theme-colors)))
            (cond
             ((eq type 'flowchart) (markdown-modern-mermaid--render-flowchart lines colors))
             ((eq type 'sequence)  (markdown-modern-mermaid--render-sequence lines colors))
             ((eq type 'state)     (markdown-modern-mermaid--render-state lines colors))
             ((eq type 'class)     (markdown-modern-mermaid--render-class lines colors))
             ((eq type 'er)        (markdown-modern-mermaid--render-er lines colors))
             (t (message "markdown-modern-mermaid: unknown type %S" type) nil)))
        (error
         (message "markdown-modern-mermaid: %s render error: %s" type (error-message-string err))
         nil)))))

;;; ============================================================
;;; Flowchart Renderer
;;; ============================================================

(defun markdown-modern-mermaid--parse-flowchart (lines)
  "Parse flowchart LINES into (:direction DIR :nodes NODES :edges EDGES).
NODES is a hash-table id->(list :id :label :shape).
EDGES is a list of (list :from :to :label :style)."
  (let ((direction "TD")
        (nodes (make-hash-table :test 'equal))
        (edges nil)
        (first (car lines)))
    ;; Parse direction from first line
    (when (string-match "^\\(?:graph\\|flowchart\\)\\s-+\\(TB\\|TD\\|BT\\|LR\\|RL\\)" first)
      (setq direction (match-string 1 first)))
    ;; Parse remaining lines
    (dolist (raw-line (cdr lines))
      (let ((line (string-trim raw-line)))
        (unless (or (string-empty-p line)
                    (string-match-p "^%%" line)
                    (string-match-p "^\\(style\\|classDef\\|class\\|click\\|subgraph\\|end\\)" line))
          (cond
           ;; Edge: A[label] -->|text| B[label]
           ((string-match
             (concat "\\([A-Za-z0-9_]+\\)"
                     "\\(?:\\[\\([^]]*\\)\\]\\|(\\([^)]*\\))\\|{\\([^}]*\\)}\\|\\[\\[\\([^]]*\\)\\]\\]\\)?"
                     "[ \t]*"
                     "\\(--+>\\|==+>\\|-\\.->\\|--+\\)"
                     "[ \t]*"
                     "\\(?:|\\([^|]*\\)|\\)?"
                     "[ \t]*"
                     "\\([A-Za-z0-9_]+\\)"
                     "\\(?:\\[\\([^]]*\\)\\]\\|(\\([^)]*\\))\\|{\\([^}]*\\)}\\|\\[\\[\\([^]]*\\)\\]\\]\\)?")
             line)
            (let* ((from-id (match-string 1 line))
                   (from-label (or (match-string 2 line) (match-string 3 line)
                                   (match-string 4 line) (match-string 5 line)))
                   (arrow (match-string 6 line))
                   (edge-label (match-string 7 line))
                   (to-id (match-string 8 line))
                   (to-label (or (match-string 9 line) (match-string 10 line)
                                 (match-string 11 line) (match-string 12 line)))
                   (from-shape (cond ((match-string 2 line) 'rect)
                                     ((match-string 3 line) 'round)
                                     ((match-string 4 line) 'diamond)
                                     (t nil)))
                   (to-shape (cond ((match-string 9 line) 'rect)
                                   ((match-string 10 line) 'round)
                                   ((match-string 11 line) 'diamond)
                                   (t nil))))
              ;; Register nodes
              (unless (gethash from-id nodes)
                (puthash from-id (list :id from-id :label (or from-label from-id)
                                       :shape (or from-shape 'rect))
                         nodes))
              (when (and from-label (not from-shape))
                ;; Update label if we have one now
                (let ((existing (gethash from-id nodes)))
                  (when (string= (plist-get existing :label) from-id)
                    (puthash from-id (plist-put (copy-sequence existing) :label from-label) nodes))))
              (unless (gethash to-id nodes)
                (puthash to-id (list :id to-id :label (or to-label to-id)
                                     :shape (or to-shape 'rect))
                         nodes))
              (when (and to-label (not to-shape))
                (let ((existing (gethash to-id nodes)))
                  (when (string= (plist-get existing :label) to-id)
                    (puthash to-id (plist-put (copy-sequence existing) :label to-label) nodes))))
              (push (list :from from-id :to to-id
                          :label (when edge-label (string-trim edge-label))
                          :style (cond
                                  ((string-match-p "==>" arrow) 'thick)
                                  ((string-match-p "-\\.->" arrow) 'dotted)
                                  (t 'normal)))
                    edges)))
           ;; Standalone node: A[text] or A(text) or A{text}
           ((string-match
             "^\\([A-Za-z0-9_]+\\)\\(?:\\[\\([^]]*\\)\\]\\|(\\([^)]*\\))\\|{\\([^}]*\\)}\\)"
             line)
            (let ((id (match-string 1 line))
                  (label (or (match-string 2 line) (match-string 3 line) (match-string 4 line)))
                  (shape (cond ((match-string 2 line) 'rect)
                               ((match-string 3 line) 'round)
                               ((match-string 4 line) 'diamond))))
              (puthash id (list :id id :label (or label id) :shape (or shape 'rect)) nodes)))))))
    (list :direction direction :nodes nodes :edges (nreverse edges))))

(defun markdown-modern-mermaid--flowchart-topo-sort (nodes edges)
  "Topological sort of NODES given EDGES.  Return list of node IDs."
  (let* ((all-ids nil)
         (in-degree (make-hash-table :test 'equal))
         (adjacency (make-hash-table :test 'equal))
         (queue nil)
         (result nil))
    (maphash (lambda (k _v) (push k all-ids)) nodes)
    ;; Ensure edge endpoints exist
    (dolist (edge edges)
      (let ((from (plist-get edge :from))
            (to (plist-get edge :to)))
        (unless (member from all-ids) (push from all-ids))
        (unless (member to all-ids) (push to all-ids))
        (unless (gethash from nodes)
          (puthash from (list :id from :label from :shape 'rect) nodes))
        (unless (gethash to nodes)
          (puthash to (list :id to :label to :shape 'rect) nodes))))
    (setq all-ids (nreverse all-ids))
    (dolist (id all-ids) (puthash id 0 in-degree))
    (dolist (edge edges)
      (let ((from (plist-get edge :from))
            (to (plist-get edge :to)))
        (puthash from (cons to (gethash from adjacency nil)) adjacency)
        (puthash to (1+ (gethash to in-degree 0)) in-degree)))
    (dolist (id all-ids)
      (when (zerop (gethash id in-degree 0))
        (push id queue)))
    (setq queue (nreverse queue))
    (while queue
      (let ((node (pop queue)))
        (push node result)
        (dolist (neighbor (gethash node adjacency nil))
          (let ((new-deg (1- (gethash neighbor in-degree 1))))
            (puthash neighbor new-deg in-degree)
            (when (zerop new-deg)
              (setq queue (append queue (list neighbor))))))))
    (dolist (id all-ids)
      (unless (member id result) (push id result)))
    (nreverse result)))

(defun markdown-modern-mermaid--flowchart-assign-layers (node-ids edges)
  "Assign layer numbers to NODE-IDS based on EDGES.  Return alist (id . layer).
Back-edges (cycles) are ignored to prevent infinite layer growth."
  (let ((layers (make-hash-table :test 'equal))
        ;; Build a set of forward edges only (from appears before to in topo order)
        (topo-rank (make-hash-table :test 'equal))
        (forward-edges nil))
    ;; Assign topological rank to each node
    (let ((rank 0))
      (dolist (id node-ids)
        (puthash id rank topo-rank)
        (setq rank (1+ rank))))
    ;; Filter to forward edges only
    (dolist (edge edges)
      (let ((from (plist-get edge :from))
            (to (plist-get edge :to)))
        (when (< (gethash from topo-rank 0) (gethash to topo-rank 0))
          (push edge forward-edges))))
    ;; Assign layers using only forward edges
    (dolist (id node-ids) (puthash id 0 layers))
    (dotimes (_ (length node-ids))
      (dolist (edge forward-edges)
        (let* ((from (plist-get edge :from))
               (to (plist-get edge :to))
               (fl (gethash from layers 0))
               (tl (gethash to layers 0)))
          (when (< tl (1+ fl))
            (puthash to (1+ fl) layers)))))
    (let (result)
      (dolist (id node-ids)
        (push (cons id (gethash id layers 0)) result))
      (nreverse result))))

(defun markdown-modern-mermaid--render-flowchart (lines colors)
  "Render flowchart from LINES with theme COLORS.  Return SVG string."
  (let* ((parsed (markdown-modern-mermaid--parse-flowchart lines))
         (direction (plist-get parsed :direction))
         (nodes (plist-get parsed :nodes))
         (edges (plist-get parsed :edges))
         (horizontal (member direction '("LR" "RL")))
         (reverse-dir (member direction '("BT" "RL")))
         (bg (plist-get colors :bg))
         (fg (plist-get colors :fg))
         (surface (plist-get colors :surface))
         (border (plist-get colors :border))
         ;; Layout parameters
         (font-size 14)
         (node-pad-x 20)
         (node-h 40)
         (layer-gap (if horizontal 120 80))
         (sibling-gap 40)
         ;; Compute
         (sorted-ids (markdown-modern-mermaid--flowchart-topo-sort nodes edges))
         (effective-edges (if reverse-dir
                              (mapcar (lambda (e)
                                        (list :from (plist-get e :to)
                                              :to (plist-get e :from)
                                              :label (plist-get e :label)
                                              :style (plist-get e :style)))
                                      edges)
                            edges))
         (layer-alist (markdown-modern-mermaid--flowchart-assign-layers sorted-ids effective-edges))
         (max-layer (if layer-alist (apply #'max (mapcar #'cdr layer-alist)) 0))
         (layer-groups (make-hash-table :test 'equal))
         ;; Node positions: id -> (:x :y :w :h)
         (node-pos (make-hash-table :test 'equal))
         (svg-parts nil)
         (defs-parts nil)
         (total-w 0)
         (total-h 0))
    ;; Group nodes by layer
    (dolist (pair layer-alist)
      (puthash (cdr pair)
               (append (gethash (cdr pair) layer-groups nil) (list (car pair)))
               layer-groups))
    ;; Compute node widths
    (let ((node-widths (make-hash-table :test 'equal)))
      (maphash (lambda (id info)
                 (let* ((label (plist-get info :label))
                        (tw (markdown-modern-mermaid--text-width label font-size))
                        (shape (plist-get info :shape))
                        (w (pcase shape
                             ('diamond (+ tw (* node-pad-x 4)))
                             (_ (+ tw (* node-pad-x 2))))))
                   (puthash id (max w 70) node-widths)))
               nodes)
      ;; FIRST PASS: compute total-w and total-h before positioning
      (if horizontal
          (let ((x 20))
            (dotimes (layer (1+ max-layer))
              (let* ((layer-nodes (gethash layer layer-groups nil))
                     (max-w (apply #'max 70
                                   (mapcar (lambda (id) (gethash id node-widths 70)) layer-nodes)))
                     (count (length layer-nodes))
                     (layer-h (+ (* count node-h) (* (max 0 (1- count)) sibling-gap))))
                (setq total-h (max total-h (+ layer-h 40)))
                (setq x (+ x max-w layer-gap))))
            (setq total-w (+ x 20)))
        (progn
          (dotimes (layer (1+ max-layer))
            (let* ((layer-nodes (gethash layer layer-groups nil))
                   (layer-w 0))
              (dolist (id layer-nodes)
                (setq layer-w (+ layer-w (gethash id node-widths 70) sibling-gap)))
              (setq layer-w (- layer-w sibling-gap))
              (setq total-w (max total-w (+ layer-w 40)))))
          ;; total-w already computed from layer widths
          (setq total-h (+ 40 (* (1+ max-layer) (+ node-h layer-gap))))))
      ;; SECOND PASS: position nodes centered within total-w
      (if horizontal
          (let ((x 20))
            (dotimes (layer (1+ max-layer))
              (let* ((layer-nodes (gethash layer layer-groups nil))
                     (max-w (apply #'max 70
                                   (mapcar (lambda (id) (gethash id node-widths 70)) layer-nodes)))
                     (count (length layer-nodes))
                     (layer-h (+ (* count node-h) (* (max 0 (1- count)) sibling-gap)))
                     (y (/ (- total-h layer-h) 2)))
                (dolist (id layer-nodes)
                  (let ((w (gethash id node-widths 70)))
                    (puthash id (list :x (+ x (/ (- max-w w) 2)) :y y :w w :h node-h) node-pos)
                    (setq y (+ y node-h sibling-gap))))
                (setq x (+ x max-w layer-gap)))))
        (let ((y 20))
          (dotimes (layer (1+ max-layer))
            (let* ((layer-nodes (gethash layer layer-groups nil))
                   (layer-w 0))
              (dolist (id layer-nodes)
                (setq layer-w (+ layer-w (gethash id node-widths 70) sibling-gap)))
              (setq layer-w (- layer-w sibling-gap))
              (let ((x (/ (- total-w layer-w) 2)))
                (dolist (id layer-nodes)
                  (let ((w (gethash id node-widths 70)))
                    (puthash id (list :x x :y y :w w :h node-h) node-pos)
                    (setq x (+ x w sibling-gap)))))
              (setq y (+ y node-h layer-gap))))
          (setq total-h (+ y 20)))))
    ;; Check for back-edges that need right-side routing and widen SVG
    (let ((has-back-edge nil))
      (dolist (edge effective-edges)
        (let ((fp (gethash (plist-get edge :from) node-pos))
              (tp (gethash (plist-get edge :to) node-pos)))
          (when (and fp tp
                     (if horizontal
                         (>= (plist-get fp :x) (plist-get tp :x))
                       (>= (plist-get fp :y) (plist-get tp :y))))
            (setq has-back-edge t))))
      (when has-back-edge
        (setq total-w (+ total-w 60))))
    ;; Arrow marker
    (push (markdown-modern-mermaid--svg-arrow-marker "arrowhead" fg) defs-parts)
    ;; Background
    (push (markdown-modern-mermaid--svg-rect 0 0 total-w total-h 6 bg "none") svg-parts)
    ;; Draw edges first (behind nodes)
    (dolist (edge effective-edges)
      (let* ((from-id (plist-get edge :from))
             (to-id (plist-get edge :to))
             (from-pos (gethash from-id node-pos))
             (to-pos (gethash to-id node-pos))
             (label (plist-get edge :label))
             (style (plist-get edge :style)))
        (when (and from-pos to-pos)
          (let* ((dash (pcase style ('dotted "5,5") ('thick nil) (_ nil)))
                 (sw (pcase style ('thick "3") (_ "1.5")))
                 ;; Detect back-edge: target is above source (vertical) or left (horizontal)
                 (is-back-edge (if horizontal
                                   (>= (plist-get from-pos :x) (plist-get to-pos :x))
                                 (>= (plist-get from-pos :y) (plist-get to-pos :y))))
                 (sx 0) (sy 0) (ex 0) (ey 0))
            (if is-back-edge
                ;; Back-edge: route around the right side of nodes
                (let* ((from-right (+ (plist-get from-pos :x) (plist-get from-pos :w)))
                       (to-right (+ (plist-get to-pos :x) (plist-get to-pos :w)))
                       (from-cy (+ (plist-get from-pos :y) (/ (plist-get from-pos :h) 2)))
                       (to-cy (+ (plist-get to-pos :y) (/ (plist-get to-pos :h) 2)))
                       (route-x (+ (max from-right to-right) 30)))
                  (setq sx from-right sy from-cy ex to-right ey to-cy)
                  (push (format "<path d=\"M %d %d L %d %d L %d %d L %d %d\" stroke=\"%s\" fill=\"none\" stroke-width=\"%s\" marker-end=\"url(#arrowhead)\"%s/>"
                                sx sy route-x sy route-x ey ex ey
                                fg sw
                                (if dash (format " stroke-dasharray=\"%s\"" dash) ""))
                        svg-parts)
                  ;; Label on back-edge
                  (when label
                    (let ((lx (+ route-x 6))
                          (ly (/ (+ sy ey) 2)))
                      (push (markdown-modern-mermaid--svg-text lx ly label (1- font-size) fg "start") svg-parts))))
              ;; Forward edge: normal routing
              (let* ((fx (+ (plist-get from-pos :x) (/ (plist-get from-pos :w) 2)))
                     (fy (+ (plist-get from-pos :y) (/ (plist-get from-pos :h) 2)))
                     (tx (+ (plist-get to-pos :x) (/ (plist-get to-pos :w) 2)))
                     (ty (+ (plist-get to-pos :y) (/ (plist-get to-pos :h) 2))))
                ;; Adjust connection points to node borders
                (if horizontal
                    (progn
                      (setq sx (+ (plist-get from-pos :x) (plist-get from-pos :w)))
                      (setq sy fy)
                      (setq ex (plist-get to-pos :x))
                      (setq ey ty))
                  (setq sx fx)
                  (setq sy (+ (plist-get from-pos :y) (plist-get from-pos :h)))
                  (setq ex tx)
                  (setq ey (plist-get to-pos :y)))
                ;; Draw path
                (if (and (not horizontal) (/= sx ex))
                    (let ((mid-y (/ (+ sy ey) 2)))
                      (push (format "<path d=\"M %d %d C %d %d %d %d %d %d\" stroke=\"%s\" fill=\"none\" stroke-width=\"%s\" marker-end=\"url(#arrowhead)\"%s/>"
                                    sx sy sx mid-y ex mid-y ex ey
                                    fg sw
                                    (if dash (format " stroke-dasharray=\"%s\"" dash) ""))
                            svg-parts))
                  (if (and horizontal (/= sy ey))
                      (let ((mid-x (/ (+ sx ex) 2)))
                        (push (format "<path d=\"M %d %d C %d %d %d %d %d %d\" stroke=\"%s\" fill=\"none\" stroke-width=\"%s\" marker-end=\"url(#arrowhead)\"%s/>"
                                      sx sy mid-x sy mid-x ey ex ey
                                      fg sw
                                      (if dash (format " stroke-dasharray=\"%s\"" dash) ""))
                              svg-parts))
                    (push (format "<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"%s\" stroke-width=\"%s\" marker-end=\"url(#arrowhead)\"%s/>"
                                  sx sy ex ey fg sw
                                  (if dash (format " stroke-dasharray=\"%s\"" dash) ""))
                          svg-parts)))
                ;; Edge label
                (when label
                  (let ((lx (/ (+ sx ex) 2))
                        (ly (- (/ (+ sy ey) 2) 4)))
                    (push (markdown-modern-mermaid--svg-rect (- lx (/ (+ (markdown-modern-mermaid--text-width label font-size) 8) 2))
                                                        (- ly (1+ font-size))
                                                        (+ (markdown-modern-mermaid--text-width label font-size) 8)
                                                        (+ font-size 6)
                                                        3 bg "none")
                          svg-parts)
                    (push (markdown-modern-mermaid--svg-text lx ly label (1- font-size) fg) svg-parts)))))))))
    ;; Draw nodes
    (maphash
     (lambda (id pos)
       (let* ((info (gethash id nodes))
              (label (plist-get info :label))
              (shape (plist-get info :shape))
              (x (plist-get pos :x))
              (y (plist-get pos :y))
              (w (plist-get pos :w))
              (h (plist-get pos :h))
              (cx (+ x (/ w 2)))
              (cy (+ y (/ h 2)))
              (text-y (+ cy (/ font-size 3))))
         (pcase shape
           ('diamond
            (push (markdown-modern-mermaid--svg-diamond cx cy w h surface border) svg-parts))
           ('round
            (push (markdown-modern-mermaid--svg-rect x y w h (/ h 2) surface border) svg-parts))
           ('circle
            (let ((r (/ (max w h) 2)))
              (push (markdown-modern-mermaid--svg-circle cx cy r surface border) svg-parts)))
           (_
            (push (markdown-modern-mermaid--svg-rect x y w h 6 surface border) svg-parts)))
         (push (markdown-modern-mermaid--svg-text cx text-y label font-size fg) svg-parts)))
     node-pos)
    ;; Assemble SVG
    (markdown-modern-mermaid--svg-wrap
     total-w total-h
     (mapconcat #'identity (nreverse defs-parts) "\n")
     (mapconcat #'identity (nreverse svg-parts) "\n"))))

;;; ============================================================
;;; Sequence Diagram Renderer
;;; ============================================================

(defun markdown-modern-mermaid--parse-sequence (lines)
  "Parse sequence diagram LINES.
Return :participants (IDs in source order), :labels (ID to display label),
:messages, :blocks and :events.  Events preserve the order of messages and
block boundaries so layout can reserve space for each header and branch."
  (let ((participants nil)
        (labels (make-hash-table :test 'equal))
        (messages nil)
        (blocks nil)
        (events nil)
        (block-stack nil)
        (msg-idx 0)
        (number nil))
    (cl-labels ((register (id &optional label)
                  (unless (member id participants) (push id participants))
                  (when label (puthash id label labels))))
      (dolist (raw-line (cdr lines))
        (let ((line (string-trim raw-line)))
          (cond
           ((or (string-empty-p line) (string-prefix-p "%%" line)))
           ((string-match "^\\(?:participant\\|actor\\)\\s-+\\(\\S-+\\)\\(?:\\s-+as\\s-+\\(.+\\)\\)?$" line)
            (register (match-string 1 line) (match-string 2 line)))
           ((string= line "autonumber") (setq number 1))
           ;; Longest arrow spellings first; IDs may contain hyphens.
           ((string-match
             (concat "^\\(\\S-+?\\)\\s-*"
                     "\\(-->>\\|->>\\|-->\\|->\\|--)\\|-)\\)"
                     "\\s-*\\(\\S-+?\\)\\s-*:\\s-*\\(.*\\)$") line)
            (let* ((from (match-string 1 line))
                   (arrow (match-string 2 line))
                   (to (match-string 3 line))
                   (text (match-string 4 line))
                   (msg (list :from from :to to :text text
                              :type (cdr (assoc arrow '(("->>" . solid)
                                                        ("-->>" . dashed)
                                                        ("->" . solid-line)
                                                        ("-->" . dashed-line)
                                                        ("-)" . async)
                                                        ("--)" . dashed-async))))
                              :number number :index msg-idx)))
              (register from)
              (register to)
              (push msg messages)
              (push (cons 'message msg) events)
              (when number (setq number (1+ number)))
              (setq msg-idx (1+ msg-idx))))
           ((string-match "^Note\\s-+\\(over\\|left of\\|right of\\)\\s-+\\([^:]+\\):\\s-*\\(.*\\)$" line)
            (let* ((position (match-string 1 line))
                   (targets (match-string 2 line))
                   (text (match-string 3 line))
                   (ids (split-string targets "," t "[ \t]+"))
                   (msg (list :from (car ids) :to (car (last ids))
                              :text text :type 'note :position position
                              :index msg-idx)))
              (dolist (id ids) (register id))
              (push msg messages)
              (push (cons 'message msg) events)
              (setq msg-idx (1+ msg-idx))))
           ((string-match "^\\(alt\\|opt\\|loop\\|par\\|critical\\)\\(?:\\s-+\\(.*\\)\\)?$" line)
            (let ((block (list :type (intern (match-string 1 line))
                               :label (or (match-string 2 line) "")
                               :start msg-idx :sections nil
                               :depth (length block-stack))))
              (push block blocks)
              (push block block-stack)
              (push (cons 'start block) events)))
           ((string-match "^\\(?:else\\|and\\|option\\)\\(?:\\s-+\\(.*\\)\\)?$" line)
            (when block-stack
              (let ((section (list :label (or (match-string 1 line) "")
                                   :index msg-idx)))
                (push section (plist-get (car block-stack) :sections))
                (push (cons 'section section) events))))
           ((string= line "end")
            (when block-stack
              (let ((block (pop block-stack)))
                (plist-put block :end msg-idx)
                (push (cons 'end block) events))))))))
    (list :participants (nreverse participants) :labels labels
          :messages (nreverse messages) :blocks (nreverse blocks)
          :events (nreverse events))))

(defun markdown-modern-mermaid--sequence-text-lines (text)
  "Split sequence diagram TEXT at Mermaid line breaks."
  (split-string text "<br[ \t]*/?>"))

(defun markdown-modern-mermaid--sequence-text-width (text font-size)
  "Estimate the widest line of sequence diagram TEXT at FONT-SIZE."
  (apply #'max (mapcar (lambda (line)
                         (markdown-modern-mermaid--text-width line font-size))
                       (markdown-modern-mermaid--sequence-text-lines text))))

(defun markdown-modern-mermaid--sequence-text (x y text font-size fill &optional anchor)
  "Draw multiline TEXT at X Y with FONT-SIZE, FILL and ANCHOR.
Y is the baseline of the first line; subsequent lines are 18 pixels apart."
  (mapconcat (lambda (line)
               (prog1 (markdown-modern-mermaid--svg-text
                       x y line font-size fill anchor)
                 (setq y (+ y 18))))
             (markdown-modern-mermaid--sequence-text-lines text) "\n"))

(defun markdown-modern-mermaid--sequence-message-text (msg)
  "Return MSG's label including its sequence number, when enabled."
  (if (plist-get msg :number)
      (format "%s. %s" (plist-get msg :number) (plist-get msg :text))
    (plist-get msg :text)))

(defun markdown-modern-mermaid--sequence-note-bounds (msg positions)
  "Return (X . WIDTH) for note MSG using participant POSITIONS."
  (let* ((fx (gethash (plist-get msg :from) positions))
         (tx (gethash (plist-get msg :to) positions))
         (over (equal (plist-get msg :position) "over"))
         (width (max (+ 24 (markdown-modern-mermaid--sequence-text-width
                            (plist-get msg :text) 13))
                     (if over (+ 24 (abs (- fx tx))) 0)))
         (x (pcase (plist-get msg :position)
              ("left of" (- fx 12 width))
              ("right of" (+ fx 12))
              (_ (- (/ (+ fx tx) 2) (/ width 2))))))
    (cons x width)))

(defun markdown-modern-mermaid--layout-sequence (parsed)
  "Lay out PARSED sequence diagram and annotate events with vertical positions.
Return participant :positions, :width, :height, :box-height and :bottom."
  (let* ((participants (plist-get parsed :participants))
         (labels (plist-get parsed :labels))
         (messages (plist-get parsed :messages))
         (blocks (plist-get parsed :blocks))
         (positions (make-hash-table :test 'equal))
         (widths (mapcar (lambda (id)
                           (max 80 (+ 40 (markdown-modern-mermaid--sequence-text-width
                                          (gethash id labels id) 14))))
                         participants))
         (box-height (apply #'max 40
                            (mapcar (lambda (id)
                                      (+ 20 (* 18 (length
                                                   (markdown-modern-mermaid--sequence-text-lines
                                                    (gethash id labels id))))))
                                    participants)))
         (gap 180)
         (min-x 0)
         (max-x 0)
         (depth (apply #'max 0 (mapcar (lambda (block) (plist-get block :depth)) blocks)))
         (margin (+ 20 (* 12 depth)))
         (y (+ 40 box-height)))
    ;; Keep adjacent boxes and message labels from overlapping other columns.
    (cl-loop for (left right) on widths while right
             do (setq gap (max gap (+ (/ (+ left right) 2) 40))))
    (dolist (msg messages)
      (unless (or (eq (plist-get msg :type) 'note)
                  (equal (plist-get msg :from) (plist-get msg :to)))
        (let ((span (abs (- (cl-position (plist-get msg :from) participants :test #'equal)
                            (cl-position (plist-get msg :to) participants :test #'equal)))))
          (setq gap (max gap (ceiling (+ 24 (markdown-modern-mermaid--sequence-text-width
                                             (markdown-modern-mermaid--sequence-message-text msg) 13))
                                      span))))))
    (cl-loop for id in participants for width in widths for i from 0
             for x = (* i gap)
             do (puthash id x positions)
             (setq min-x (min min-x (- x (/ width 2)))
                   max-x (max max-x (+ x (/ width 2)))))
    ;; Include notes and self-message labels in the canvas, even outside lifelines.
    (dolist (msg messages)
      (cond
       ((eq (plist-get msg :type) 'note)
        (let ((bounds (markdown-modern-mermaid--sequence-note-bounds msg positions)))
          (setq min-x (min min-x (car bounds))
                max-x (max max-x (+ (car bounds) (cdr bounds))))))
       ((equal (plist-get msg :from) (plist-get msg :to))
        (setq max-x (max max-x
                         (+ (gethash (plist-get msg :from) positions)
                            (max 40 (+ 8 (markdown-modern-mermaid--sequence-text-width
                                          (markdown-modern-mermaid--sequence-message-text msg) 13)))))))))
    (let ((offset (- margin min-x)))
      (maphash (lambda (id x) (puthash id (+ x offset) positions)) positions))
    (setq max-x (+ (- max-x min-x) (* 2 margin)))
    ;; Long conditions must also fit inside their frames.
    (dolist (block blocks)
      (let ((inset (+ 20 (* 24 (plist-get block :depth)))))
        (setq max-x (max max-x
                         (+ inset 24
                            (markdown-modern-mermaid--text-width
                             (upcase (symbol-name (plist-get block :type))) 13)
                            (markdown-modern-mermaid--sequence-text-width
                             (concat "[" (plist-get block :label) "]") 13))))
        (dolist (section (plist-get block :sections))
          (setq max-x (max max-x
                           (+ inset 40 (markdown-modern-mermaid--sequence-text-width
                                        (concat "[" (plist-get section :label) "]") 13)))))))
    ;; Every structural event gets space of its own, including empty branches.
    (dolist (event (plist-get parsed :events))
      (let ((item (cdr event)))
        (pcase (car event)
          ('message
           (let* ((text (markdown-modern-mermaid--sequence-message-text item))
                  (text-height (* 18 (length (markdown-modern-mermaid--sequence-text-lines text))))
                  (note (eq (plist-get item :type) 'note))
                  (self (equal (plist-get item :from) (plist-get item :to))))
             (plist-put item :y y)
             (plist-put item :text-height text-height)
             (setq y (+ y text-height (if note 32 (if self 48 28))))))
          ((or 'start 'section)
           (plist-put item :y y)
           (setq y (+ y 16 (* 18 (length (markdown-modern-mermaid--sequence-text-lines
                                          (plist-get item :label)))))))
          ('end
           (plist-put item :bottom y)
           (setq y (+ y 16))))))
    ;; Incomplete blocks can occur during editing; keep their contents visible.
    (dolist (block blocks)
      (unless (plist-get block :bottom) (plist-put block :bottom y)))
    (list :positions positions :width max-x :height (+ y box-height 20)
          :box-height box-height :bottom y)))

(defun markdown-modern-mermaid--render-sequence (lines colors)
  "Render sequence diagram from LINES with COLORS.  Return SVG string."
  (let* ((parsed (markdown-modern-mermaid--parse-sequence lines))
         (participants (plist-get parsed :participants))
         (labels (plist-get parsed :labels))
         (bg (plist-get colors :bg))
         (fg (plist-get colors :fg))
         (surface (plist-get colors :surface))
         (border (plist-get colors :border))
         (accent (plist-get colors :accent)))
    (when participants
      (let* ((layout (markdown-modern-mermaid--layout-sequence parsed))
             (positions (plist-get layout :positions))
             (width (plist-get layout :width))
             (height (plist-get layout :height))
             (box-h (plist-get layout :box-height))
             (bottom (plist-get layout :bottom))
             (parts nil))
        (push (markdown-modern-mermaid--svg-rect 0 0 width height 6 bg "none") parts)
        ;; Frames and conditions precede the lifelines and messages.
        (dolist (block (plist-get parsed :blocks))
          (let* ((x (+ 10 (* 12 (plist-get block :depth))))
                 (y (plist-get block :y))
                 (right (- width x))
                 (type (upcase (symbol-name (plist-get block :type))))
                 (tag-w (+ 12 (markdown-modern-mermaid--text-width type 13))))
            (push (markdown-modern-mermaid--svg-rect
                   x y (- right x) (- (plist-get block :bottom) y) 4 "none" border "1") parts)
            (push (markdown-modern-mermaid--svg-rect x y tag-w 22 4 surface border) parts)
            (push (markdown-modern-mermaid--svg-text (+ x (/ tag-w 2)) (+ y 15)
                                                     type 13 accent nil "bold") parts)
            (push (markdown-modern-mermaid--sequence-text
                   (+ x tag-w 8) (+ y 15) (concat "[" (plist-get block :label) "]") 13 fg "start") parts)
            (dolist (section (plist-get block :sections))
              (let ((sy (plist-get section :y)))
                (push (markdown-modern-mermaid--svg-line x sy right sy border "5,5") parts)
                (push (markdown-modern-mermaid--sequence-text
                       (+ x 20) (+ sy 18) (concat "[" (plist-get section :label) "]") 13 fg "start") parts)))))
        (dolist (id participants)
          (let* ((x (gethash id positions))
                 (label (gethash id labels id))
                 (bw (max 80 (+ 40 (markdown-modern-mermaid--sequence-text-width label 14))))
                 (text-h (* 18 (length (markdown-modern-mermaid--sequence-text-lines label)))))
            (push (markdown-modern-mermaid--svg-line x (+ 20 box-h) x bottom border "4,4") parts)
            (dolist (y (list 20 bottom))
              (push (markdown-modern-mermaid--svg-rect (- x (/ bw 2)) y bw box-h 6 surface border) parts)
              (push (markdown-modern-mermaid--sequence-text
                     x (+ y (/ (- box-h text-h) 2) 14) label 14 fg) parts))))
        (dolist (msg (plist-get parsed :messages))
          (let* ((fx (gethash (plist-get msg :from) positions))
                 (tx (gethash (plist-get msg :to) positions))
                 (text (markdown-modern-mermaid--sequence-message-text msg))
                 (type (plist-get msg :type))
                 (y (plist-get msg :y))
                 (text-h (plist-get msg :text-height)))
            (if (eq type 'note)
                (let* ((bounds (markdown-modern-mermaid--sequence-note-bounds msg positions))
                       (x (car bounds))
                       (nw (cdr bounds)))
                  (push (markdown-modern-mermaid--svg-rect
                         x y nw (+ text-h 16) 4
                         (markdown-modern-mermaid--color-blend bg accent 0.1) accent) parts)
                  (push (markdown-modern-mermaid--sequence-text
                         (+ x (/ nw 2)) (+ y 21) text 13 fg) parts))
              (let* ((my (+ y text-h 8))
                     (self (= fx tx))
                     (dashed (memq type '(dashed dashed-line dashed-async)))
                     (marker (cond ((memq type '(solid-line dashed-line)) "")
                                   ((memq type '(async dashed-async)) " marker-end=\"url(#seq-open)\"")
                                   (t " marker-end=\"url(#seq-arrow)\"")))
                     (style (concat marker (if dashed " stroke-dasharray=\"5,5\"" ""))))
                (push (if self
                          (format "<path d=\"M %d %d H %d V %d H %d\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.5\"%s/>"
                                  fx my (+ fx 30) (+ my 20) fx fg style)
                        (format "<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"%s\" stroke-width=\"1.5\"%s/>"
                                fx my tx my fg style)) parts)
                (push (markdown-modern-mermaid--sequence-text
                       (if self (+ fx 8) (/ (+ fx tx) 2)) (+ y 13) text 13 fg
                       (if self "start" "middle")) parts)))))
        (markdown-modern-mermaid--svg-wrap
         width height
         (concat (markdown-modern-mermaid--svg-arrow-marker "seq-arrow" fg)
                 (markdown-modern-mermaid--svg-arrow-marker "seq-open" fg 'open))
         (mapconcat #'identity (nreverse parts) "\n"))))))

;;; ============================================================
;;; State Diagram Renderer
;;; ============================================================

(defun markdown-modern-mermaid--parse-state (lines)
  "Parse state diagram LINES into states, transitions and direction.
State identities are independent of descriptions.  The start and end
pseudostates have distinct symbol IDs, separate from user-supplied IDs."
  (let ((states (make-hash-table :test 'equal))
        (transitions nil)
        (direction "TB")
        (in-note nil)
        (id-pattern "\\([^[:space:]:;{}]+?\\)"))
    (cl-labels
        ((register (id &optional label)
           (unless (gethash id states)
             (puthash id (list :id id :label (if (stringp id) id "")
                               :type (if (symbolp id) id 'state)) states))
           (when label (plist-put (gethash id states) :label label))))
      (dolist (raw-line (cdr lines))
        (let ((line (string-trim (car (split-string raw-line "%%")))))
          (setq line (string-trim-right line "[; \t]+"))
          (cond
           ((or (string-empty-p line) (string-prefix-p "%%" line)))
           (in-note (when (equal line "end note") (setq in-note nil)))
           ((string-match-p "^note\\s-" line)
            (setq in-note (not (string-match-p ":" line))))
           ((string-match "^direction\\s-+\\(TB\\|TD\\|BT\\|LR\\|RL\\)$" line)
            (setq direction (match-string 1 line)))
           ((string-match (concat "^state\\s-+\"\\([^\"]*\\)\"\\s-+as\\s-+"
                                  id-pattern "$") line)
            (register (match-string 2 line) (match-string 1 line)))
           ;; A colon terminates the target ID, even with no surrounding spaces.
           ((string-match (concat "^" id-pattern "\\s-*-->\\s-*" id-pattern
                                  "\\(?:\\s-*:\\s-*\\(.*\\)\\)?$") line)
            (let* ((from (match-string 1 line))
                   (to (match-string 2 line))
                   (label (match-string 3 line)))
              (when (equal from "[*]") (setq from 'start))
              (when (equal to "[*]") (setq to 'end))
              (register from)
              (register to)
              (push (list :from from :to to
                          :label (and label (not (string-empty-p label)) label))
                    transitions)))
           ((string-match (concat "^" id-pattern "\\s-*:\\s-*\\(.*\\)$") line)
            (register (match-string 1 line) (match-string 2 line)))
           ((string-match (concat "^\\(?:state\\s-+\\)?" id-pattern "$") line)
            (unless (member line '("}" "--")) (register (match-string 1 line))))))))
    (list :states states :transitions (nreverse transitions) :direction direction)))

(defun markdown-modern-mermaid--state-order (states transitions)
  "Return a cycle-aware order for STATES connected by TRANSITIONS.
Depth-first finishing order puts forward transitions before their targets.
Only edges to active ancestors (and self-loops) need feedback routing."
  (let ((adjacency (make-hash-table :test 'equal))
        (incoming (make-hash-table :test 'equal))
        (visited (make-hash-table :test 'equal))
        order)
    (dolist (edge (reverse transitions))
      (push (plist-get edge :to) (gethash (plist-get edge :from) adjacency))
      (puthash (plist-get edge :to) t incoming))
    (cl-labels ((visit (id)
                 (unless (gethash id visited)
                   (puthash id t visited)
                   (dolist (to (gethash id adjacency)) (visit to))
                   (push id order))))
      (when (gethash 'start states) (visit 'start))
      (maphash (lambda (id _) (unless (gethash id incoming) (visit id))) states)
      (maphash (lambda (id _) (visit id)) states))
    order))

(defun markdown-modern-mermaid--state-text-size (text font-size)
  "Return the padded (WIDTH . HEIGHT) of TEXT at FONT-SIZE."
  (cons (+ 16 (markdown-modern-mermaid--sequence-text-width text font-size))
        (+ 10 (* 18 (length (markdown-modern-mermaid--sequence-text-lines text))))))

(defun markdown-modern-mermaid--state-sort-layers (layers links)
  "Reduce crossings in LAYERS using adjacent vertex LINKS.
Each layer contains vertex plists.  Invisible routing vertices participate
in the ordering so transitions spanning several layers avoid real states."
  (let ((before (make-hash-table :test 'eq))
        (after (make-hash-table :test 'eq))
        (positions (make-hash-table :test 'eq))
        best best-score)
    (dolist (link links)
      (push (car link) (gethash (cdr link) before))
      (push (cdr link) (gethash (car link) after)))
    (cl-labels
        ((index-layers ()
           (dotimes (rank (length layers))
             (cl-loop for vertex in (aref layers rank) for i from 0
                      do (puthash vertex i positions))))
         (score ()
           (let ((crossings 0))
             (cl-loop for rest on links for a = (car rest) do
                      (dolist (b (cdr rest))
                        (when (and (= (plist-get (car a) :rank)
                                      (plist-get (car b) :rank))
                                   (< (* (- (gethash (car a) positions)
                                            (gethash (car b) positions))
                                         (- (gethash (cdr a) positions)
                                            (gethash (cdr b) positions))) 0))
                          (cl-incf crossings))))
             crossings))
         (remember ()
           (let ((value (score)))
             (when (or (null best-score) (< value best-score))
               (setq best-score value best (copy-sequence layers))))))
      (index-layers)
      (remember)
      (dotimes (sweep 8)
        (let ((down (cl-evenp sweep)))
          (dotimes (step (1- (length layers)))
            (let* ((rank (if down (1+ step) (- (length layers) step 2)))
                   (neighbors (if down before after))
                   (weights (make-hash-table :test 'eq)))
              (dolist (vertex (aref layers rank))
                (let ((ids (gethash vertex neighbors)))
                  (puthash vertex
                           (if ids (/ (float (apply #'+ (mapcar
                                                         (lambda (id) (gethash id positions)) ids)))
                                      (length ids))
                             (gethash vertex positions)) weights)))
              (aset layers rank
                    (cl-stable-sort (copy-sequence (aref layers rank))
                                    (lambda (a b) (< (gethash a weights) (gethash b weights)))))
              (index-layers))))
        (remember)))
    best))

(defun markdown-modern-mermaid--layout-state (parsed)
  "Lay out PARSED state diagram with separate transition and label space.
Return :nodes, :routes, :width and :height.  Routes contain SVG-coordinate
:points and optional :label-box rectangles.  Internal coordinates use X
across layers and Y along them; horizontal directions are transposed last."
  (let* ((states (plist-get parsed :states))
         (transitions (plist-get parsed :transitions))
         (direction (plist-get parsed :direction))
         (horizontal (member direction '("LR" "RL")))
         (backward (member direction '("BT" "RL")))
         (order (markdown-modern-mermaid--state-order states transitions))
         (ranks (markdown-modern-mermaid--flowchart-assign-layers order transitions))
         (max-rank (* 2 (apply #'max 0 (mapcar #'cdr ranks))))
         (layers (make-vector (1+ max-rank) nil))
         (nodes (make-hash-table :test 'equal))
         (outgoing (make-hash-table :test 'equal))
         (incoming (make-hash-table :test 'equal))
         (feedback-out (make-vector (1+ max-rank) nil))
         (feedback-in (make-vector (1+ max-rank) nil))
         (feedback-space (make-vector (1+ max-rank) 0))
         (row-tops (make-vector (1+ max-rank) 0))
         (row-bottoms (make-vector (1+ max-rank) 0))
         links routes
         (width 0) (height 0))
    (cl-labels
        ((vertex (rank w h &optional id label)
           (let ((v (list :rank rank :w (if horizontal h w) :h (if horizontal w h)
                          :id id :label label :x 0 :y 0)))
             (push v (aref layers rank)) v))
         (port (route source)
           (let* ((id (plist-get route (if source :from :to)))
                  (node (gethash id nodes))
                  (edges (gethash id (if source outgoing incoming)))
                  (count (length edges))
                  (offset (* (min 14 (/ (plist-get node :w) (1+ count)))
                             (- (cl-position route edges :test #'eq) (/ (1- count) 2.0))))
                  (radius (/ (plist-get node :h) 2.0))
                  (dy (if (memq id '(start end))
                          (sqrt (max 0 (- (* radius radius) (* offset offset))))
                        radius)))
             (cons (+ (plist-get node :x) offset)
                   (+ (plist-get node :y) (* (if source 1 -1) dy)))))
         (transform (point)
           (let ((x (car point)) (y (if backward (- height (cdr point)) (cdr point))))
             (if horizontal (cons y x) (cons x y))))
         (box (v)
           (let ((center (transform (cons (plist-get v :x) (plist-get v :y))))
                 (w (plist-get v (if horizontal :h :w)))
                 (h (plist-get v (if horizontal :w :h))))
             (list :x (- (car center) (/ w 2.0)) :y (- (cdr center) (/ h 2.0))
                   :w w :h h))))
      (dolist (pair ranks)
        (let* ((id (car pair))
               (info (gethash id states))
               (size (markdown-modern-mermaid--state-text-size (plist-get info :label) 14))
               (pseudo (memq (plist-get info :type) '(start end)))
               (diameter (if (eq (plist-get info :type) 'start) 20 24)))
          (puthash id (vertex (* 2 (cdr pair))
                              (if pseudo diameter (max 80 (+ 20 (car size))))
                              (if pseudo diameter (max 40 (+ 8 (cdr size)))) id) nodes)))
      ;; Every forward edge has its own waypoint in every intermediate layer.
      ;; One waypoint holds the label and reserves its full dimensions.
      (dolist (edge transitions)
        (let* ((from (gethash (plist-get edge :from) nodes))
               (to (gethash (plist-get edge :to) nodes))
               (fr (plist-get from :rank)) (tr (plist-get to :rank))
               (label (plist-get edge :label))
               (route (append (copy-sequence edge) (list :back (>= fr tr))))
               (chain (list from))
               (label-rank (1+ (* 2 (/ (+ fr tr -2) 4)))))
          (if (>= fr tr)
              (progn
                (push route (aref feedback-out fr))
                (push route (aref feedback-in tr)))
            (cl-loop for rank from (1+ fr) below tr do
                     (let* ((text (and (= rank label-rank) label))
                            (size (and text (markdown-modern-mermaid--state-text-size text 13)))
                            (v (if size (vertex rank (car size) (cdr size) nil text)
                                 (vertex rank (if horizontal 0 12) (if horizontal 12 0)))))
                       (when text (plist-put route :label-vertex v))
                       (push v chain)))
            (push to chain)
            (setq chain (nreverse chain))
            (cl-loop for (a b) on chain while b do (push (cons a b) links))
            (plist-put route :vertices chain))
          (push route routes)
          (push route (gethash (plist-get edge :from) outgoing))
          (push route (gethash (plist-get edge :to) incoming))))
      (setq routes (nreverse routes))
      ;; Each returning label gets a band above its target.  Other return
      ;; arrows cross the outside lanes only between these label bands.
      (dotimes (rank (length layers))
        (dolist (route (aref feedback-in rank))
          (let* ((label (plist-get route :label))
                 (size (and label (markdown-modern-mermaid--state-text-size label 13)))
                 (depth (if size (if horizontal (car size) (cdr size)) 0)))
            (cl-incf (aref feedback-space rank) (+ 24 depth))
            (plist-put route :entry-offset (aref feedback-space rank)))))
      (dotimes (rank (length layers)) (aset layers rank (nreverse (aref layers rank))))
      (setq layers (markdown-modern-mermaid--state-sort-layers layers links))
      (dotimes (rank (length layers))
        (setq width (max width (+ 40 (apply #'+ (mapcar
                                                (lambda (v) (+ 24 (plist-get v :w)))
                                                (aref layers rank)))))))
      (dotimes (rank (length layers))
        (let* ((row (aref layers rank))
               (row-width (- (apply #'+ (mapcar (lambda (v) (+ 24 (plist-get v :w))) row)) 24))
               (row-height (apply #'max 0 (mapcar (lambda (v) (plist-get v :h)) row)))
               (x (/ (- width row-width) 2.0)))
          (cl-incf height (+ 20 (aref feedback-space rank)))
          (aset row-tops rank height)
          (dolist (v row)
            (plist-put v :x (+ x (/ (plist-get v :w) 2.0)))
            (plist-put v :y (+ height (/ row-height 2.0)))
            (cl-incf x (+ (plist-get v :w) 24)))
          (cl-incf height row-height)
          (aset row-bottoms rank height)
          (cl-incf height (+ 20 (* 16 (length (aref feedback-out rank)))))))
      ;; Sort ports by their next waypoint to avoid crossings at the node edge.
      (dolist (table (list outgoing incoming))
        (maphash
         (lambda (id edges)
           (puthash id
                    (cl-stable-sort
                     edges (lambda (a b)
                             (cl-labels ((next-x (r)
                                           (if (plist-get r :back) width
                                             (plist-get (if (eq table outgoing)
                                                            (cadr (plist-get r :vertices))
                                                          (car (last (plist-get r :vertices) 2))) :x))))
                               (< (next-x a) (next-x b))))) table)) table))
      (let ((lane-x width))
        (dolist (route routes)
          (let ((start (port route t)) (end (port route nil)) points)
            (if (plist-get route :back)
                (let* ((fr (plist-get (gethash (plist-get route :from) nodes) :rank))
                       (tr (plist-get (gethash (plist-get route :to) nodes) :rank))
                       (sy (+ (aref row-bottoms fr) 16
                              (* 16 (cl-position route (aref feedback-out fr) :test #'eq))))
                       (ty (- (aref row-tops tr) (plist-get route :entry-offset)))
                       (label (plist-get route :label))
                       (size (and label (markdown-modern-mermaid--state-text-size label 13)))
                       (w (if size (if horizontal (cdr size) (car size)) 0))
                       (h (if size (if horizontal (car size) (cdr size)) 0)))
                  (cl-incf lane-x (+ 24 (/ w 2.0)))
                  (setq points (list start (cons (car start) sy) (cons lane-x sy)
                                     (cons lane-x ty) (cons (car end) ty) end))
                  (when label
                    (plist-put route :label-box
                               (box (list :x lane-x :y (+ ty 8 (/ h 2.0)) :w w :h h))))
                  (cl-incf lane-x (+ 24 (/ w 2.0))))
              (setq points (list start))
              (push (cons (car start)
                          (aref row-bottoms (plist-get (gethash (plist-get route :from) nodes) :rank)))
                    points)
              (dolist (v (butlast (cdr (plist-get route :vertices))))
                ;; Stay vertical across the entire row, including beside
                ;; taller siblings, and bend only in the space between rows.
                (push (cons (plist-get v :x) (aref row-tops (plist-get v :rank))) points)
                (push (cons (plist-get v :x) (aref row-bottoms (plist-get v :rank))) points))
              (push (cons (car end)
                          (aref row-tops (plist-get (gethash (plist-get route :to) nodes) :rank)))
                    points)
              (push end points)
              (setq points (nreverse points))
              (when (plist-get route :label-vertex)
                (plist-put route :label-box (box (plist-get route :label-vertex)))))
            (plist-put route :points (mapcar #'transform points))))
        (setq width (max width (+ lane-x 20))))
      (maphash (lambda (id v) (puthash id (box v) nodes)) nodes))
    (list :nodes nodes :routes routes :horizontal horizontal
          :width (ceiling (if horizontal height width))
          :height (ceiling (if horizontal width height)))))

(defun markdown-modern-mermaid--state-path (points horizontal straight)
  "Return a path through POINTS, using HORIZONTAL layer orientation.
Use smooth curves between layers, or line segments when STRAIGHT is non-nil."
  ;; A zero-length final segment makes SVG orient the arrowhead to the right
  ;; instead of along the incoming edge.  Row-boundary stubs can coincide.
  (let (distinct)
    (dolist (point points)
      (unless (and distinct (= (car point) (caar distinct))
                   (= (cdr point) (cdar distinct)))
        (push point distinct)))
    (setq points (nreverse distinct)))
  (concat (format "M %.1f %.1f" (caar points) (cdar points))
          (mapconcat
           (lambda (pair)
             (let* ((a (car pair)) (b (cadr pair))
                    (mx (/ (+ (car a) (car b)) 2.0))
                    (my (/ (+ (cdr a) (cdr b)) 2.0)))
               (if (or straight (= (car a) (car b)) (= (cdr a) (cdr b)))
                   (format " L %.1f %.1f" (car b) (cdr b))
                 (format " C %.1f %.1f %.1f %.1f %.1f %.1f"
                         (if horizontal mx (car a)) (if horizontal (cdr a) my)
                         (if horizontal mx (car b)) (if horizontal (cdr b) my)
                         (car b) (cdr b)))))
           (cl-loop for rest on points while (cdr rest) collect (list (car rest) (cadr rest))) "")))

(defun markdown-modern-mermaid--render-state (lines colors)
  "Render state diagram from LINES with COLORS.  Return SVG string."
  (let* ((parsed (markdown-modern-mermaid--parse-state lines))
         (states (plist-get parsed :states))
         (bg (plist-get colors :bg))
         (fg (plist-get colors :fg))
         parts)
    (when (> (hash-table-count states) 0)
      (let* ((layout (markdown-modern-mermaid--layout-state parsed))
             (width (plist-get layout :width)) (height (plist-get layout :height)))
        (push (markdown-modern-mermaid--svg-rect 0 0 width height 6 bg "none") parts)
        (dolist (route (plist-get layout :routes))
          (push (format "<path d=\"%s\" stroke=\"%s\" fill=\"none\" stroke-width=\"1.5\" stroke-linejoin=\"round\" marker-end=\"url(#state-arrow)\"/>"
                        (markdown-modern-mermaid--state-path
                         (plist-get route :points) (plist-get layout :horizontal) (plist-get route :back)) fg) parts))
        (maphash
         (lambda (id pos)
           (let* ((info (gethash id states))
                  (x (plist-get pos :x)) (y (plist-get pos :y))
                  (w (plist-get pos :w)) (h (plist-get pos :h))
                  (cx (+ x (/ w 2.0))) (cy (+ y (/ h 2.0))))
             (pcase (plist-get info :type)
               ('start (push (markdown-modern-mermaid--svg-circle cx cy 10 fg fg) parts))
               ('end
                (push (markdown-modern-mermaid--svg-circle cx cy 12 bg fg) parts)
                (push (markdown-modern-mermaid--svg-circle cx cy 8 fg fg) parts))
               (_
                (push (markdown-modern-mermaid--svg-rect x y w h 8
                                                       (plist-get colors :surface)
                                                       (plist-get colors :border)) parts)
                (push (markdown-modern-mermaid--sequence-text
                       cx (+ y 25) (plist-get info :label) 14 fg) parts)))))
         (plist-get layout :nodes))
        ;; Draw labels last, in the space reserved during layout.
        (dolist (route (plist-get layout :routes))
          (when-let* ((box (plist-get route :label-box)))
            (let ((x (plist-get box :x)) (y (plist-get box :y))
                  (w (plist-get box :w)) (h (plist-get box :h)))
              (push (markdown-modern-mermaid--svg-rect x y w h 3 bg "none") parts)
              (push (markdown-modern-mermaid--sequence-text
                     (+ x (/ w 2.0)) (+ y 19) (plist-get route :label) 13 fg) parts))))
        (markdown-modern-mermaid--svg-wrap
         width height (markdown-modern-mermaid--svg-arrow-marker "state-arrow" fg)
         (mapconcat #'identity (nreverse parts) "\n"))))))

;;; ============================================================
;;; Class Diagram Renderer
;;; ============================================================

(defun markdown-modern-mermaid--parse-class (lines)
  "Parse class diagram LINES.
Returns (:classes CLASSES :relationships RELS).
CLASSES is hash-table name->(list :name :attrs :methods).
RELS is list of (:from FROM :to TO :type TYPE :label LABEL)."
  (let ((classes (make-hash-table :test 'equal))
        (relationships nil)
        (current-class nil))
    (dolist (raw-line (cdr lines))
      (let ((line (string-trim raw-line)))
        (cond
         ;; End of class body
         ((and current-class (string= line "}"))
          (setq current-class nil))
         ;; Inside class body - attribute or method
         (current-class
          (let ((cls (gethash current-class classes)))
            (when cls
              (if (string-match "(.*)" line)
                  (plist-put cls :methods
                             (append (plist-get cls :methods) (list line)))
                (plist-put cls :attrs
                           (append (plist-get cls :attrs) (list line)))))))
         ;; class Name { ... }
         ((string-match "^class\\s-+\\(\\S-+\\)\\s-*{?" line)
          (let ((name (match-string 1 line)))
            (unless (gethash name classes)
              (puthash name (list :name name :attrs nil :methods nil) classes))
            (when (string-match "{" line)
              (setq current-class name))))
         ;; class Name
         ((string-match "^class\\s-+\\(\\S-+\\)$" line)
          (let ((name (match-string 1 line)))
            (unless (gethash name classes)
              (puthash name (list :name name :attrs nil :methods nil) classes))))
         ;; Relationship: A <|-- B, A *-- B, A o-- B, A --> B, A -- B, A ..> B
         ((string-match
           "^\\(\\S-+\\)\\s-+\\(<|--\\|\\*--\\|o--\\|-->\\|--\\|\\.\\+>\\|\\.\\.>\\)\\s-+\\(\\S-+\\)\\(?:\\s-*:\\s-*\\(.*\\)\\)?"
           line)
          (let ((from (match-string 1 line))
                (rel (match-string 2 line))
                (to (match-string 3 line))
                (label (match-string 4 line)))
            (unless (gethash from classes)
              (puthash from (list :name from :attrs nil :methods nil) classes))
            (unless (gethash to classes)
              (puthash to (list :name to :attrs nil :methods nil) classes))
            (push (list :from from :to to
                        :type (cond
                               ((string= rel "<|--") 'inheritance)
                               ((string= rel "*--") 'composition)
                               ((string= rel "o--") 'aggregation)
                               ((string= rel "-->") 'dependency)
                               ((string-match-p "\\.\\." rel) 'realization)
                               (t 'association))
                        :label (when label (string-trim label)))
                  relationships)))
         ;; Colon syntax: ClassName : +method() or ClassName : -attr
         ((string-match "^\\(\\S-+\\)\\s-*:\\s-*\\(.*\\)" line)
          (let ((name (match-string 1 line))
                (member-str (string-trim (match-string 2 line))))
            (unless (gethash name classes)
              (puthash name (list :name name :attrs nil :methods nil) classes))
            (let ((cls (gethash name classes)))
              (if (string-match "(.*)" member-str)
                  (plist-put cls :methods
                             (append (plist-get cls :methods) (list member-str)))
                (plist-put cls :attrs
                           (append (plist-get cls :attrs) (list member-str))))))))))
    (list :classes classes :relationships (nreverse relationships))))

(defun markdown-modern-mermaid--render-class (lines colors)
  "Render class diagram from LINES with COLORS.  Return SVG string."
  (let* ((parsed (markdown-modern-mermaid--parse-class lines))
         (classes (plist-get parsed :classes))
         (relationships (plist-get parsed :relationships))
         (bg (plist-get colors :bg))
         (fg (plist-get colors :fg))
         (surface (plist-get colors :surface))
         (border (plist-get colors :border))
         (accent (plist-get colors :accent))
         (font-size 13)
         (line-h 20)
         (pad-x 14)
         (pad-y 10)
         (grid-gap-x 50)
         (grid-gap-y 50)
         ;; Collect class names
         (class-names nil)
         (class-pos (make-hash-table :test 'equal))
         (svg-parts nil)
         (defs-parts nil)
         (total-w 0)
         (total-h 0))
    (maphash (lambda (k _v) (push k class-names)) classes)
    (setq class-names (nreverse class-names))
    ;; Compute class box sizes
    (let ((class-sizes (make-hash-table :test 'equal)))
      (dolist (name class-names)
        (let* ((cls (gethash name classes))
               (attrs (plist-get cls :attrs))
               (methods (plist-get cls :methods))
               (name-w (markdown-modern-mermaid--text-width name font-size))
               (max-w name-w)
               (section-lines 1)) ; name section
          ;; Measure attrs
          (dolist (a attrs)
            (setq max-w (max max-w (markdown-modern-mermaid--text-width a font-size)))
            (setq section-lines (1+ section-lines)))
          ;; Measure methods
          (dolist (m methods)
            (setq max-w (max max-w (markdown-modern-mermaid--text-width m font-size)))
            (setq section-lines (1+ section-lines)))
          ;; Add separators
          (when attrs (setq section-lines (1+ section-lines)))
          (when methods (setq section-lines (1+ section-lines)))
          (let ((w (+ max-w (* pad-x 2) 20))
                (h (+ (* section-lines line-h) (* pad-y 2))))
            (puthash name (list :w w :h h) class-sizes))))
      ;; Grid layout
      (let* ((cols (max 1 (ceiling (sqrt (length class-names)))))
             (x 20) (y 20)
             (col 0)
             (row-h 0))
        (dolist (name class-names)
          (let* ((size (gethash name class-sizes))
                 (w (plist-get size :w))
                 (h (plist-get size :h)))
            (puthash name (list :x x :y y :w w :h h) class-pos)
            (setq row-h (max row-h h))
            (setq total-w (max total-w (+ x w 20)))
            (setq col (1+ col))
            (setq x (+ x w grid-gap-x))
            (when (>= col cols)
              (setq col 0 x 20 y (+ y row-h grid-gap-y) row-h 0))))
        (setq total-h (+ y row-h 20))))
    ;; Markers
    (push (markdown-modern-mermaid--svg-arrow-marker "class-arrow" fg) defs-parts)
    (push (markdown-modern-mermaid--svg-arrow-marker "class-diamond" fg 'diamond) defs-parts)
    (push (markdown-modern-mermaid--svg-arrow-marker "class-circle" fg 'circle) defs-parts)
    (push (format "<marker id=\"class-inherit\" viewBox=\"0 0 10 10\" refX=\"10\" refY=\"5\" markerWidth=\"10\" markerHeight=\"10\" orient=\"auto-start-reverse\"><path d=\"M 0 0 L 10 5 L 0 10 z\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1\"/></marker>"
                  bg fg)
          defs-parts)
    ;; Background
    (push (markdown-modern-mermaid--svg-rect 0 0 total-w total-h 6 bg "none") svg-parts)
    ;; Draw relationships
    (dolist (rel relationships)
      (let* ((from-name (plist-get rel :from))
             (to-name (plist-get rel :to))
             (rel-type (plist-get rel :type))
             (label (plist-get rel :label))
             (fp (gethash from-name class-pos))
             (tp (gethash to-name class-pos)))
        (when (and fp tp)
          (let* ((fx (+ (plist-get fp :x) (/ (plist-get fp :w) 2)))
                 (fy (+ (plist-get fp :y) (plist-get fp :h)))
                 (tx (+ (plist-get tp :x) (/ (plist-get tp :w) 2)))
                 (ty (plist-get tp :y))
                 (marker (pcase rel-type
                           ('inheritance "class-inherit")
                           ('composition "class-diamond")
                           ('aggregation "class-circle")
                           (_ "class-arrow")))
                 (dash (if (memq rel-type '(dependency realization)) "5,5" nil)))
            ;; Connect from bottom of from-class to top of to-class
            ;; If they're on the same row, connect side-to-side instead
            (when (and (>= ty (plist-get fp :y))
                       (<= ty (+ (plist-get fp :y) (plist-get fp :h) 5)))
              (setq fx (+ (plist-get fp :x) (plist-get fp :w)))
              (setq fy (+ (plist-get fp :y) (/ (plist-get fp :h) 2)))
              (setq tx (plist-get tp :x))
              (setq ty (+ (plist-get tp :y) (/ (plist-get tp :h) 2))))
            (push (format "<line x1=\"%d\" y1=\"%d\" x2=\"%d\" y2=\"%d\" stroke=\"%s\" stroke-width=\"1.5\" marker-end=\"url(#%s)\"%s/>"
                          fx fy tx ty fg marker
                          (if dash (format " stroke-dasharray=\"%s\"" dash) ""))
                  svg-parts)
            (when label
              (push (markdown-modern-mermaid--svg-text (/ (+ fx tx) 2) (- (/ (+ fy ty) 2) 6)
                                                  label (1- font-size) fg)
                    svg-parts))))))
    ;; Draw class boxes
    (dolist (name class-names)
      (let* ((cls (gethash name classes))
             (pos (gethash name class-pos))
             (x (plist-get pos :x))
             (y (plist-get pos :y))
             (w (plist-get pos :w))
             (h (plist-get pos :h))
             (attrs (plist-get cls :attrs))
             (methods (plist-get cls :methods))
             (cy y))
        ;; Box background
        (push (markdown-modern-mermaid--svg-rect x y w h 4 surface border) svg-parts)
        ;; Name section
        (setq cy (+ cy pad-y line-h))
        (push (markdown-modern-mermaid--svg-text (+ x (/ w 2)) cy name font-size accent nil "bold") svg-parts)
        ;; Separator after name
        (when (or attrs methods)
          (setq cy (+ cy (/ pad-y 2)))
          (push (markdown-modern-mermaid--svg-line x cy (+ x w) cy border) svg-parts)
          (setq cy (+ cy (/ pad-y 2))))
        ;; Attrs
        (dolist (a attrs)
          (setq cy (+ cy line-h))
          (push (markdown-modern-mermaid--svg-text (+ x pad-x) cy a font-size fg "start") svg-parts))
        ;; Separator between attrs and methods
        (when (and attrs methods)
          (setq cy (+ cy (/ pad-y 2)))
          (push (markdown-modern-mermaid--svg-line x cy (+ x w) cy border) svg-parts)
          (setq cy (+ cy (/ pad-y 2))))
        ;; Methods
        (dolist (m methods)
          (setq cy (+ cy line-h))
          (push (markdown-modern-mermaid--svg-text (+ x pad-x) cy m font-size fg "start") svg-parts))))
    ;; Assemble
    (markdown-modern-mermaid--svg-wrap
     total-w total-h
     (mapconcat #'identity (nreverse defs-parts) "\n")
     (mapconcat #'identity (nreverse svg-parts) "\n"))))

;;; ============================================================
;;; ER Diagram Renderer
;;; ============================================================

(defun markdown-modern-mermaid--parse-er (lines)
  "Parse ER diagram LINES.
Returns (:entities ENTITIES :relationships RELS).
ENTITIES is hash-table name->(list :name :attrs).
RELS is list of (:from FROM :to TO :card-from CARD :card-to CARD :label LABEL)."
  (let ((entities (make-hash-table :test 'equal))
        (relationships nil)
        (current-entity nil))
    (dolist (raw-line (cdr lines))
      (let ((line (string-trim raw-line)))
        (cond
         ;; End of entity body
         ((and current-entity (string= line "}"))
          (setq current-entity nil))
         ;; Inside entity body
         (current-entity
          (when (string-match "^\\(\\S-+\\)\\s-+\\(\\S-+\\)\\(?:\\s-+\\(.*\\)\\)?" line)
            (let ((ent (gethash current-entity entities)))
              (when ent
                (plist-put ent :attrs
                           (append (plist-get ent :attrs)
                                   (list (list :type (match-string 1 line)
                                               :name (match-string 2 line)
                                               :constraint (match-string 3 line)))))))))
         ;; Entity with body
         ((string-match "^\\(\\S-+\\)\\s-*{" line)
          (let ((name (match-string 1 line)))
            (unless (gethash name entities)
              (puthash name (list :name name :attrs nil) entities))
            (setq current-entity name)))
         ;; Relationship: ENTITY ||--o{ OTHER : "label"
         ((string-match
           "^\\(\\S-+\\)\\s-+\\(||\\||o\\|}|\\|}o\\)--\\(||\\|o|\\|o{\\|{\\||{\\)\\s-+\\(\\S-+\\)\\s-*:\\s-*\\(.*\\)"
           line)
          (let ((from (match-string 1 line))
                (card-from (match-string 2 line))
                (card-to (match-string 3 line))
                (to (match-string 4 line))
                (label (string-trim (match-string 5 line) "\"" "\"")))
            (unless (gethash from entities)
              (puthash from (list :name from :attrs nil) entities))
            (unless (gethash to entities)
              (puthash to (list :name to :attrs nil) entities))
            (push (list :from from :to to
                        :card-from card-from :card-to card-to
                        :label label)
                  relationships))))))
    (list :entities entities :relationships (nreverse relationships))))

(defun markdown-modern-mermaid--er-draw-notation (ex ey dx dy card color)
  "Draw crow's foot ER notation at entity edge (EX, EY).
DX, DY is the direction away from the entity along the relationship.
CARD is the cardinality string (e.g. \"||\" \"|o\" \"}|\" \"o{\").
COLOR is the stroke color.  Returns list of SVG element strings."
  (let* ((len (sqrt (+ (* (float dx) dx) (* (float dy) dy))))
         (ux (if (> len 0) (/ (float dx) len) 1.0))
         (uy (if (> len 0) (/ (float dy) len) 0.0))
         (px (- uy))   ; perpendicular unit vector
         (py ux)
         (tk 7)        ; tick half-length
         (parts nil)
         (has-one (string-match-p "|" card))
         (has-zero (string-match-p "o" card))
         (has-many (string-match-p "[{}]" card)))
    (cond
     ;; Exactly one (||): two perpendicular ticks
     ((and has-one (not has-many) (not has-zero))
      (dolist (d '(6 12))
        (let ((cx (+ ex (* ux d))) (cy (+ ey (* uy d))))
          (push (format "<line x1=\"%.0f\" y1=\"%.0f\" x2=\"%.0f\" y2=\"%.0f\" stroke=\"%s\" stroke-width=\"2\"/>"
                        (- cx (* px tk)) (- cy (* py tk))
                        (+ cx (* px tk)) (+ cy (* py tk)) color)
                parts))))
     ;; One or many (}| |{): tick + crow's foot
     ((and has-one has-many)
      (let ((cx (+ ex (* ux 6))) (cy (+ ey (* uy 6))))
        (push (format "<line x1=\"%.0f\" y1=\"%.0f\" x2=\"%.0f\" y2=\"%.0f\" stroke=\"%s\" stroke-width=\"2\"/>"
                      (- cx (* px tk)) (- cy (* py tk))
                      (+ cx (* px tk)) (+ cy (* py tk)) color)
              parts))
      (let* ((tip-x (+ ex (* ux 20))) (tip-y (+ ey (* uy 20)))
             (base-x (+ ex (* ux 10))) (base-y (+ ey (* uy 10))))
        (push (format "<line x1=\"%.0f\" y1=\"%.0f\" x2=\"%.0f\" y2=\"%.0f\" stroke=\"%s\" stroke-width=\"1.5\"/>"
                      tip-x tip-y (+ base-x (* px tk)) (+ base-y (* py tk)) color) parts)
        (push (format "<line x1=\"%.0f\" y1=\"%.0f\" x2=\"%.0f\" y2=\"%.0f\" stroke=\"%s\" stroke-width=\"1.5\"/>"
                      tip-x tip-y base-x base-y color) parts)
        (push (format "<line x1=\"%.0f\" y1=\"%.0f\" x2=\"%.0f\" y2=\"%.0f\" stroke=\"%s\" stroke-width=\"1.5\"/>"
                      tip-x tip-y (- base-x (* px tk)) (- base-y (* py tk)) color) parts)))
     ;; Zero or one (o| |o): tick + circle
     ((and has-zero has-one)
      (let ((cx (+ ex (* ux 6))) (cy (+ ey (* uy 6))))
        (push (format "<line x1=\"%.0f\" y1=\"%.0f\" x2=\"%.0f\" y2=\"%.0f\" stroke=\"%s\" stroke-width=\"2\"/>"
                      (- cx (* px tk)) (- cy (* py tk))
                      (+ cx (* px tk)) (+ cy (* py tk)) color)
              parts))
      (let ((ox (+ ex (* ux 17))) (oy (+ ey (* uy 17))))
        (push (format "<circle cx=\"%.0f\" cy=\"%.0f\" r=\"4\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1.5\"/>"
                      ox oy "none" color) parts)))
     ;; Zero or many (}o o{): circle + crow's foot
     ((and has-zero has-many)
      (let ((ox (+ ex (* ux 8))) (oy (+ ey (* uy 8))))
        (push (format "<circle cx=\"%.0f\" cy=\"%.0f\" r=\"4\" fill=\"%s\" stroke=\"%s\" stroke-width=\"1.5\"/>"
                      ox oy "none" color) parts))
      (let* ((tip-x (+ ex (* ux 22))) (tip-y (+ ey (* uy 22)))
             (base-x (+ ex (* ux 14))) (base-y (+ ey (* uy 14))))
        (push (format "<line x1=\"%.0f\" y1=\"%.0f\" x2=\"%.0f\" y2=\"%.0f\" stroke=\"%s\" stroke-width=\"1.5\"/>"
                      tip-x tip-y (+ base-x (* px tk)) (+ base-y (* py tk)) color) parts)
        (push (format "<line x1=\"%.0f\" y1=\"%.0f\" x2=\"%.0f\" y2=\"%.0f\" stroke=\"%s\" stroke-width=\"1.5\"/>"
                      tip-x tip-y base-x base-y color) parts)
        (push (format "<line x1=\"%.0f\" y1=\"%.0f\" x2=\"%.0f\" y2=\"%.0f\" stroke=\"%s\" stroke-width=\"1.5\"/>"
                      tip-x tip-y (- base-x (* px tk)) (- base-y (* py tk)) color) parts))))
    parts))

(defun markdown-modern-mermaid--render-er (lines colors)
  "Render ER diagram from LINES with COLORS.  Return SVG string."
  (let* ((parsed (markdown-modern-mermaid--parse-er lines))
         (entities (plist-get parsed :entities))
         (relationships (plist-get parsed :relationships))
         (bg (plist-get colors :bg))
         (fg (plist-get colors :fg))
         (surface (plist-get colors :surface))
         (border (plist-get colors :border))
         (_accent (plist-get colors :accent))
         (font-size 11)
         (line-h 18)
         (pad-x 12)
         (pad-y 10)
         (grid-gap-x 120)
         (grid-gap-y 80)
         ;; Collect entity names
         (entity-names nil)
         (entity-pos (make-hash-table :test 'equal))
         (svg-parts nil)
         (defs-parts nil)
         (total-w 0)
         (total-h 0))
    (maphash (lambda (k _v) (push k entity-names)) entities)
    (setq entity-names (nreverse entity-names))
    ;; Compute entity box sizes
    (let ((entity-sizes (make-hash-table :test 'equal)))
      (dolist (name entity-names)
        (let* ((ent (gethash name entities))
               (attrs (plist-get ent :attrs))
               (name-w (markdown-modern-mermaid--text-width name font-size))
               (max-w name-w)
               (num-lines (1+ (length attrs)))) ; name + attrs
          (dolist (a attrs)
            (let ((attr-text (concat (plist-get a :type) " " (plist-get a :name))))
              (setq max-w (max max-w (markdown-modern-mermaid--text-width attr-text font-size)))))
          ;; Add separator line
          (when attrs (setq num-lines (1+ num-lines)))
          (puthash name (list :w (+ max-w (* pad-x 2) 14)
                              :h (+ (* num-lines line-h) (* pad-y 2)))
                   entity-sizes)))
      ;; Grid layout
      (let* ((cols (max 1 (ceiling (sqrt (length entity-names)))))
             (x 20) (y 20)
             (col 0)
             (row-h 0))
        (dolist (name entity-names)
          (let* ((size (gethash name entity-sizes))
                 (w (plist-get size :w))
                 (h (plist-get size :h)))
            (puthash name (list :x x :y y :w w :h h) entity-pos)
            (setq row-h (max row-h h))
            (setq total-w (max total-w (+ x w 20)))
            (setq col (1+ col))
            (setq x (+ x w grid-gap-x))
            (when (>= col cols)
              (setq col 0 x 20 y (+ y row-h grid-gap-y) row-h 0))))
        (setq total-h (+ y row-h 20))))
    ;; Background
    (push (markdown-modern-mermaid--svg-rect 0 0 total-w total-h 6 bg "none") svg-parts)
    ;; Draw relationships
    (dolist (rel relationships)
      (let* ((from-name (plist-get rel :from))
             (to-name (plist-get rel :to))
             (label (plist-get rel :label))
             (card-from (plist-get rel :card-from))
             (card-to (plist-get rel :card-to))
             (fp (gethash from-name entity-pos))
             (tp (gethash to-name entity-pos)))
        (when (and fp tp)
          (let* ((fx (+ (plist-get fp :x) (plist-get fp :w)))
                 (fy (+ (plist-get fp :y) (/ (plist-get fp :h) 2)))
                 (tx (plist-get tp :x))
                 (ty (+ (plist-get tp :y) (/ (plist-get tp :h) 2))))
            ;; If same row but to is left of from, adjust
            (when (< tx fx)
              (setq fx (plist-get fp :x))
              (setq tx (+ (plist-get tp :x) (plist-get tp :w))))
            ;; If different rows: route toward target entity, not just center
            (when (> (abs (- fy ty)) 20)
              (let* ((fp-x (plist-get fp :x)) (fp-w (plist-get fp :w))
                     (tp-x (plist-get tp :x)) (tp-w (plist-get tp :w))
                     (tp-cx (+ tp-x (/ tp-w 2)))
                     (fp-cx (+ fp-x (/ fp-w 2)))
                     (margin 10))
                ;; From-entity: bottom edge, x offset toward target center
                (setq fx (max (+ fp-x margin) (min (- (+ fp-x fp-w) margin) tp-cx)))
                (setq fy (+ (plist-get fp :y) (plist-get fp :h)))
                ;; To-entity: top edge, x offset toward source center
                (setq tx (max (+ tp-x margin) (min (- (+ tp-x tp-w) margin) fp-cx)))
                (setq ty (plist-get tp :y))))
            ;; Main relationship line (shortened to leave room for notation)
            (let* ((ldx (- tx fx)) (ldy (- ty fy))
                   (llen (sqrt (+ (* (float ldx) ldx) (* (float ldy) ldy))))
                   (lux (if (> llen 0) (/ (float ldx) llen) 1.0))
                   (luy (if (> llen 0) (/ (float ldy) llen) 0.0))
                   (inset 22))
              (push (markdown-modern-mermaid--svg-line
                     (round (+ fx (* lux inset))) (round (+ fy (* luy inset)))
                     (round (- tx (* lux inset))) (round (- ty (* luy inset)))
                     fg) svg-parts)
              ;; Crow's foot notation at from-entity
              (dolist (s (markdown-modern-mermaid--er-draw-notation
                          fx fy ldx ldy card-from fg))
                (push s svg-parts))
              ;; Crow's foot notation at to-entity
              (dolist (s (markdown-modern-mermaid--er-draw-notation
                          tx ty (- ldx) (- ldy) card-to fg))
                (push s svg-parts)))
            ;; Relationship label
            (when (and label (not (string-empty-p label)))
              (let ((lx (/ (+ fx tx) 2))
                    (ly (- (/ (+ fy ty) 2) 8)))
                (push (markdown-modern-mermaid--svg-text lx ly label (1- font-size) fg) svg-parts)))))))
    ;; Draw entity boxes
    (dolist (name entity-names)
      (let* ((ent (gethash name entities))
             (pos (gethash name entity-pos))
             (x (plist-get pos :x))
             (y (plist-get pos :y))
             (w (plist-get pos :w))
             (h (plist-get pos :h))
             (attrs (plist-get ent :attrs)))
        ;; Box background
        (push (markdown-modern-mermaid--svg-rect x y w h 4 surface border) svg-parts)
        (if (not attrs)
            ;; Simple entity: center name vertically in box
            (push (markdown-modern-mermaid--svg-text
                   (+ x (/ w 2)) (+ y (/ h 2) (/ font-size 3))
                   name font-size fg) svg-parts)
          ;; Entity with attributes: name in header, attrs below separator
          (let* ((header-h (+ pad-y line-h (/ pad-y 2)))
                 (sep-y (+ y header-h))
                 (cy (+ sep-y (/ pad-y 2))))
            ;; Name centered in header region
            (push (markdown-modern-mermaid--svg-text
                   (+ x (/ w 2)) (+ y (/ header-h 2) (/ font-size 3))
                   name font-size fg) svg-parts)
            ;; Separator line
            (push (markdown-modern-mermaid--svg-line x sep-y (+ x w) sep-y border) svg-parts)
            ;; Attributes
            (dolist (a attrs)
              (setq cy (+ cy line-h))
              (let ((attr-text (concat (plist-get a :type) " " (plist-get a :name)))
                    (constraint (plist-get a :constraint)))
                (push (markdown-modern-mermaid--svg-text (+ x pad-x) cy attr-text font-size fg "start") svg-parts)
                (when (and constraint (not (string-empty-p constraint)))
                  (push (markdown-modern-mermaid--svg-text (- (+ x w) pad-x) cy constraint
                                                      (- font-size 2) border "end")
                        svg-parts))))))))
    ;; Assemble
    (markdown-modern-mermaid--svg-wrap
     total-w total-h
     (if defs-parts (mapconcat #'identity (nreverse defs-parts) "\n") "")
     (mapconcat #'identity (nreverse svg-parts) "\n"))))

(provide 'markdown-modern-mermaid)
;;; markdown-modern-mermaid.el ends here
