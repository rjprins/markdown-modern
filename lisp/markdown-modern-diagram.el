;;; markdown-modern-diagram.el --- Focused diagram viewer -*- lexical-binding: t; -*-

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

;; View a Mermaid SVG in a temporary Image mode buffer, with zoom, pan,
;; fit and return controls.  The Markdown source and inline image are untouched.

;;; Code:

(require 'image-mode)
(require 'markdown-modern-render)

(declare-function markdown-modern--fenced-code-block-content-at "markdown-modern")

(defvar markdown-modern-diagram-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "+") #'markdown-modern-diagram-zoom-in)
    (define-key map (kbd "=") #'markdown-modern-diagram-zoom-in)
    (define-key map (kbd "-") #'markdown-modern-diagram-zoom-out)
    (define-key map (kbd "f") #'markdown-modern-diagram-fit)
    (define-key map (kbd "0") #'markdown-modern-diagram-actual-size)
    (define-key map (kbd "q") #'markdown-modern-diagram-quit)
    (define-key map [down-mouse-1] #'markdown-modern-diagram-drag)
    (define-key map [mouse-1] #'ignore)
    (define-key map [drag-mouse-1] #'ignore)
    (dolist (key '([C-wheel-up] [C-mouse-4]))
      (define-key map key #'markdown-modern-diagram-zoom-in))
    (dolist (key '([C-wheel-down] [C-mouse-5]))
      (define-key map key #'markdown-modern-diagram-zoom-out))
    map)
  "Keymap for `markdown-modern-diagram-mode'.")

(define-derived-mode markdown-modern-diagram-mode image-mode "Diagram"
  "View a diagram with zoom and panning.
Drag with the left mouse button, or use arrow keys to pan.  Use + and - to zoom,
f to fit the window, 0 for actual size, and q to return to Markdown."
  (setq-local buffer-read-only t)
  (setq-local header-line-format
              " Diagram   + / -: zoom   arrows / drag: pan   f: fit   0: 100%   q: return")
  (setq-local display-line-numbers nil))

(defun markdown-modern-diagram--pan-to (x y)
  "Pan to pixel offsets X and Y, clamped to the displayed image."
  (let* ((size (image-display-size (image-get-display-property) t))
         (max-x (max 0 (- (car size) (window-body-width nil t))))
         (max-y (max 0 (- (cdr size) (window-body-height nil t)))))
    (image-set-window-hscroll
     (ceiling (/ (max 0 (min x max-x)) (float (frame-char-width)))))
    (image-set-window-vscroll (round (max 0 (min y max-y))))))

(defun markdown-modern-diagram--zoom (factor event)
  "Zoom by FACTOR around the viewport center, selecting EVENT's window."
  (when event
    (select-window (posn-window (event-start event))))
  (let* ((image (image-get-display-property))
         (size (image-display-size image t))
         (original (create-image (plist-get (cdr image) :data) 'svg t :scale 1))
         (width (car (image-size original t)))
         (half-width (/ (window-body-width nil t) 2.0))
         (half-height (/ (window-body-height nil t) 2.0))
         (x (+ (* (window-hscroll) (frame-char-width)) half-width))
         (y (+ (window-vscroll nil t) half-height)))
    (image-transform-set-scale (* factor (/ (float (car size)) width)))
    (markdown-modern-diagram--pan-to
     (- (* x factor) half-width) (- (* y factor) half-height))))

(defun markdown-modern-diagram-zoom-in (&optional event)
  "Zoom into the diagram, optionally in mouse EVENT's window."
  (interactive (list (when (mouse-event-p last-input-event) last-input-event)))
  (markdown-modern-diagram--zoom 1.2 event))

(defun markdown-modern-diagram-zoom-out (&optional event)
  "Zoom out of the diagram, optionally in mouse EVENT's window."
  (interactive (list (when (mouse-event-p last-input-event) last-input-event)))
  (markdown-modern-diagram--zoom (/ 1.0 1.2) event))

(defun markdown-modern-diagram-fit ()
  "Fit the whole diagram in the window and reset panning."
  (interactive)
  (image-transform-fit-both)
  (markdown-modern-diagram--pan-to 0 0))

(defun markdown-modern-diagram-actual-size ()
  "Show the diagram at its original size and reset panning."
  (interactive)
  (image-transform-reset-to-original)
  (markdown-modern-diagram--pan-to 0 0))

(defun markdown-modern-diagram-drag (event)
  "Pan the diagram by dragging from mouse EVENT."
  (interactive "e")
  (let* ((start (event-start event))
         (window (posn-window start))
         (origin (posn-x-y start)))
    (select-window window)
    (let ((x (* (window-hscroll) (frame-char-width)))
          (y (window-vscroll nil t))
          next)
      (track-mouse
        (while (progn
                 (setq next (read-event))
                 (mouse-movement-p next))
          (let* ((position (event-start next))
                 (xy (posn-x-y position)))
            (when (eq (posn-window position) window)
              (markdown-modern-diagram--pan-to
               (+ x (- (car origin) (car xy)))
               (+ y (- (cdr origin) (cdr xy))))))))
      ;; Do not swallow a keyboard command that interrupted the drag.
      (unless (memq (car-safe next) '(mouse-1 drag-mouse-1))
        (setq unread-command-events (cons next unread-command-events))))))

(defun markdown-modern-diagram-quit ()
  "Close the temporary viewer and return to the previous buffer."
  (interactive)
  (quit-window t))

(defun markdown-modern-diagram--svg-at-point ()
  "Return the rendered Mermaid SVG at point, including from revealed source."
  (let* ((info (markdown-modern--fenced-code-block-content-at (point)))
         (bounds (and info
                      (markdown-modern-render--mermaid-bounds
                       (plist-get info :block-start) (plist-get info :block-end)))))
    (unless bounds
      (user-error "No Mermaid diagram at point"))
    (or (markdown-modern-mermaid-render
         (buffer-substring-no-properties (nth 1 bounds) (nth 2 bounds)))
        (user-error "This Mermaid diagram cannot be rendered; its source is unchanged"))))

(defun markdown-modern-diagram--open (svg name)
  "Open SVG in a temporary viewer labeled with source buffer NAME."
  (let ((buffer (generate-new-buffer (format "*Diagram: %s*" name)))
        ready)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (insert svg)
            (goto-char (point-min))
            (set-buffer-modified-p nil))
          (pop-to-buffer-same-window buffer)
          (let ((image-auto-resize t))
            (markdown-modern-diagram-mode))
          ;; Account for the viewer header when fitting the initial image.
          (markdown-modern-diagram-fit)
          (setq ready t))
      (unless ready
        (when (eq (window-buffer) buffer)
          (quit-window t))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

;;;###autoload
(defun markdown-modern-focus-diagram (&optional event)
  "Focus the Mermaid diagram at point or mouse EVENT in a zoomable viewer.
Works on rendered diagrams and anywhere in a Mermaid source fence."
  (interactive (list (when (mouse-event-p last-input-event) last-input-event)))
  (unless (and (display-images-p) (image-type-available-p 'svg))
    (user-error "Diagram viewing requires graphical Emacs with SVG support"))
  (when event
    (select-window (posn-window (event-start event))))
  (let ((svg (save-excursion
               (when event
                 (goto-char (posn-point (event-start event))))
               (markdown-modern-diagram--svg-at-point)))
        (name (buffer-name)))
    (markdown-modern-diagram--open svg name)))

(provide 'markdown-modern-diagram)
;;; markdown-modern-diagram.el ends here
