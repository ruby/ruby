;;;
;;;  ruby-mode.el -
;;;
;;;  $Author$
;;;  $Revision$
;;;  $Date$
;;;  created at: Fri Feb  4 14:49:13 JST 1994
;;;

(defconst ruby-block-beg-re
  "class\\|module\\|def\\|if\\|case\\|while\\|for\\|begin"
  )

(defconst ruby-block-mid-re
  "then\\|else\\|elsif\\|when\\|rescue\\|ensure"
  )

(defconst ruby-block-end-re "end")

(defconst ruby-delimiter
  (concat "[?$/(){}#\"'`]\\|\\[\\|\\]\\|\\<\\("
	  ruby-block-beg-re "\\|" ruby-block-end-re "\\)\\>")
  )

(defconst ruby-negative
  (concat "^[ \t]*\\(\\b\\(" ruby-block-mid-re "\\)\\|\\("
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
  (define-key ruby-mode-map "\t" 'ruby-indent-command)
  (define-key ruby-mode-map "\C-m" 'ruby-reindent-then-newline-and-indent)
  (define-key ruby-mode-map "\C-j" 'newline))

(defvar ruby-mode-syntax-table nil
  "Syntax table in use in ruby-mode buffers.")

(if ruby-mode-syntax-table
    ()
  (setq ruby-mode-syntax-table (make-syntax-table))
  (modify-syntax-entry ?\' "\"" ruby-mode-syntax-table)
  (modify-syntax-entry ?\" "\"" ruby-mode-syntax-table)
  (modify-syntax-entry ?# "<" ruby-mode-syntax-table)
  (modify-syntax-entry ?\n ">" ruby-mode-syntax-table)
  (modify-syntax-entry ?\\ "'" ruby-mode-syntax-table)
  (modify-syntax-entry ?$ "/" ruby-mode-syntax-table)
  (modify-syntax-entry ?? "/" ruby-mode-syntax-table)
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
  (setq comment-start-skip "#+ *")
  (make-local-variable 'parse-sexp-ignore-comments)
  (setq parse-sexp-ignore-comments t)
  (run-hooks 'ruby-mode-hook))

(defun ruby-current-indentation ()
  (save-excursion
    (beginning-of-line)
    (back-to-indentation)
    (current-column)))

(defun ruby-delete-indentation ()
  (let
      ((b nil)
       (m nil))
    (save-excursion
      (beginning-of-line)
      (setq b (point))
      (back-to-indentation)
      (setq m (point)))
    (delete-region b m)))

(defun ruby-indent-line (&optional flag)
  "Correct indentation of the current ruby line."
  (ruby-indent-to (ruby-calculate-indent)))

(defun ruby-indent-command ()
  (interactive)
  (ruby-indent-line t))

(defun ruby-indent-to (x)
  (let ((p nil) beg end)
    (if (null x)
	nil
      (setq p (- (current-column) (ruby-current-indentation)))
      (ruby-delete-indentation)
      (beginning-of-line)
      (save-excursion
	(setq beg (point))
	(forward-line 1)
	(setq end (point)))
      (indent-to x)
      (if (> p 0) (forward-char p)))))

(defun ruby-expr-beg ()
  (save-excursion
    (skip-chars-backward " \t")
    (or (bolp) (forward-char -1))
    (or (looking-at ruby-operator-chars)
	(looking-at "[\\[({]")
	(bolp)
	(and (looking-at ruby-symbol-chars)
	     (forward-word -1)
	     (or 
	      (looking-at ruby-block-beg-re)
	      (looking-at ruby-block-mid-re))))))

(defun ruby-parse-region (start end)
  (let ((indent-point end)
	(indent 0)
	(in-string nil)
	(in-paren nil)
	(depth 0)
	(nest nil))
    (save-excursion
      (if start
	  (goto-char start)
	(ruby-beginning-of-defun))
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
		     (equal w (char-after (point)))
		     (re-search-forward (format "[^\\]%c" w) indent-point t))
		nil)
	       (t
		(goto-char indent-point)
		(setq in-string t))))
	     ((looking-at "/")
	      (if (and (ruby-expr-beg)
		       (goto-char pnt)
		       (looking-at "\\([^/\n]\\|\\\\/\\)*")
		       (eq ?/ (char-after (match-end 0))))
		  (goto-char (1+ (match-end 0)))
		(goto-char indent-point)
		(setq in-string t)))
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
	      (goto-char pnt))
	     ((looking-at "[\\[({]")
	      (setq nest (cons (cons (char-after (point)) pnt) nest))
	      (setq depth (1+ depth))
	      (goto-char pnt))
	     ((looking-at "[])}]")
	      (setq nest (cdr nest))
	      (setq depth (1- depth))
	      (goto-char pnt))
	     ((looking-at ruby-block-end-re)
	      (if (and (not (bolp))
		       (progn
			 (forward-char -1)
			 (eq ?_ (char-after (point))))
		       (progn
			 (goto-char pnt)
			 (eq ?_ (char-after (point)))))
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
	       (save-excursion
		 (goto-char pnt)
		 (not (eq ?_ (char-after (point)))))
	       (skip-chars-backward " \t")
	       (or (bolp)
		   (save-excursion
		     (forward-char -1)
		     (looking-at ruby-operator-chars)))
	       (progn
		 (setq nest (cons (cons nil pnt) nest))
		 (setq depth (1+ depth))))
	      (goto-char pnt))
	     (t
	      (error (format "bad string %s"
			     (buffer-substring (point) pnt)
			     )))))))
      (list in-string (car nest) depth))))

(defun ruby-calculate-indent (&optional parse-start)
  (save-excursion
    (beginning-of-line)
    (let ((indent-point (point))
	  (case-fold-search nil)
	  state bol eol
	  (indent 0))
      (if parse-start
	  (goto-char parse-start)
	(ruby-beginning-of-defun)
	(setq parse-start (point)))
      (setq state (ruby-parse-region parse-start indent-point))
      (cond
       ((nth 0 state)			; within string
	(setq indent nil))		;  do nothing

       ((nth 1 state)			; in paren
	(goto-char (cdr (nth 1 state)))
	(setq indent
	      (if (and (eq (car (nth 1 state)) ?\( )
		       (not (looking-at "(\\s *$")))
		  (current-column)
		(+ (current-indentation) ruby-indent-level))))

       ((> (nth 2 state) 0)		; in nest
	(goto-char (cdr (nth 1 state)))
	(forward-word -1)		; skip back a keyword
	(setq indent (+ (current-column) ruby-indent-level)))

       (t				; toplevel
	(setq indent 0)))

      (cond
       (indent
	(goto-char indent-point)
	(end-of-line)
	(setq eol (point))
	(beginning-of-line)
	(cond 
	 ((re-search-forward ruby-negative eol t)
	  (setq indent (- indent ruby-indent-level)))
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
	  (beginning-of-line)
	  (skip-chars-backward " \t\n")
	  (beginning-of-line)		; goto beginning of non-empty line
	  (setq bol (point))
	  (end-of-line)
	  (setq eol (point))
	  (and (search-backward "#" bol t) ; check for comment line
	       (not (eq ?? (char-after (1- (point)))))
	       (not (nth 0 (ruby-parse-region parse-start (point))))
	       (setq eol (point)))
	  (goto-char eol)
	  (skip-chars-backward " \t")
	  (or (bobp) (forward-char -1))
	  (and (looking-at ruby-operator-chars)
;;	       (or (not (eq ?/ (char-after (point))))
;;		   (progn
;;		     (not (nth 0 (ruby-parse-region parse-start (point))))))
	       (or (not (eq ?/ (char-after (point))))
		   (null (nth 0 (ruby-parse-region parse-start (point)))))
	       (save-excursion
		 (goto-char parse-start)
		 (sit-for 1))
	       (not (eq (char-after (1- (point))) ?$))
	       (or (not (eq ?| (char-after (point))))
		   (save-excursion
		     (or (eolp) (forward-char -1))
		     (and (search-backward "|" bol t)
			  (skip-chars-backward " \t\n")
			  (and (not (eolp))
			       (progn
				 (forward-char -1)
				 (not (looking-at "\\{")))))))
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

(defun ruby-end-of-defun (&optional arg)
  "Move forward to next end of defun.
An end of a defun is found by moving forward from the beginning of one."
  (interactive "p")
  (and (re-search-forward (concat "^\\(" ruby-block-end-re "\\)\\b")
			  nil 'move (or arg 1))
       (progn (beginning-of-line) t))
  (forward-line 1))

(defun ruby-reindent-then-newline-and-indent ()
  (interactive "*")
  (save-excursion
    (delete-region (point) (progn (skip-chars-backward " \t") (point))))
  (newline)
  (save-excursion
    (forward-line -1)
    (indent-according-to-mode))
  (indent-according-to-mode))

(defun ruby-encomment-region (beg end)
  (interactive "r")
  (save-excursion
    (goto-char beg)
    (while (re-search-forward "^" end t)
      (replace-match "#" nil nil))))

(defun ruby-decomment-region (beg end)
  (interactive "r")
  (save-excursion
    (goto-char beg)
    (while (re-search-forward "^\\([ \t]*\\)#" end t)
      (replace-match "\\1" nil nil))))

(if (featurep 'hilit19)
    (hilit-set-mode-patterns
     'ruby-mode
     '(("\\s #.*$" nil comment)
       ("^#.*$" nil comment)
       ("\\$\\(.\\|\\sw+\\)" nil type)
       ("[^$\\?]\\(\"[^\\\"]*\\(\\\\\\(.\\|\n\\)[^\\\"]*\\)*\"\\)" 1 string)
       ("[^$\\?]\\('[^\\']*\\(\\\\\\(.\\|\n\\)[^\\']*\\)*'\\)" 1 string)
       ("^/\\([^/\n]\\|\\\\/\\)*/" nil string)
       ("[^a-zA-Z_]\\s *\\(/\\([^/\n]\\|\\\\/\\)*/\\)" 1 string)
       ("\\(begin\\|case\\|else\\|elsif\\|end\\|ensure\\|for\\|if\\|rescue\\|then\\|when\\|while\\)\\s *\\(/\\([^/\n]\\|\\\\/\\)*/\\)" 2 string)
       ("^\\s *require.*$" nil include)
       ("^\\s *load.*$" nil include)
       ("^\\s *\\(include\\|alias\\|undef\\).*$" nil decl)
       ("^\\s *\\<\\(class\\|def\\|module\\)\\>" "[)\n;]" defun)
       ("[^_]\\<\\(begin\\|case\\|else\\|elsif\\|end\\|ensure\\|for\\|if\\|rescue\\|then\\|when\\|while\\)\\>[^_]" 1 defun)
       ("[^_]\\<\\(and\\|break\\|continue\\|fail\\|in\\|not\\|or\\|redo\\|retry\\|return\\|super\\|yield\\)\\>[^_]" 1 keyword)
       ("[^_]\\<\\(self\\|nil\\|TRUE\\|FALSE\\|__LINE__\\|__FILE__\\)\\>[^_]" 1 define)
       ("$.[a-zA-Z_0-9]*" nil struct)
       ("@[a-zA-Z_0-9]+" nil struct)
       ("[^_]\\<[A-Z].[a-zA-Z_0-9]*" nil define)
       ("^__END__" nil label))))
