;;; -*- emacs-lisp -*-
;;;
;;; ruby-style.el -
;;;
;;; C/C++ mode style for Ruby.
;;;
;;;  $Author$
;;;  created at: Thu Apr 26 13:54:01 JST 2007
;;;
;;; Put this file under a directory contained in ``load-path'', and
;;; then load it.
;;; To switch to the "ruby" style automatically if it looks like a
;;; source file of ruby, add ruby-style-c-mode to c-mode-hook:
;;;
;;;   (require 'ruby-style)
;;;   (add-hook 'c-mode-hook 'ruby-style-c-mode)
;;;   (add-hook 'c++-mode-hook 'ruby-style-c-mode)
;;;
;;; Customize the c-default-style variable to set the default style
;;; for each CC major mode.

(defconst ruby-style-revision "$Revision$"
  "Ruby style revision string.")

(defconst ruby-style-version
  (and
   (string-match "[0-9.]+" ruby-style-revision)
   (substring ruby-style-revision (match-beginning 0) (match-end 0)))
  "Ruby style version number.")

(defun ruby-style-case-indent (x)
  (save-excursion
    (back-to-indentation)
    (unless (progn (backward-up-list) (back-to-indentation)
                   (> (point) (cdr x)))
      (goto-char (cdr x))
      (if (looking-at "\\<case\\|default\\>") '*))))

(defun ruby-style-label-indent (x)
  (save-excursion
    (back-to-indentation)
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
   (indent-tabs-mode . nil)
   (show-trailing-whitespace . t)
   (c-backslash-column . 1)
   (c-backslash-max-column . 1)
   (c-offsets-alist
    (case-label . *)
    (label . (ruby-style-label-indent *))
    (statement-case-intro . *)
    (statement-case-open . *)
    (statement-block-intro . (ruby-style-case-indent +))
    (access-label /)
    )))

(c-add-style
 "prism"
 '("bsd"
   (c-basic-offset . 4)
   (tab-width . 8)
   (indent-tabs-mode . nil)
   (show-trailing-whitespace . t)
   (c-offsets-alist
    (case-label . +)
    )))

;;;###autoload
(defun ruby-style-c-mode ()
  (interactive)
  (if (or (let ((name (buffer-file-name))) (and name (string-match "/ruby\\>" name)))
          (save-excursion
            (goto-char (point-min))
            (let ((head (progn (forward-line 100) (point)))
                  (case-fold-search nil))
              (goto-char (point-min))
              (re-search-forward "Copyright (C) .* Yukihiro Matsumoto" head t)))
	  (condition-case ()
	      (with-temp-buffer
		(when (= 0 (call-process "git" nil t nil "remote" "get-url" "origin"))
		  (goto-char (point-min))
		  (looking-at ".*/ruby\\(\\.git\\)?$")))
	    (error))
	  (condition-case ()
	      (with-temp-buffer
		(when (= 0 (call-process "svn" nil t nil "info" "--xml"))
		  (goto-char (point-min))
		  (search-forward-regexp "<root>.*/ruby</root>" nil)))
	    (error))
	  nil)
      (c-set-style "ruby")))

(provide 'ruby-style)
