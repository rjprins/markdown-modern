;;; lint.el --- Run package-lint in an isolated directory -*- lexical-binding: t; no-byte-compile: t; -*-

(setq user-emacs-directory (expand-file-name ".build/emacs/")
      custom-file (expand-file-name "custom.el" user-emacs-directory))
(require 'package)

(setq package-user-dir (expand-file-name ".build/elpa")
      package-archives '(("gnu" . "https://elpa.gnu.org/packages/")
                         ("melpa" . "https://melpa.org/packages/")))
(package-initialize)
(unless (package-installed-p 'package-lint)
  (package-refresh-contents)
  (package-install 'package-lint))
(require 'package-lint)
(setq package-lint-main-file (expand-file-name "lisp/markdown-modern.el"))
(package-lint-batch-and-exit)
