;;; screenshot.el --- Render the README screenshot -*- lexical-binding: t; no-byte-compile: t; -*-

(unless (display-graphic-p)
  (error "Run this script in a graphical Emacs session"))

(defconst markdown-modern-screenshot-output
  (expand-file-name "images/screenshot.png"))

(require 'markdown-modern)
(load-theme 'modus-operandi t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(set-face-attribute 'default nil :family "JetBrains Mono" :height 125)
(set-face-attribute 'fixed-pitch nil :family "JetBrains Mono" :height 1.0)
(set-face-attribute 'variable-pitch nil :family "Noto Sans" :height 1.0)
(set-frame-size (selected-frame) 1100 1100 t)
(setq inhibit-startup-screen t
      enable-local-variables nil
      enable-local-eval nil)
(find-file "images/demo.md")
(markdown-modern-mode)
(goto-char (point-min))
(forward-line 2)
(markdown-modern--jit-fontify (point-min) (point-max))
(run-at-time
 2 nil
 (lambda ()
   (redisplay t)
   (let ((coding-system-for-write 'binary))
     (write-region (x-export-frames nil 'png) nil markdown-modern-screenshot-output
                   nil 'silent))
   (kill-emacs)))
