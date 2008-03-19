;;; -*- emacs-lisp -*-
;;;
;;; ruby-style.el -
;;;
;;; C/C++ mode style for Ruby.
;;;
;;;  $Author: nobu $
;;;  created at: Thu Apr 26 13:54:01 JST 2007
;;;

(defconst ruby-style-revision "$Revision: 15588 $"
  "Ruby style revision string.")

(defconst ruby-style-version
  (progn
   (string-match "[0-9.]+" ruby-style-revision)
   (substring ruby-style-revision (match-beginning 0) (match-end 0)))
  "Ruby style version number.")

(defun ruby-style-case-indent (x)
  (save-excursion
    (unless (progn (backward-up-list) (back-to-indentation)
		   (> (point) (cdr x)))
      (goto-char (cdr x))
      (if (looking-at "\\<case\\|default\\>") '*))))

(defun ruby-style-label-indent (x)
  (save-excursion
    (unless (progn (backward-up-list) (back-to-indentation)
		   (>= (point) (cdr x)))
      (goto-char (cdr x))
      (condition-case ()
	  (progn
	    (backward-up-list)
	    (backward-sexp 2)
	    (if (looking-at "\\<switch\\>") '/))
	(error)))))

(require 'cc-styles)
(c-add-style
 "ruby"
 '("bsd"
   (c-basic-offset . 4)
   (tab-width . 8)
   (indent-tabs-mode . t)
   (c-offsets-alist
    (case-label . *)
    (label . (ruby-style-label-indent *))
    (statement-case-intro . *)
    (statement-case-open . *)
    (statement-block-intro . (ruby-style-case-indent +))
    (access-label /)
    )))

(defun ruby-style-c-mode ()
  (interactive)
  (if (or (string-match "/ruby\\>" (buffer-file-name))
          (save-excursion
            (goto-char (point-min))
            (let ((head (progn (forward-line 100) (point)))
                  (case-fold-search nil))
              (goto-char (point-min))
              (re-search-forward "Copyright (C) .* Yukihiro Matsumoto" head t))))
      (setq c-file-style "ruby")))

(provide 'ruby-style)
