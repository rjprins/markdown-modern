;;; install-test.el --- Check a fresh package installation -*- lexical-binding: t; -*-

(require 'package)

(let* ((method (pop command-line-args-left))
       (source (pop command-line-args-left))
       (install-dir (make-temp-file "markdown-modern-install-" t))
       (user-emacs-directory (file-name-as-directory install-dir))
       (package-user-dir (expand-file-name "elpa" install-dir))
       (custom-file (expand-file-name "custom.el" install-dir))
       (package-directory-list nil))
  (unwind-protect
      (progn
        (package-initialize)
        (pcase method
          ("tar" (package-install-file (expand-file-name source)))
          ("vc"
           (require 'package-vc)
           (package-vc-install `(markdown-modern :url ,source :lisp-dir "lisp")))
          (_ (error "Unknown installation method: %s" method)))
        (require 'markdown-modern)
        (with-temp-buffer
          (insert "# Fresh install\n\nSome **bold** text.\n")
          (let ((source-text (buffer-string)))
            (markdown-modern-mode)
            (markdown-modern--jit-fontify (point-min) (point-max))
            (unless (and (eq major-mode 'markdown-modern-mode)
                         (overlays-in (point-min) (point-max))
                         (equal source-text (buffer-substring-no-properties
                                             (point-min) (point-max))))
              (error "Fresh installation did not render Markdown"))))
        (message "Fresh %s installation passed" method))
    (delete-directory install-dir t)))
