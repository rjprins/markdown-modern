;;; package.el --- Build the package tarball -*- lexical-binding: t; -*-

(require 'package)

(let* ((root default-directory)
       (desc (with-temp-buffer
               (insert-file-contents "lisp/markdown-modern.el")
               (package-buffer-info)))
       (name (symbol-name (package-desc-name desc)))
       (version (package-version-join (package-desc-version desc)))
       (dirname (concat name "-" version))
       (staging (make-temp-file "markdown-modern-package-" t))
       (package-dir (expand-file-name dirname staging))
       (archive (expand-file-name (concat "dist/" dirname ".tar") root)))
  (unwind-protect
      (progn
        (make-directory package-dir)
        (make-directory (file-name-directory archive) t)
        (dolist (file (directory-files "lisp" t "\\.el\\'"))
          (copy-file file (expand-file-name (file-name-nondirectory file)
                                           package-dir)))
        (dolist (file '("README.md" "CHANGELOG.md" "LICENSE"))
          (copy-file file (expand-file-name file package-dir)))
        (copy-directory "images" (expand-file-name "images" package-dir))
        (with-temp-file (expand-file-name (concat name "-pkg.el") package-dir)
          (insert ";;; -*- no-byte-compile: t; lexical-binding: t -*-\n")
          (prin1 `(define-package ,name ,version ,(package-desc-summary desc)
                    ',(mapcar (lambda (dep)
                                (list (car dep) (package-version-join (cadr dep))))
                              (package-desc-reqs desc)))
                 (current-buffer))
          (insert "\n"))
        (unless (zerop (call-process "tar" nil t nil "-cf" archive
                                    "-C" staging dirname))
          (error "Could not build %s" archive))
        (message "Package created: %s" archive))
    (delete-directory staging t)))
