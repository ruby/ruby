;;;
;;;  ruby-mode.el -
;;;
;;;  $Author$
;;;  $Date$
;;;  created at: Fri Feb  4 14:49:13 JST 1994
;;;

(defconst ruby-mode-revision "$Revision$")

(defconst ruby-mode-version
  (progn
   (string-match "[0-9.]+" ruby-mode-revision)
   (substring ruby-mode-revision (match-beginning 0) (match-end 0))))

(defconst ruby-block-beg-re
  "class\\|module\\|def\\|if\\|unless\\|case\\|while\\|until\\|for\\|begin\\|do"
  )

(defconst ruby-indent-beg-re
  "\\(\\s *\\(class\\|module\\|def\\)\\)\\|if\\|unless\\|case\\|while\\|until\\|for\\|begin"
    )

(defconst ruby-modifier-re
  "if\\|unless\\|while\\|until"
  )

(defconst ruby-block-mid-re
  "then\\|else\\|elsif\\|when\\|rescue\\|ensure"
  )

(defconst ruby-block-op-re
  "and\\|or\\|not"
  )

(defconst ruby-block-end-re "end")

(defconst ruby-delimiter
  (concat "[?$/%(){}#\"'`]\\|\\[\\|\\]\\|\\<\\("
	  ruby-block-beg-re
	  "\\|" ruby-block-end-re
	  "\\)\\>\\|^=begin")
  )

(defconst ruby-negative
  (concat "^[ \t]*\\(\\(" ruby-block-mid-re "\\)\\>\\|\\("
	    ruby-block-end-re "\\)\\>\\|\\}\\|\\]\\)")
  )

(defconst ruby-operator-chars "[,.+*/%-&|^~=<>:]")
(defconst ruby-symbol-chars "[a-zA-Z0-9_]")

(defvar ruby-mode-abbrev-table nil
  "Abbrev table in use in ruby-mode buffers.")

