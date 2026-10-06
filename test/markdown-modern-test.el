;;; markdown-modern-test.el --- Test runner for markdown-modern -*- lexical-binding: t; no-byte-compile: t; -*-

;; Copyright (C) 2026 markdown-modern contributors

;;; Commentary:

;; Main test runner for markdown-modern.
;; Loads all test modules and provides test execution functions.
;;
;; Covers commands, export, integration, jit-lock, LaTeX conversion,
;; rendering, parser setup and tree-sitter parsing.
;;
;; Run tests:
;;   M-x markdown-modern-run-all-tests
;;   M-x ert RET t RET
;;   make test

;;; Code:

(require 'ert)

;; Add test directory to load path
(let ((test-dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path test-dir)
  (add-to-list 'load-path (expand-file-name "../lisp" test-dir)))

;; Load markdown-modern
(require 'markdown-modern)
(markdown-modern-ts--ensure-grammar)

;; Load test modules
(require 'markdown-modern-export-test)
(require 'markdown-modern-commands-test)
(require 'markdown-modern-setup-test)
(require 'markdown-modern-integration-test)
(require 'markdown-modern-jit-test)
(require 'markdown-modern-latex-test)
(require 'markdown-modern-render-test)
(require 'markdown-modern-ts-test)

(defconst markdown-modern-test-selector
  "^\\(export\\|cmd\\|setup\\|integration\\|jit\\|latex\\|render\\|ts\\)/"
  "ERT selector for all markdown-modern test suites.")

;;; Test Runner Functions

(defun markdown-modern-run-all-tests ()
  "Run all markdown-modern tests interactively."
  (interactive)
  (ert-run-tests-interactively markdown-modern-test-selector))

(defun markdown-modern-run-export-tests ()
  "Run only export tests."
  (interactive)
  (ert-run-tests-interactively "^export/"))

(defun markdown-modern-run-command-tests ()
  "Run only command tests."
  (interactive)
  (ert-run-tests-interactively "^cmd/"))

(defun markdown-modern-run-integration-tests ()
  "Run only integration tests."
  (interactive)
  (ert-run-tests-interactively "^integration/"))

;;; Batch Test Runner (for CI/Makefile)

(defun markdown-modern-run-tests-batch-and-exit ()
  "Run all tests in batch mode and exit with appropriate code."
  (ert-run-tests-batch-and-exit markdown-modern-test-selector))

;;; Test Statistics

(defun markdown-modern-test-stats ()
  "Display test statistics."
  (interactive)
  (let ((tests (ert-select-tests markdown-modern-test-selector t)))
    (dolist (suite '(cmd export integration jit latex setup render ts))
      (message "%s: %d" suite
               (length (ert-select-tests (format "^%s/" suite) t))))
    (message "Total test count: %d" (length tests))))

(provide 'markdown-modern-test)
;;; markdown-modern-test.el ends here
