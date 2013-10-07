;;; ruby-additional.el --- ruby-mode extensions yet to be merged into Emacs

;; Authors: Yukihiro Matsumoto, Nobuyoshi Nakada, Akinori MUSHA
;; URL: http://svn.ruby-lang.org/cgi-bin/viewvc.cgi/trunk/misc/
;; Created: 3 Sep 2012
;; Package-Requires: ((ruby-mode "1.2"))
;; Keywords: ruby, languages

;;; Commentary:
;;
;; This package contains ruby-mode extensions yet to be merged into
;; the Emacs distribution.

;;; Code:

(eval-when-compile
  (require 'ruby-mode))

(eval-after-load 'ruby-mode
  '(progn
     (define-key ruby-mode-map "\C-c\C-e" 'ruby-insert-end)
     (define-key ruby-mode-map "\C-c{" 'ruby-toggle-block)

     (defun ruby-insert-end ()
       (interactive)
       (if (eq (char-syntax (preceding-char)) ?w)
           (insert " "))
       (insert "end")
       (save-excursion
         (if (eq (char-syntax (following-char)) ?w)
             (insert " "))
         (ruby-indent-line t)
         (end-of-line)))

     (defun ruby-brace-to-do-end ()
       (when (looking-at "{")
         (let ((orig (point)) (end (progn (ruby-forward-sexp) (point))))
           (when (eq (preceding-char) ?\})
             (delete-char -1)
             (if (eq (char-syntax (preceding-char)) ?w)
                 (insert " "))
             (insert "end")
             (if (eq (char-syntax (following-char)) ?w)
                 (insert " "))
             (goto-char orig)
             (delete-char 1)
             (if (eq (char-syntax (preceding-char)) ?w)
                 (insert " "))
             (insert "do")
             (when (looking-at "\\sw\\||")
               (insert " ")
               (backward-char))
             t))))

     (defun ruby-do-end-to-brace ()
       (when (and (or (bolp)
                      (not (memq (char-syntax (preceding-char)) '(?w ?_))))
                  (looking-at "\\<do\\(\\s \\|$\\)"))
         (let ((orig (point)) (end (progn (ruby-forward-sexp) (point))))
           (backward-char 3)
           (when (looking-at ruby-block-end-re)
             (delete-char 3)
             (insert "}")
             (goto-char orig)
             (delete-char 2)
             (insert "{")
             (if (looking-at "\\s +|")
                 (delete-char (- (match-end 0) (match-beginning 0) 1)))
             t))))

     (defun ruby-toggle-block ()
       (interactive)
       (or (ruby-brace-to-do-end)
           (ruby-do-end-to-brace)))

     (defcustom ruby-encoding-map
       '((us-ascii       . nil)       ;; Do not put coding: us-ascii
         (utf-8          . nil)       ;; Do not put coding: utf-8
         (shift-jis      . cp932)     ;; Emacs charset name of Shift_JIS
         (shift_jis      . cp932)     ;; MIME charset name of Shift_JIS
         (japanese-cp932 . cp932))    ;; Emacs charset name of CP932
       "Alist to map encoding name from Emacs to Ruby.
Associating an encoding name with nil means it needs not be
explicitly declared in magic comment."
       :type '(repeat (cons (symbol :tag "From") (symbol :tag "To")))
       :group 'ruby)

     (defun ruby-mode-set-encoding ()
       "Insert or update a magic comment header with the proper encoding.
`ruby-encoding-map' is looked up to convert an encoding name from
Emacs to Ruby."
       (let* ((nonascii
               (save-excursion
                 (widen)
                 (goto-char (point-min))
                 (re-search-forward "[^\0-\177]" nil t)))
              (coding-system
               (or coding-system-for-write
                   buffer-file-coding-system))
              (coding-system
               (and coding-system
                    (coding-system-change-eol-conversion coding-system nil)))
              (coding-system
               (and coding-system
                    (or
                     (coding-system-get coding-system :mime-charset)
                     (let ((coding-type (coding-system-get coding-system :coding-type)))
                       (cond ((eq coding-type 'undecided)
                              (if nonascii
                                  (if (coding-system-get coding-system :prefer-utf-8)
                                      'utf-8 'ascii-8bit)))
                             ((memq coding-type '(utf-8 shift-jis))
                              coding-type))))))
              (coding-system
               (or coding-system
                   'us-ascii))
              (coding-system
               (let ((cons (assq coding-system ruby-encoding-map)))
                 (if cons (cdr cons) coding-system)))
              (coding-system
               (and coding-system
                    (symbol-name coding-system))))
         (if coding-system
             (save-excursion
               (widen)
               (goto-char (point-min))
               (if (looking-at "^#!") (beginning-of-line 2))
               (cond ((looking-at "\\s *#.*-\*-\\s *\\(en\\)?coding\\s *:\\s *\\([-a-z0-9_]*\\)\\s *\\(;\\|-\*-\\)")
                      (unless (string= (match-string 2) coding-system)
                        (goto-char (match-beginning 2))
                        (delete-region (point) (match-end 2))
                        (and (looking-at "-\*-")
                             (let ((n (skip-chars-backward " ")))
                               (cond ((= n 0) (insert "  ") (backward-char))
                                     ((= n -1) (insert " "))
                                     ((forward-char)))))
                        (insert coding-system)))
                     ((looking-at "\\s *#.*coding\\s *[:=]"))
                     (t (when ruby-insert-encoding-magic-comment
                          (insert "# -*- coding: " coding-system " -*-\n"))))))))

     ))

(provide 'ruby-additional)

;;; ruby-additional.el ends here