(define-abbrev-table 'ruby-mode-abbrev-table ())

(defvar ruby-mode-map nil "Keymap used in ruby mode.")

(if ruby-mode-map
    nil
  (setq ruby-mode-map (make-sparse-keymap))
  (define-key ruby-mode-map "{" 'ruby-electric-brace)
  (define-key ruby-mode-map "}" 'ruby-electric-brace)
  (define-key ruby-mode-map "\e\C-a" 'ruby-beginning-of-defun)
  (define-key ruby-mode-map "\e\C-e" 'ruby-end-of-defun)
  (define-key ruby-mode-map "\e\C-b" 'ruby-beginning-of-block)
  (define-key ruby-mode-map "\e\C-f" 'ruby-end-of-block)
  (define-key ruby-mode-map "\e\C-p" 'ruby-beginning-of-block)
  (define-key ruby-mode-map "\e\C-n" 'ruby-end-of-block)
  (define-key ruby-mode-map "\t" 'ruby-indent-command)
  (define-key ruby-mode-map "\C-c\C-e" 'ruby-insert-end)
  (define-key ruby-mode-map "\C-j" 'ruby-reindent-then-newline-and-indent)
  (define-key ruby-mode-map "\C-m" 'newline))

(defvar ruby-mode-syntax-table nil
  "Syntax table in use in ruby-mode buffers.")

(if ruby-mode-syntax-table
    ()
  (setq ruby-mode-syntax-table (make-syntax-table))
  (modify-syntax-entry ?\' "\"" ruby-mode-syntax-table)
  (modify-syntax-entry ?\" "\"" ruby-mode-syntax-table)
  (modify-syntax-entry ?\` "\"" ruby-mode-syntax-table)
  (modify-syntax-entry ?# "<" ruby-mode-syntax-table)
  (modify-syntax-entry ?\n ">" ruby-mode-syntax-table)
  (modify-syntax-entry ?\\ "'" ruby-mode-syntax-table)
  (modify-syntax-entry ?$ "/" ruby-mode-syntax-table)
  (modify-syntax-entry ?? "_" ruby-mode-syntax-table)
  (modify-syntax-entry ?_ "_" ruby-mode-syntax-table)
  (modify-syntax-entry ?< "." ruby-mode-syntax-table)
  (modify-syntax-entry ?> "." ruby-mode-syntax-table)
  (modify-syntax-entry ?& "." ruby-mode-syntax-table)
  (modify-syntax-entry ?| "." ruby-mode-syntax-table)
  (modify-syntax-entry ?% "." ruby-mode-syntax-table)
  (modify-syntax-entry ?= "." ruby-mode-syntax-table)
  (modify-syntax-entry ?/ "." ruby-mode-syntax-table)
  (modify-syntax-entry ?+ "." ruby-mode-syntax-table)
  (modify-syntax-entry ?* "." ruby-mode-syntax-table)
  (modify-syntax-entry ?- "." ruby-mode-syntax-table)
  (modify-syntax-entry ?\; "." ruby-mode-syntax-table)
  (modify-syntax-entry ?\( "()" ruby-mode-syntax-table)
  (modify-syntax-entry ?\) ")(" ruby-mode-syntax-table)
  (modify-syntax-entry ?\{ "(}" ruby-mode-syntax-table)
  (modify-syntax-entry ?\} "){" ruby-mode-syntax-table)
  (modify-syntax-entry ?\[ "(]" ruby-mode-syntax-table)
  (modify-syntax-entry ?\] ")[" ruby-mode-syntax-table)
  )

(defvar ruby-indent-level 2
  "*Indentation of ruby statements.")

(defun ruby-mode ()
  "Major mode for editing ruby scripts.
\\[ruby-indent-command] properly indents subexpressions of multi-line
class, module, def, if, while, for, do, and case statements, taking
nesting into account.

The variable ruby-indent-level controls the amount of indentation.
\\{ruby-mode-map}"
  (interactive)
  (kill-all-local-variables)
  (use-local-map ruby-mode-map)
  (setq mode-name "ruby")
  (setq major-mode 'ruby-mode)
  (set-syntax-table ruby-mode-syntax-table)
  (setq local-abbrev-table ruby-mode-abbrev-table)
  (make-local-variable 'indent-line-function)
  (setq indent-line-function 'ruby-indent-line)
  (make-local-variable 'require-final-newline)
  (setq require-final-newline t)
  (make-variable-buffer-local 'comment-start)
  (setq comment-start "# ")
  (make-variable-buffer-local 'comment-end)
  (setq comment-end "")
  (make-variable-buffer-local 'comment-column)
  (setq comment-column 32)
  (make-variable-buffer-local 'comment-start-skip)
  (setq comment-start-skip "\\(^\\|\\s-\\);?#+ *")
  (make-local-variable 'parse-sexp-ignore-comments)
  (setq parse-sexp-ignore-comments t)
  (run-hooks 'ruby-mode-hook))

(defun ruby-current-indentation ()
  (save-excursion
    (beginning-of-line)
    (back-to-indentation)
    (current-column)))

(defun ruby-indent-line (&optional flag)
  "Correct indentation of the current ruby line."
  (ruby-indent-to (ruby-calculate-indent)))

(defun ruby-indent-command ()
  (interactive)
  (ruby-indent-line t))

(defun ruby-indent-to (x)
  (if x
      (let (shift top beg)
	(and (< x 0)
	     (error "invalid nest"))
	(setq shift (current-column))
	(beginning-of-line)
	(setq beg (point))
	(back-to-indentation)
	(setq top (current-column))
	(skip-chars-backward " \t")
	(cond
	 ((>= x shift)
	  (setq shift 0))
	 ((>= shift top)
	  (setq shift (- shift top)))
	 (t (setq shift 0)))
	(if (and (bolp)
		 (= x top))
	    (move-to-column (+ x shift))
	  (move-to-column top)
	  (delete-region beg (point))
	  (beginning-of-line)
	  (indent-to x)
	  (move-to-column (+ x shift))))))

(defun ruby-expr-beg (&optional modifier)
  (save-excursion
    (if (looking-at "\\?")
	(progn
	  (or (bolp) (forward-char -1))
	  (not (looking-at "\\sw")))
      (skip-chars-backward " \t")
      (or (bolp) (forward-char -1))
      (or (looking-at ruby-operator-chars)
	  (looking-at "[\\[({!?]")
	  (bolp)
	  (and (looking-at ruby-symbol-chars)
	       (forward-word -1)
	       (or 
		(and modifier (bolp))
		(looking-at ruby-block-beg-re)
		(looking-at ruby-block-op-re)
		(looking-at ruby-block-mid-re)
		(and modifier
		     (save-excursion
		       (forward-char -1)
		       (let ((c (char-after (point))))
			 (or (eq c ?.)
			     (eq c ? )
			     (eq c ?\t))))))
	       (goto-char (match-end 0))
	       (looking-at "[^_]"))))))

(defun ruby-parse-region (start end)
  (let ((indent-point end)
	  (indent 0)
	  (in-string nil)
	  (in-paren nil)
	  (depth 0)
	  (nest nil)
	  (pcol nil))
    (save-excursion
	(if start
	    (goto-char start)
	  (ruby-beginning-of-indent))
	(save-restriction
	  (narrow-to-region (point) end)
	  (while (and (> indent-point (point))
		      (re-search-forward ruby-delimiter indent-point t))
	    (let ((pnt (point)) w)
	      (goto-char (match-beginning 0))
	      (cond
	       ((or (looking-at "\"")	;skip string
		    (looking-at "'")
		    (looking-at "`"))
		(setq w (char-after (point)))
		(cond
		 ((and (not (eobp))
		       (re-search-forward (format "[^\\]%c" w) indent-point t))
		  nil)
		 (t
		  (setq in-string (point))
		  (goto-char indent-point))))
	       ((looking-at "/")
		(cond
		 ((and (not (eobp)) (ruby-expr-beg))
		  (if (re-search-forward "[^\\]/" indent-point t)
		      nil
		    (setq in-string (point))
		    (goto-char indent-point)))
		 (t
		  (goto-char pnt))))
	       ((looking-at "%")
		(cond
		 ((and (not (eobp)) (ruby-expr-beg)
		       (looking-at "%[Qqrx]?\\(.\\)"))
		  (setq w (buffer-substring (match-beginning 1)
					    (match-end 1)))
		  (cond
		   ((string= w "[") (setq w "]"))
		   ((string= w "{") (setq w "}"))
		   ((string= w "(") (setq w ")"))
		   ((string= w "<") (setq w ">")))
		  (goto-char (match-end 0))
		  (if (search-forward w indent-point t)
		      nil
		    (setq in-string (point))
		    (goto-char indent-point)))
		 (t
		  (goto-char pnt))))
	       ((looking-at "\\?")	;skip ?char
		(cond
		 ((ruby-expr-beg)
		  (looking-at "?\\(\\\\C-\\|\\\\M-\\)*.")
		  (goto-char (match-end 0)))
		 (t
		  (goto-char pnt))))
	       ((looking-at "\\$")	;skip $char
		(goto-char pnt)
		(forward-char 1))
	       ((looking-at "#")		;skip comment
		(forward-line 1)
		(goto-char (point))
		)
	       ((looking-at "(")
		(setq nest (cons (cons (char-after (point)) pnt) nest))
		(setq pcol (cons (cons pnt depth) pcol))
		(setq depth 0)
		(goto-char pnt)
		)
	       ((looking-at "[\\[{]")
		(setq nest (cons (cons (char-after (point)) pnt) nest))
		(setq depth (1+ depth))
		(goto-char pnt)
		)
	       ((looking-at ")")
		(setq nest (cdr nest))
		(setq depth (cdr (car pcol)))
		(setq pcol (cdr pcol))
		(goto-char pnt))
	       ((looking-at "[])}]")
		(setq nest (cdr nest))
		(setq depth (1- depth))
		(goto-char pnt))
	       ((looking-at ruby-block-end-re)
		(if (or (and (not (bolp))
			     (progn
			       (forward-char -1)
			       (eq ?_ (char-after (point)))))
			(progn
			  (goto-char pnt)
			  (setq w (char-after (point)))
			  (or (eq ?_ w)
			      (eq ?! w)
			      (eq ?? w))))
		    nil
		  (setq nest (cdr nest))
		  (setq depth (1- depth)))
		(goto-char pnt))
	       ((looking-at ruby-block-beg-re)
		(and 
		 (or (bolp)
		     (progn
		       (forward-char -1)
		       (not (eq ?_ (char-after (point))))))
		 (progn
		   (goto-char pnt)
		   (setq w (char-after (point)))
		   (and (not (eq ?_ w))
			(not (eq ?! w))
			(not (eq ?? w))))
		 (progn
		   (goto-char (match-beginning 0))
		   (if (looking-at ruby-modifier-re)
		       (ruby-expr-beg)
		     t))
		 (progn
		   (setq nest (cons (cons nil pnt) nest))
		   (setq depth (1+ depth))))
		(if (looking-at "def\\s *[/`]")
		    (goto-char (match-end 0))
		  (goto-char pnt)))
	       ((looking-at "^=begin")
		(if (re-search-forward "^=end" indent-point t)
		    (forward-line 1)
		  (setq in-string (match-end 0))
		  (goto-char indent-point)))
	       (t
		(error (format "bad string %s"
			       (buffer-substring (point) pnt)
			       )))))))
	(list in-string (car nest) depth (car (car pcol))))))

(defun ruby-calculate-indent (&optional parse-start)
  (save-excursion
    (beginning-of-line)
    (let ((indent-point (point))
	    (case-fold-search nil)
	    state bol eol
	    (indent 0))
	(if parse-start
	    (goto-char parse-start)
	  (ruby-beginning-of-indent)
	  (setq parse-start (point)))
	(back-to-indentation)
	(setq indent (current-column))
	(setq state (ruby-parse-region parse-start indent-point))
	(cond
	 ((nth 0 state)			; within string
	  (setq indent nil))		;  do nothing

	 ((car (nth 1 state))		; in paren
	  (goto-char (cdr (nth 1 state)))
	  (if (eq (car (nth 1 state)) ?\( )
	      (let ((column (current-column))
		    (s (ruby-parse-region (point) indent-point)))
		(cond
		 ((and (nth 2 s) (> (nth 2 s) 0))
		  (goto-char (cdr (nth 1 s)))
		  (forward-word -1)
		  (setq indent (+ (current-column) ruby-indent-level)))
		 (t 
		  (setq indent (current-column)))))
	    (cond
	     ((nth 3 state)
	      (goto-char (nth 3 state))
	      (setq indent (+ (current-column) ruby-indent-level)))
	     (t
	      (goto-char parse-start)
	      (back-to-indentation)
	      (setq indent (+ (current-column) (* (nth 2 state) ruby-indent-level)))))
	    ))

	 ((and (nth 2 state)(> (nth 2 state) 0)) ; in nest
	  (if (null (cdr (nth 1 state)))
	      (error "invalid nest"))
	  (goto-char (cdr (nth 1 state)))
	  (forward-word -1)		; skip back a keyword
	  (cond
	   ((looking-at "do")		; iter block is a special case
	    (cond
	     ((nth 3 state)
	      (goto-char (nth 3 state))
	      (setq indent (+ (current-column) ruby-indent-level)))
	     (t
	      (goto-char parse-start)
	      (back-to-indentation)
	      (setq indent (+ (current-column) (* (nth 2 state) ruby-indent-level))))))
	   (t
	    (setq indent (+ (current-column) ruby-indent-level)))))

	 ((and (nth 2 state) (< (nth 2 state) 0)) ; in negative nest
	  (setq indent (+ (current-column) (* (nth 2 state) ruby-indent-level)))))

	(cond
	 (indent
	  (goto-char indent-point)
	  (end-of-line)
	  (setq eol (point))
	  (beginning-of-line)
	  (cond 
	   ((re-search-forward ruby-negative eol t)
	    (and (not (eq ?_ (char-after (match-end 0))))
		 (setq indent (- indent ruby-indent-level))))
	   ;;operator terminated lines
	   ((and
	     (save-excursion
	       (beginning-of-line)
	       (not (bobp)))
	     (or (null (car (nth 1 state))) ;not in parens
		 (and (eq (car (nth 1 state)) ?\{)
		      (save-excursion	;except non-block braces
			(goto-char (cdr (nth 1 state)))
			(or (bobp) (forward-char -1))
			(not (ruby-expr-beg))))))
	    ;; goto beginning of non-empty no-comment line
	    (let (end done)
	      (while (not done)
		(skip-chars-backward " \t\n")
		(setq end (point))
		(beginning-of-line)
		(if (re-search-forward "^\\s *#" end t)
		    (beginning-of-line)
		  (setq done t))))
	    (setq bol (point))
	    (end-of-line)
	    (skip-chars-backward " \t")
	    (or (bobp) (forward-char -1))
	    (and
	     (or (and (looking-at ruby-symbol-chars)
		      (skip-chars-backward ruby-symbol-chars)
		      (looking-at ruby-block-op-re)
		      (save-excursion
			(goto-char (match-end 0))
			(not (looking-at "[a-z_]"))))
		 (and (looking-at ruby-operator-chars)
		      (or (not (or (eq ?/ (char-after (point)))))
			  (null (nth 0 (ruby-parse-region parse-start (point)))))
		      (not (eq (char-after (1- (point))) ?$))
		      (or (not (eq ?| (char-after (point))))
			  (save-excursion
			    (or (eolp) (forward-char -1))
			    (and (search-backward "|")
				 (skip-chars-backward " \t\n")
				 (and (not (eolp))
				      (progn
					(forward-char -1)
					(not (looking-at "\\{")))
				      (progn
					(forward-word -1)
					(not (looking-at "do\\>[^_]")))))))))
	     (setq indent (+ indent ruby-indent-level)))))))
	indent)))
 
(defun ruby-electric-brace (arg)
  (interactive "P")
  (self-insert-command (prefix-numeric-value arg))
  (ruby-indent-line t))

(defun ruby-beginning-of-defun (&optional arg)
  "Move backward to next beginning-of-defun.
With argument, do this that many times.
Returns t unless search stops due to end of buffer."
  (interactive "p")
  (and (re-search-backward (concat "^\\(" ruby-block-beg-re "\\)\\b")
			   nil 'move (or arg 1))
       (progn (beginning-of-line) t)))

(defun ruby-beginning-of-indent ()
  (and (re-search-backward (concat "^\\(" ruby-indent-beg-re "\\)\\b")
			   nil 'move)
       (progn
	 (beginning-of-line)
	 t)))

(defun ruby-end-of-defun (&optional arg)
  "Move forward to next end of defun.
An end of a defun is found by moving forward from the beginning of one."
  (interactive "p")
  (and (re-search-forward (concat "^\\(" ruby-block-end-re "\\)\\b[^_]")
			  nil 'move (or arg 1))
       (progn (beginning-of-line) t))
  (forward-line 1))

(defun ruby-move-to-block (n)
  (let (start pos done down)
    (setq start (ruby-calculate-indent))
    (if (eobp)
	nil
      (while (and (not (bobp)) (not done))
	(forward-line n)
	(cond
	 ((looking-at "^$"))
	 ((looking-at "^\\s *#"))
	 (t
	  (setq pos (current-indentation))
	  (cond
	   ((< start pos)
	    (setq down t))
	   ((and down (= pos start))
	    (setq done t))
	   ((> start pos)
	    (setq done t)))))
	(if done
	    (progn
	      (back-to-indentation)
	      (if (looking-at ruby-block-mid-re)
		  (setq done nil)))))))
  (back-to-indentation))

(defun ruby-beginning-of-block ()
  "Move backward to next beginning-of-block"
  (interactive)
  (ruby-move-to-block -1))

(defun ruby-end-of-block ()
  "Move forward to next beginning-of-block"
  (interactive)
  (ruby-move-to-block 1))

(defun ruby-reindent-then-newline-and-indent ()
  (interactive "*")
  (save-excursion
    (delete-region (point) (progn (skip-chars-backward " \t") (point))))
  (newline)
  (save-excursion
    (forward-line -1)
    (indent-according-to-mode))
  (indent-according-to-mode))

(fset 'ruby-encomment-region (symbol-function 'comment-region))

(defun ruby-decomment-region (beg end)
  (interactive "r")
  (save-excursion
    (goto-char beg)
    (while (re-search-forward "^\\([ \t]*\\)#" end t)
      (replace-match "\\1" nil nil)
      (save-excursion
	(ruby-indent-line)))))

(defun ruby-insert-end ()
  (interactive)
  (insert "end")
  (ruby-indent-line t)
  (end-of-line))

(cond
 ((featurep 'hilit19)
  (hilit-set-mode-patterns
   'ruby-mode
   '(("[^$\\?]\\(\"[^\\\"]*\\(\\\\\\(.\\|\n\\)[^\\\"]*\\)*\"\\)" 1 string)
     ("[^$\\?]\\('[^\\']*\\(\\\\\\(.\\|\n\\)[^\\']*\\)*'\\)" 1 string)
     ("[^$\\?]\\(`[^\\`]*\\(\\\\\\(.\\|\n\\)[^\\`]*\\)*`\\)" 1 string)
     ("^\\s *#.*$" nil comment)
     ("[^$@?\\]\\(#[^$@{].*$\\)" 1 comment)
     ("[^a-zA-Z_]\\(\\?\\(\\\\[CM]-\\)*.\\)" 1 string)
     ("^\\s *\\(require\\|load\\).*$" nil include)
     ("^\\s *\\(include\\|alias\\|undef\\).*$" nil decl)
     ("^\\s *\\<\\(class\\|def\\|module\\)\\>" "[)\n;]" defun)
     ("[^_]\\<\\(begin\\|case\\|else\\|elsif\\|end\\|ensure\\|for\\|if\\|unless\\|rescue\\|then\\|when\\|while\\|until\\|do\\)\\>[^_]" 1 defun)
     ("[^_]\\<\\(and\\|break\\|next\\|raise\\|fail\\|in\\|not\\|or\\|redo\\|retry\\|return\\|super\\|yield\\|self\\|nil\\)\\>[^_]" 1 keyword)
     ("\\$\\(.\\|\\sw+\\)" nil type)
     ("[$@].[a-zA-Z_0-9]*" nil struct)
     ("^__END__" nil label))))

 ((featurep 'font-lock)
  (or (boundp 'font-lock-variable-name-face)
      (setq font-lock-variable-name-face font-lock-type-face))
  (defvar ruby-font-lock-keywords
    (list
     (cons (concat
	    "\\(^\\|[^_]\\)\\b\\("
	    (mapconcat
	     'identity
	     '("alias"
	       "and"
	       "begin"
	       "break"
	       "case"
	       "class"
	       "do"
	       "elsif"
	       "else"
	       "fail"
	       "ensure"
	       "for"
	       "end"
	       "if"
	       "in"
	       "module"
	       "next"
	       "not"
	       "or"
	       "raise"
	       "redo"
	       "rescue"
	       "retry"
	       "return"
	       "then"
	       "self"
	       "super"
	       "unless"
	       "undef"
	       "until"
	       "when"
	       "while"
	       )
	     "\\|")
	    "\\)[ \n\t()]")
	   2)
     ;; variables
     '("\\(^\\|[^_]\\)\\b\\(nil\\|self\\|true\\|false\\)\\b[^_]"
       2 font-lock-variable-name-face)
     ;; variables
     '("\\[$@].\\([a-zA-Z0-9_]\\)"
       0 font-lock-variable-name-face)
     ;; constants
     '("\\(^\\|[^_]\\)\\b\\([A-Z]+[a-zA-Z0-9_]*\\)"
       2 font-lock-type-face)
     ;; functions
     '("^\\s *def[ \t]+[^ \t(]*"
       0 font-lock-function-name-face t))
    "*Additional expressions to highlight in ruby mode.")
  (if (and (>= (string-to-int emacs-version) 20)
          (not (featurep 'xemacs)))
      (add-hook
       'ruby-mode-hook
       (lambda ()
        (make-local-variable 'font-lock-defaults)
        (setq font-lock-defaults 
              '((ruby-font-lock-keywords) nil nil ((?\_ . "w"))))))
    (add-hook 'ruby-mode-hook
             (lambda ()
               (setq font-lock-keywords ruby-font-lock-keywords)
               (font-lock-mode 1))))))
