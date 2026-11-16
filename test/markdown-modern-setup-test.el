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

(ert-deftest setup/text-width-right-margin ()
  "The right margin leaves the text width; the rest goes to the margin."
  ;; 840 px of text leave 2500 - 840 px, in 10 px frame columns.
  (should (= (markdown-modern--text-width-right-margin 2500 840 10) 166))
  ;; 84 columns of a 14 px font, the rest in 16 px columns.
  (should (= (markdown-modern--text-width-right-margin 1280 1176 16) 6))
  ;; A window narrower than the reading width gets no margin.
  (should (= (markdown-modern--text-width-right-margin 500 840 10) 0)))

(defun markdown-modern-setup-test--right-margin ()
  "Return the right margin of the selected window, 0 when unset."
  (or (cdr (window-margins)) 0))

(ert-deftest setup/text-width-sets-and-restores-right-margin ()
  "The mode keeps the reading width and gives the margin back on exit."
  (let ((markdown-modern-text-width 40)
        (markdown-modern-left-margin 4))
    (save-window-excursion
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (set-window-margins nil nil nil)
        (let ((available (window-body-width)))
          (insert "Some text\n")
          (markdown-modern-mode)
          (should (memq #'markdown-modern--update-text-width
                        window-size-change-functions))
          (should (= (markdown-modern-setup-test--right-margin)
                     (- available 44)))
          (should (= (window-body-width) 44))
          ;; A second run finds the same margin.
          (markdown-modern--update-text-width)
          (should (= (window-body-width) 44))
          (fundamental-mode)
          (should (= (markdown-modern-setup-test--right-margin) 0))
          (should-not (memq #'markdown-modern--update-text-width
                            window-size-change-functions)))))))

(ert-deftest setup/text-width-fringes-and-split ()
  "The fringes go outside the margin, and a wide margin does not block a split."
  (let ((markdown-modern-text-width 40)
        (markdown-modern-left-margin 4)
        (fringe-calls nil))
    (save-window-excursion
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (delete-other-windows)
        (set-window-margins nil nil nil)
        ;; Batch frames have no fringes to read back, so record the calls.
        (cl-letf (((symbol-function 'set-window-fringes)
                   (lambda (_window _left &optional _right outside &rest _)
                     (push outside fringe-calls))))
          (markdown-modern-mode)
          (should (equal fringe-calls '(t)))
          (should (equal (window-parameter nil 'min-margins) '(0 . 0)))
          ;; The margin leaves 44 of 80 columns, too few for two windows of
          ;; that width unless the split may shrink the margin.
          (should (split-window-right))
          (fundamental-mode)
          (should (equal (car fringe-calls) fringes-outside-margins))
          (should-not (window-parameter nil 'min-margins)))))))

;; The tests below run in an 80-column batch window with
;; `markdown-modern-setup-test--with-window'.  A batch column is one pixel.

(defmacro markdown-modern-setup-test--with-window (text-width &rest body)
  "Show a markdown-modern buffer with TEXT-WIDTH in one window, run BODY."
  (declare (indent 1))
  `(let ((markdown-modern-text-width ,text-width)
         (markdown-modern-left-margin 4))
     (save-window-excursion
       (with-temp-buffer
         (switch-to-buffer (current-buffer))
         (delete-other-windows)
         (set-window-margins nil nil nil)
         (set-window-parameter nil 'min-margins nil)
         (insert "Some text\n")
         (markdown-modern-mode)
         ,@body))))

(ert-deftest setup/text-width-ignores-left-margin ()
  "A left margin from another package does not narrow the text."
  (markdown-modern-setup-test--with-window 40
    (set-window-margins nil 2 (cdr (window-margins)))
    (markdown-modern--update-text-width)
    (should (equal (window-margins) '(2 . 34)))
    (should (= (window-body-width) 44))))

(ert-deftest setup/text-width-counts-line-numbers ()
  "Line numbers come on top of the reading width."
  (markdown-modern-setup-test--with-window 40
    (setq-local display-line-numbers t)
    (cl-letf (((symbol-function 'line-number-display-width) (lambda (&rest _) 5)))
      (markdown-modern--update-text-width))
    (should (= (window-body-width) 49))))

(ert-deftest setup/text-width-settles-after-split ()
  "After a split, one update gives each window its final margin."
  (markdown-modern-setup-test--with-window 20
    (should (= (window-body-width) 24))
    (let ((new (split-window-right)))
      ;; Both halves still carry the old margin, wider than the window.
      (dolist (win (list (selected-window) new))
        (markdown-modern--update-text-width win)
        (should (= (window-body-width win) 24))))))

(ert-deftest setup/text-width-off-while-truncating ()
  "Truncated lines scroll at the full window width."
  (markdown-modern-setup-test--with-window 40
    (should (> (markdown-modern-setup-test--right-margin) 0))
    (markdown-modern-toggle-truncate-lines)
    (should (= (markdown-modern-setup-test--right-margin) 0))
    (markdown-modern-toggle-truncate-lines)
    (should (= (window-body-width) 44))))

(ert-deftest setup/text-width-leaves-foreign-margin ()
  "A right margin set by another package stays."
  (markdown-modern-setup-test--with-window 40
    (set-window-margins nil nil 7)
    (markdown-modern--update-text-width)
    (should (= (markdown-modern-setup-test--right-margin) 7))
    (fundamental-mode)
    (should (= (markdown-modern-setup-test--right-margin) 7))))

(ert-deftest setup/split-advice-counts-reading-margin ()
  "A markdown-modern window splits side by side unless the advice is off."
  (markdown-modern-setup-test--with-window 40
    (let ((split-width-threshold 60))
      ;; The text area is 44 columns; without the margin it would be 80.
      (should (= (window-body-width) 44))
      (should (window-splittable-p (selected-window) t))
      (should (= (window-body-width) 44))
      (let ((markdown-modern-advise-window-splittable-p nil))
        (should-not (window-splittable-p (selected-window) t))))))

(ert-deftest setup/split-advice-option-removes-advice ()
  "Turning the option off removes the advice."
  (unwind-protect
      (progn
        (advice-add 'window-splittable-p :around
                    #'markdown-modern--window-splittable-p)
        (customize-set-variable 'markdown-modern-advise-window-splittable-p nil)
        (should-not (advice-member-p #'markdown-modern--window-splittable-p
                                     'window-splittable-p)))
    (customize-set-variable 'markdown-modern-advise-window-splittable-p t)))

(ert-deftest setup/text-width-narrow-window-keeps-fringes ()
  "A window too narrow for a margin keeps its fringes as they are."
  (let ((fringe-calls nil))
    (cl-letf (((symbol-function 'set-window-fringes)
               (lambda (&rest args) (push args fringe-calls))))
      (markdown-modern-setup-test--with-window 100
        (should (= (markdown-modern-setup-test--right-margin) 0))
        (should-not fringe-calls)
        (should-not (window-parameter nil 'min-margins))))))

(ert-deftest setup/text-width-nil-or-other-manager-leaves-margins ()
  "No margin without a reading width or under another width mode."
  (save-window-excursion
    (with-temp-buffer
      (switch-to-buffer (current-buffer))
      (set-window-margins nil nil nil)
      (let ((markdown-modern-text-width nil))
        (markdown-modern-mode)
        (should (= (markdown-modern-setup-test--right-margin) 0)))
      (let ((markdown-modern-text-width 40))
        (setq-local visual-fill-column-mode t)
        (markdown-modern--update-text-width)
        (should (= (markdown-modern-setup-test--right-margin) 0))))))

(provide 'markdown-modern-setup-test)
;;; markdown-modern-setup-test.el ends here
