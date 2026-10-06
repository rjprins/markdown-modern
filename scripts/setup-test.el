;;; setup-test.el --- Check package loading without grammars -*- lexical-binding: t; no-byte-compile: t; -*-

(require 'treesit)

;; Override library names before any grammar loads, even on a developer's
;; machine that already has them installed.  Run in a fresh Emacs process.
(setq treesit-load-name-override-list
      '((markdown "libmarkdown-modern-missing-block" "tree_sitter_markdown")
        (markdown-inline "libmarkdown-modern-missing-inline" "tree_sitter_markdown_inline")))

(dolist (language '(markdown markdown-inline))
  (when (treesit-language-available-p language)
    (error "Setup test unexpectedly found a grammar: %s" language)))

(require 'markdown-modern)
(unless (commandp 'markdown-modern-install-grammars)
  (error "The grammar installer is not available"))

(with-temp-buffer
  (let ((diagnostic (condition-case err
                        (progn (markdown-modern-mode) nil)
                      (user-error (error-message-string err)))))
    (unless (and diagnostic
                 (string-match-p "markdown-modern-install-grammars" diagnostic))
      (error "Missing-grammar activation did not report the installer: %s" diagnostic))))

(message "Package loads without grammars and reports how to install them")
