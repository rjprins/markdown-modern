;;; markdown-modern-test.el --- Test runner for markdown-modern -*- lexical-binding: t; -*-

;; Copyright (C) 2026 markdown-modern contributors

;;; Commentary:

;; Main test runner for markdown-modern.
;; Loads all test modules and provides test execution functions.
;;
;; Test organization:
;;   - markdown-modern-export-test.el    : Export/HTML conversion tests (~45 tests)
;;   - markdown-modern-commands-test.el  : Interactive command tests (~35 tests)
;;   - markdown-modern-regex-test.el     : Regex pattern tests (~40 tests)
;;   - markdown-modern-integration-test.el : End-to-end tests (~15 tests)
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

;; Load test modules
(require 'markdown-modern-export-test)
(require 'markdown-modern-commands-test)
(require 'markdown-modern-regex-test)
(require 'markdown-modern-integration-test)

;;; Test Runner Functions

(defun markdown-modern-run-all-tests ()
  "Run all markdown-modern tests interactively."
  (interactive)
  (ert-run-tests-interactively
   "^\\(export\\|cmd\\|regex\\|integration\\)/"))

(defun markdown-modern-run-export-tests ()
  "Run only export tests."
  (interactive)
  (ert-run-tests-interactively "^export/"))

(defun markdown-modern-run-command-tests ()
  "Run only command tests."
  (interactive)
  (ert-run-tests-interactively "^cmd/"))

(defun markdown-modern-run-regex-tests ()
  "Run only regex tests."
  (interactive)
  (ert-run-tests-interactively "^regex/"))

(defun markdown-modern-run-integration-tests ()
  "Run only integration tests."
  (interactive)
  (ert-run-tests-interactively "^integration/"))

;;; Batch Test Runner (for CI/Makefile)

(defun markdown-modern-run-tests-batch-and-exit ()
  "Run all tests in batch mode and exit with appropriate code."
  (let ((test-selector "^\\(export\\|cmd\\|regex\\|integration\\)/"))
    (ert-run-tests-batch-and-exit test-selector)))

;;; Test Statistics

(defun markdown-modern-test-stats ()
  "Display test statistics."
  (interactive)
  (let ((export-count 0)
        (cmd-count 0)
        (regex-count 0)
        (integration-count 0))
    (mapatoms
     (lambda (sym)
       (when (ert-test-boundp sym)
         (let ((name (symbol-name sym)))
           (cond
            ((string-prefix-p "export/" name) (cl-incf export-count))
            ((string-prefix-p "cmd/" name) (cl-incf cmd-count))
            ((string-prefix-p "regex/" name) (cl-incf regex-count))
            ((string-prefix-p "integration/" name) (cl-incf integration-count)))))))
    (message "markdown-modern test counts:
  Export tests:      %d
  Command tests:     %d
  Regex tests:       %d
  Integration tests: %d
  ─────────────────────
  Total:             %d"
             export-count cmd-count regex-count integration-count
             (+ export-count cmd-count regex-count integration-count))))

(provide 'markdown-modern-test)
;;; markdown-modern-test.el ends here
