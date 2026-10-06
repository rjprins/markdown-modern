;;; markdown-modern-setup-test.el --- Parser setup tests -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:

;; Tests the required parser and the grammar installation workflow.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'markdown-modern)

(ert-deftest setup/mode-uses-tree-sitter-by-default ()
  "Mode activation creates both parsers without an opt-in setting."
  (with-temp-buffer
    (insert "plain_no_code_x and **bold**\n")
    (markdown-modern-mode)
    (should (treesit-parser-p markdown-modern-ts--parser))
    (should (treesit-parser-p markdown-modern-ts--inline-parser))
    (let ((types (mapcar #'markdown-modern-node-type
                        (markdown-modern-ts--inline-elements-in
                         (point-min) (point-max)))))
      (should (memq 'strong types))
      (should-not (memq 'emphasis types)))))

(ert-deftest setup/missing-inline-grammar-reports-install-command ()
  "Missing grammars fail before rendering setup and identify the installer."
  (with-temp-buffer
    (insert "Some text\n")
    (put-text-property 1 5 'face 'bold)
    (cl-letf (((symbol-function 'treesit-language-available-p)
               (lambda (language &rest _) (eq language 'markdown))))
      (let ((err (should-error (markdown-modern-mode) :type 'user-error)))
        (should (string-match-p "markdown-inline" (error-message-string err)))
        (should (string-match-p "markdown-modern-install-grammars"
                                (error-message-string err)))))
    (should (eq (get-text-property 1 'face) 'bold))
    (should-not markdown-modern-ts--parser)
    (should-not (memq #'markdown-modern--jit-fontify jit-lock-functions))))

(ert-deftest setup/no-tree-sitter-reports-required-build ()
  "An Emacs build without Tree-sitter gives an actionable error."
  (with-temp-buffer
    (cl-letf (((symbol-function 'treesit-available-p) (lambda () nil)))
      (let ((err (should-error (markdown-modern-mode) :type 'user-error)))
        (should (string-match-p "Emacs.*Tree-sitter" (error-message-string err)))))
    (should-not markdown-modern-ts--parser)))

(ert-deftest setup/install-missing-grammars-only ()
  "The installer preserves an existing grammar and installs the missing one."
  (let ((available '(markdown)) installed)
    (cl-letf (((symbol-function 'treesit-language-available-p)
               (lambda (language &rest _) (memq language available)))
              ((symbol-function 'treesit-install-language-grammar)
               (lambda (language &rest _)
                 (push language installed)
                 (push language available))))
      (markdown-modern-install-grammars)
      (should (equal installed '(markdown-inline)))
      (should (memq 'markdown available))
      (should (memq 'markdown-inline available)))))

(ert-deftest setup/installation-error-keeps-diagnostic ()
  "A grammar build error reaches the user instead of selecting another parser."
  (cl-letf (((symbol-function 'treesit-language-available-p)
             (lambda (&rest _) nil))
            ((symbol-function 'treesit-install-language-grammar)
             (lambda (&rest _) (error "C compiler not found"))))
    (let ((err (should-error (markdown-modern-install-grammars) :type 'user-error)))
      (should (string-match-p "C compiler not found" (error-message-string err))))))

(ert-deftest setup/parser-init-error-cleans-up ()
  "Failure to create the inline parser leaves no partial parser setup."
  (with-temp-buffer
    (let ((create-parser (symbol-function 'treesit-parser-create)))
      (cl-letf (((symbol-function 'treesit-parser-create)
                 (lambda (language &rest args)
                   (if (eq language 'markdown-inline)
                       (error "Inline parser failed")
                     (apply create-parser language args)))))
        (should-error (markdown-modern-ts--init)))
      (should-not markdown-modern-ts--parser)
      (should-not markdown-modern-ts--inline-parser)
      (should-not (treesit-parser-list)))))

(ert-deftest setup/parser-init-preserves-other-parsers ()
  "A failed initialization must not delete another package's parser."
  (with-temp-buffer
    (let ((existing (treesit-parser-create 'markdown))
          (create-parser (symbol-function 'treesit-parser-create)))
      (cl-letf (((symbol-function 'treesit-parser-create)
                 (lambda (language &rest args)
                   (if (eq language 'markdown-inline)
                       (error "Inline parser failed")
                     (apply create-parser language args)))))
        (should-error (markdown-modern-ts--init)))
      (should (memq existing (treesit-parser-list))))))

(ert-deftest setup/parser-lifetime ()
  "Repeated initialization and cleanup affect only our own parsers."
  (with-temp-buffer
    (let ((existing (treesit-parser-create 'markdown)))
      (markdown-modern-ts--init)
      (should-not (eq existing markdown-modern-ts--parser))
      (markdown-modern-ts--init)
      (should (= 3 (length (treesit-parser-list))))
      (markdown-modern-ts--cleanup)
      (should (equal (treesit-parser-list) (list existing)))
      (should-not markdown-modern-ts--parser)
      (should-not markdown-modern-ts--inline-parser))))

(provide 'markdown-modern-setup-test)
;;; markdown-modern-setup-test.el ends here
