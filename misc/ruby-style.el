;;; -*- emacs-lisp -*-
;;; C/C++ mode style for Ruby.

(defun ruby-style-case-indent (x)
  (save-excursion
    (goto-char (cdr x))
    (if (looking-at "\\<case\\|default\\>") '*)))

(defun ruby-style-label-indent (x)
  (save-excursion
    (goto-char (cdr x))
    (backward-up-list)
    (backward-sexp 2)
    (if (looking-at "\\<switch\\>") '/)))

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
