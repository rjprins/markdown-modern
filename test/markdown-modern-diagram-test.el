;;; markdown-modern-diagram-test.el --- Diagram viewer tests -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:

;; Source and mouse entry points run in batch.  Viewer interaction tests also
;; exercise the real SVG backend when run in graphical Emacs.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'markdown-modern)

(ert-deftest render/diagram-focus-revealed-source ()
  "Focus reads current source, including edits and alternate fences."
  (dolist (fence '("```mermaid" "~~~~ MERMAID"))
    (with-temp-buffer
      (insert fence "\nflowchart LR\nA --> B\n"
              (if (string-prefix-p "~" fence) "~~~~" "```") "\n")
      (markdown-modern-ts--init)
      (goto-char (point-min))
      (search-forward "B")
      (replace-match "Updated")
      (let ((text (buffer-string))
            (position (point))
            captured)
        (cl-letf (((symbol-function 'display-images-p) (lambda (&rest _) t))
                  ((symbol-function 'image-type-available-p) (lambda (_) t))
                  ((symbol-function 'markdown-modern-diagram--open)
                   (lambda (svg _name) (setq captured svg))))
          (markdown-modern-focus-diagram))
        (should (string-match-p ">Updated</text>" captured))
        (should (equal text (buffer-string)))
        (should (= position (point)))))))

(ert-deftest render/diagram-focus-errors-preserve-source ()
  "Missing diagrams and unsupported syntax fail without changing buffers."
  (dolist (text '("Plain text\n" "```python\nprint(1)\n```\n"
                  "```mermaid\npie\n\"Cats\" : 5\n```\n"))
    (with-temp-buffer
      (insert text)
      (markdown-modern-ts--init)
      (goto-char (point-min))
      (should-error (markdown-modern-diagram--svg-at-point) :type 'user-error)
      (should (equal (buffer-string) text))))
  (cl-letf (((symbol-function 'display-images-p) (lambda (&rest _) nil)))
    (should-error (markdown-modern-focus-diagram) :type 'user-error)))

(ert-deftest render/diagram-click-other-window ()
  "A click focuses the diagram in its own window without moving source point."
  (save-window-excursion
    (let ((source (generate-new-buffer " *diagram-click*")))
      (unwind-protect
          (let ((other (split-window-right)) captured)
            (with-current-buffer source
              (insert "Intro\n\n```mermaid\nflowchart TD\nClicked --> Diagram\n```\n")
              (markdown-modern-ts--init)
              (goto-char (point-min)))
            (set-window-buffer other source)
            (cl-letf (((symbol-function 'display-images-p) (lambda (&rest _) t))
                      ((symbol-function 'image-type-available-p) (lambda (_) t))
                      ((symbol-function 'markdown-modern-diagram--open)
                       (lambda (svg _name) (setq captured svg))))
              (markdown-modern-focus-diagram `(mouse-1 (,other 30 (20 . 20) 0))))
            (should (eq (selected-window) other))
            (should (string-match-p ">Clicked</text>" captured))
            (should (= (point) (point-min))))
        (kill-buffer source)))))

(ert-deftest render/diagram-click-bindings-and-overlay-reuse ()
  "Diagram mouse bindings are removed when an overlay is reused for prose."
  (with-temp-buffer
    (insert "```mermaid\nflowchart LR\nA --> B\n```\n")
    (markdown-modern-render--init)
    (cl-letf (((symbol-function 'create-image)
               (lambda (&rest _) '(image :type svg :data "<svg/>"))))
      (markdown-modern-render--display-mermaid-svg 1 (point-max) "<svg/>"))
    (let ((overlay (car markdown-modern-render--overlays)))
      (should (eq (lookup-key (overlay-get overlay 'keymap) [mouse-1])
                  #'markdown-modern-focus-diagram))
      (should (eq (lookup-key (overlay-get overlay 'keymap) [down-mouse-1]) #'ignore))
      (markdown-modern-render--release-overlay overlay)
      (let ((reused (markdown-modern-render--get-overlay 1 2)))
        (should (eq reused overlay))
        (should-not (overlay-get reused 'keymap))
        (should-not (overlay-get reused 'help-echo))))))

(defconst markdown-modern-diagram-test--svg
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"2400\" height=\"1800\" viewBox=\"0 0 2400 1800\"><rect width=\"2400\" height=\"1800\" fill=\"#edf2f7\"/><text x=\"100\" y=\"120\" font-size=\"48\">Large diagram</text><text x=\"1900\" y=\"1700\" font-size=\"48\">Far corner</text></svg>"
  "An SVG larger than a normal window in both dimensions.")

(ert-deftest render/diagram-viewer-controls-and-return ()
  "Real SVG zoom, pan, fit and quit preserve the original document and point."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (with-temp-buffer
      (insert "Original document\n")
      (switch-to-buffer (current-buffer))
      (let ((source (current-buffer)) (position (point)) viewer)
        (unwind-protect
            (progn
              (markdown-modern-diagram--open markdown-modern-diagram-test--svg "test")
              (setq viewer (current-buffer))
              (should (derived-mode-p 'markdown-modern-diagram-mode))
              (should buffer-read-only)
              (should-not (buffer-modified-p))
              (let ((size (image-display-size (image-get-display-property) t)))
                (should (<= (car size) (window-body-width nil t)))
                (should (<= (cdr size) (window-body-height nil t)))
                (markdown-modern-diagram-zoom-in)
                (should (> (car (image-display-size (image-get-display-property) t)) (car size)))
                (markdown-modern-diagram-zoom-out)
                (should (< (abs (- (car (image-display-size (image-get-display-property) t))
                                   (car size))) 3)))
              (markdown-modern-diagram-actual-size)
              (should (equal (image-size (image-get-display-property) t) '(2400 . 1800)))
              (markdown-modern-diagram--pan-to 100000 100000)
              (should (> (window-hscroll) 0))
              (should (> (window-vscroll nil t) 0))
              (should (<= (* (window-hscroll) (frame-char-width))
                          (+ (- 2400 (window-body-width nil t)) (frame-char-width))))
              (should (<= (window-vscroll nil t) (- 1800 (window-body-height nil t))))
              (markdown-modern-diagram-fit)
              (should (= (window-hscroll) 0))
              (should (= (window-vscroll nil t) 0))
              (markdown-modern-diagram-quit)
              (should-not (buffer-live-p viewer))
              (should (eq (current-buffer) source))
              (should (= (point) position))
              (should (equal (buffer-string) "Original document\n")))
          (when (buffer-live-p viewer) (kill-buffer viewer)))))))

(ert-deftest render/diagram-viewer-drag ()
  "Dragging moves the viewport, and interrupted drags preserve keyboard input."
  (skip-unless (display-graphic-p))
  (save-window-excursion
    (let (viewer)
      (unwind-protect
          (progn
            (markdown-modern-diagram--open markdown-modern-diagram-test--svg "drag")
            (setq viewer (current-buffer))
            (markdown-modern-diagram-actual-size)
            (let* ((window (selected-window))
                   (events `((mouse-movement (,window 1 (20 . 20) 0)) ?f))
                   (unread-command-events nil))
              (cl-letf (((symbol-function 'read-event) (lambda (&rest _) (pop events))))
                (markdown-modern-diagram-drag `(down-mouse-1 (,window 1 (120 . 120) 0))))
              (should (> (window-hscroll) 0))
              (should (= (window-vscroll nil t) 100))
              (should (equal unread-command-events '(?f)))))
        (when (buffer-live-p viewer) (kill-buffer viewer))))))

(ert-deftest render/diagram-viewer-failure-cleans-up ()
  "Failed viewer initialization returns to the source and removes its buffer."
  (save-window-excursion
    (switch-to-buffer (current-buffer))
    (let ((source (current-buffer)) (buffers (buffer-list)))
      (cl-letf (((symbol-function 'markdown-modern-diagram-mode)
                 (lambda () (error "SVG display failed"))))
        (should-error (markdown-modern-diagram--open "<svg/>" "failure")))
      (should (eq (current-buffer) source))
      (should-not (cl-set-difference (buffer-list) buffers)))))

(provide 'markdown-modern-diagram-test)
;;; markdown-modern-diagram-test.el ends here
