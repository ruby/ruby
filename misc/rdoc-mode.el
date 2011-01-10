;;
;; rdoc-mode.el
;; Major mode for RDoc editing
;;

;; Created: Fri Sep 18 09:04:49 JST 2009

;; License: Ruby's

(require 'derived)
(define-derived-mode rdoc-mode text-mode "RDoc"
  "Major mode for RD editing.
\\{rdoc-mode-map}"
  (make-local-variable 'paragraph-separate)
  (setq paragraph-separate "^\\(=+\\|\\*+\\)\\s \\|^\\s *$")
  (make-local-variable 'paragraph-start)
  (setq paragraph-start paragraph-separate)
  (make-local-variable 'require-final-newline)
  (setq require-final-newline t)
  (make-local-variable 'font-lock-defaults)
  (setq font-lock-defaults '((rdoc-font-lock-keywords) t nil))
  (make-local-variable 'font-lock-keywords)
  (setq font-lock-keywords rdoc-font-lock-keywords)
  (make-local-variable 'outline-regexp)
  (setq outline-regexp "^\\(=+\\)\\s ")
  (outline-minor-mode t)
  (setq show-trailing-whitespace t)
  (rdoc-setup-keys)
  (setq indent-tabs-mode nil)
  (run-hooks 'rdoc-mode-hook)
  )

(defun rdoc-fill-paragraph (&rest args)
  "Fills paragraph, except for cited region"
  (interactive (progn
		 (barf-if-buffer-read-only)
		 (list (if current-prefix-arg 'full))))
  (save-excursion
    (beginning-of-line)
    (unless (looking-at "^ +")
      (apply 'fill-paragraph args))))

(defun rdoc-setup-keys ()
  (interactive)
  (define-key rdoc-mode-map "\M-q" 'rdoc-fill-paragraph)
  )

(defvar rdoc-heading1-face 'font-lock-keywordoc-face)
(defvar rdoc-heading2-face 'font-lock-type-face)
(defvar rdoc-heading3-face 'font-lock-variable-name-face)
(defvar rdoc-heading4-face 'font-lock-comment-face)
(defvar rdoc-bold-face 'font-lock-function-name-face)
(defvar rdoc-emphasis-face 'font-lock-function-name-face)
(defvar rdoc-code-face 'font-lock-keyword-face)
(defvar rdoc-description-face 'font-lock-constant-face)

(defvar rdoc-font-lock-keywords
  (list
   (list "^= .*$"
	 0 rdoc-heading1-face)
   (list "^== .*$"
	 0 rdoc-heading2-face)
   (list "^=== .*$"
	 0 rdoc-heading3-face)
   (list "^=====* .*$"
	 0 rdoc-heading4-face)
   (list "\\(^\\|\\s \\)\\(\\*\\(\\sw\\|[-_:]\\)+\\*\\)\\($\\|\\s \\)"
	 2 rdoc-bold-face)		; *bold*
   (list "\\(^\\|\\s \\)\\(_\\(\\sw\\|[-_:]\\)+_\\)\\($\\|\\s \\)"
	 2 rdoc-emphasis-face)		; _emphasis_
   (list "\\(^\\|\\s \\)\\(\\+\\(\\sw\\|[-_:]\\)+\\+\\)\\($\\|\\s \\)"
	 2 rdoc-code-face)		; +code+
   (list "<em>[^<>]*</em>" 0 rdoc-emphasis-face)
   (list "<i>[^<>]*</i>" 0 rdoc-emphasis-face)
   (list "<b>[^<>]*</b>" 0 rdoc-bold-face)
   (list "<tt>[^<>]*</tt>" 0 rdoc-code-face)
   (list "<code>[^<>]*</code>" 0 rdoc-code-face)
   (list "^\\([-*]\\|[0-9]+\\.\\|[A-Za-z]\\.\\)\\s "
	 1 rdoc-description-face) ; bullet | numbered | alphabetically numbered
   (list "^\\[[^\]]*\\]\\|\\S .*::\\)\\(\\s \\|$\\)"
	 1 rdoc-description-face)	; labeled | node
   ;(list "^\\s +\\(.*\\)" 1 rdoc-verbatim-face)
   ))
