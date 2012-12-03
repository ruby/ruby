;; missing functions in Emacs 24.

(eval-after-load "\\(\\`\\|/\\)ruby-mode\\.elc?\\(\\.gz\\)?\\'"
  (progn
    (define-key ruby-mode-map "\C-c\C-e" 'ruby-insert-end)
    (define-key ruby-mode-map "\C-c{" 'ruby-toggle-block)

    (defun ruby-insert-end ()
      (interactive)
      (if (eq (char-syntax (char-before)) ?w)
	  (insert " "))
      (insert "end")
      (save-excursion
	(if (eq (char-syntax (char-after)) ?w)
	    (insert " "))
	(ruby-indent-line t)
	(end-of-line)))

    (defun ruby-brace-to-do-end ()
      (when (looking-at "{")
	(let ((orig (point)) (end (progn (ruby-forward-sexp) (point))))
	  (when (eq (char-before) ?\})
	    (delete-char -1)
	    (if (eq (char-syntax (char-before)) ?w)
		(insert " "))
	    (insert "end")
	    (if (eq (char-syntax (char-after)) ?w)
		(insert " "))
	    (goto-char orig)
	    (delete-char 1)
	    (if (eq (char-syntax (char-before)) ?w)
		(insert " "))
	    (insert "do")
	    (when (looking-at "\\sw\\||")
	      (insert " ")
	      (backward-char))
	    t))))

    (defun ruby-do-end-to-brace ()
      (when (and (or (bolp)
		     (not (memq (char-syntax (char-before)) '(?w ?_))))
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

    (defun ruby-mode-set-encoding ()
      "Insert a magic comment header with the proper encoding always.
Now encoding needs to be set always explicitly actually."
      (save-excursion
	(let ((coding-system))
	  (widen)
	  (goto-char (point-min))
	  (if (re-search-forward "[^\0-\177]" nil t)
	      (progn
		(goto-char (point-min))
		(setq coding-system
                      (or coding-system-for-write
                          buffer-file-coding-system))
		(if coding-system
		    (setq coding-system
			  (or (coding-system-get coding-system 'mime-charset)
			      (coding-system-change-eol-conversion coding-system nil))))
		(setq coding-system
		      (if coding-system
			  (symbol-name
			   (or (and ruby-use-encoding-map
				    (cdr (assq coding-system ruby-encoding-map)))
			       coding-system))
			"ascii-8bit")))
	    (setq coding-system "us-ascii"))
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
		     (insert "# -*- coding: " coding-system " -*-\n")))))))

    ))
