;;; -*- emacs-lisp -*-
;;; C/C++ mode style for Ruby.

(defun ruby-style-case-indent (x)
  (save-excursion
    (goto-char (cdr x))
    (if (looking-at "\\<case\\|default\\>")
	(- c-basic-offset
	   (% (current-column) c-basic-offset)))))

(require 'cc-styles)
(c-add-style
 "ruby"
 '("bsd"
   (c-basic-offset . 4)
   (c-offsets-alist
    (case-label . *)
    (label . *)
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
