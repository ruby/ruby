;;; ruby-additional.el --- ruby-mode extensions yet to be merged into Emacs

;; Authors: Yukihiro Matsumoto, Nobuyoshi Nakada, Akinori MUSHA
;; URL: https://svn.ruby-lang.org/cgi-bin/viewvc.cgi/trunk/misc/
;; Created: 3 Sep 2012
;; Package-Requires: ((emacs "24.3") (ruby-mode "1.2"))
;; Keywords: ruby, languages

;;; Commentary:
;;
;; This package contains ruby-mode extensions yet to be merged into
;; the latest released version of Emacs distribution.  For older
;; versions of Emacs, use ruby-mode.el bundled with CRuby.

;;; Code:

(eval-when-compile
  (require 'ruby-mode))

(eval-after-load 'ruby-mode
  '(progn
     (define-key ruby-mode-map "\C-c\C-e" 'ruby-insert-end)

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

     (defconst ruby-default-encoding-map
       '((us-ascii       . nil)       ;; Do not put coding: us-ascii
         (utf-8          . nil)       ;; Do not put coding: utf-8
         (shift-jis      . cp932)     ;; Emacs charset name of Shift_JIS
         (shift_jis      . cp932)     ;; MIME charset name of Shift_JIS
         (japanese-cp932 . cp932))    ;; Emacs charset name of CP932
       )

     (custom-set-default 'ruby-encoding-map ruby-default-encoding-map)

     (defcustom ruby-encoding-map ruby-default-encoding-map
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
                                  (or (and (coding-system-get coding-system :prefer-utf-8)
                                           'utf-8)
                                      (coding-system-get default-buffer-file-coding-system :coding-type)
                                      'ascii-8bit)))
                             ((memq coding-type '(utf-8 shift-jis))
                              coding-type)
                             (t coding-system))))))
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

     (define-key ruby-mode-map "\C-cU" 'ruby-encode-decode-unicode)

     (defun ruby-encode-unicode (beg end)
       "Convert non-ascii string in the given region to \\u{} form."
       (interactive "r")
       (setq end (set-marker (make-marker) end))
       (goto-char beg)
       (while (and (< (point) end)
		   (re-search-forward "\\([\C-@-\C-I\C-K\C-_\C-?]+\\)\\|[^\C-@-\C-?]+" end t))
	 (let ((str (match-string-no-properties 0)) sep b e f)
	   (if (match-beginning 1)
	       (setq b "" e "" sep ""
		     f (lambda (c)
			 (cond ((= c ?\t) "\\t")
			       ((= c ?\r) "\\r")
			       ((= c ?\e) "\\e")
			       ((= c ?\f) "\\f")
			       ((= c ?\b) "\\b")
			       ((= c ?\v) "\\v")
			       ((= c ?\C-?) "\\c?")
			       ((concat "\\c" (char-to-string (logior c #x40)))))))
	     (setq b "\\u{" e "}" sep " " f (lambda (c) (format "%x" c))))
	   (setq str (mapconcat f str sep))
	   (delete-region (match-beginning 0) (match-end 0))
	   (insert b str e))))

     (defun ruby-decode-unicode (beg end)
       "Convert escaped Unicode in the given region to raw string."
       (interactive "r")
       (setq end (set-marker (make-marker) end))
       (goto-char beg)
       (while (and (< (point) end)
		   (re-search-forward "\\\\u\\([0-9a-fA-F]\\{4\\}\\)\\|\\\\u{\\([0-9a-fA-F \t]+\\)}" end t))
	 (let ((b (match-beginning 0)) (e (match-end 0))
	       (s (match-string-no-properties 1)))
	   (if s
	       (setq s (cons s nil))
	     (goto-char (match-beginning 2))
	     (while (looking-at "[ \t]*\\([0-9a-fA-F]+\\)")
	       (setq s (cons (match-string-no-properties 1) s))
	       (goto-char (match-end 0))))
	   (setq s (mapconcat (lambda (c) (format "%c" (string-to-int c 16)))
			      (nreverse s) ""))
	   (delete-region b e)
	   (insert s))
	 ))

     (defun ruby-encode-decode-unicode (dec beg end)
       "Convert Unicode <-> \\u{} in the given region."
       (interactive "P\nr")
       (if dec (ruby-decode-unicode beg end) (ruby-encode-unicode beg end)))

     (defun ruby-insert-heredoc-code-block (arg)
       "Insert indented here document code block"
       (interactive "P")
       (let ((c (if arg "~" "-")))
	 (insert "\"#{<<" c "\"begin\;\"}\\n#{<<" c "'end;'}\""))
       (end-of-line)
       (if (eobp) (insert "\n") (forward-char))
       (indent-region (point)
		      (progn (insert "begin;\n" "end;\n") (point)))
       (beginning-of-line 0))
     (define-key ruby-mode-map "\C-cH" 'ruby-insert-heredoc-code-block)
     ))

;; monkey-patching ruby-mode.el in Emacs 24, as r49872.
(when (and (boundp 'ruby-syntax-before-regexp-re)
	   (not (string-match ruby-syntax-before-regexp-re "foo {|" 1)))
  (replace-regexp-in-string "\\[\\[" "\\&{|" ruby-syntax-before-regexp-re))

(provide 'ruby-additional)

;;; ruby-additional.el ends here
