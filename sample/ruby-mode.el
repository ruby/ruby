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
  "else\\|elsif\\|when\\|resque\\|ensure"
  )

(defconst ruby-block-end-re "end")

(defconst ruby-delimiter
  (concat "[$/<(){}#\"'`]\\|\\[\\|\\]\\|\\b\\("
	  ruby-block-beg-re "\\|" ruby-block-end-re "\\)\\b")
  )

(defconst ruby-negative
  (concat "^[ \t]*\\(\\b\\(" ruby-block-mid-re "\\)\\|\\("
	  ruby-block-end-re "\\)\\b\\|\\}\\|\\]\\)")
  )

(defvar ruby-mode-abbrev-table nil
  "Abbrev table in use in ruby-mode buffers.")

(define-abbrev-table 'ruby-mode-abbrev-table ())

(defvar ruby-mode-map nil "Keymap used in ruby mode.")

(if ruby-mode-map
    nil
  (setq ruby-mode-map (make-sparse-keymap))
  (define-key ruby-mode-map "\e\C-a" 'ruby-beginning-of-defun)
  (define-key ruby-mode-map "\e\C-e" 'ruby-end-of-defun)
  (define-key ruby-mode-map "\t" 'ruby-indent-command)
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
;;(modify-syntax-entry ?\n ">" ruby-mode-syntax-table)
;;(modify-syntax-entry ?\f ">" ruby-mode-syntax-table)
  (modify-syntax-entry ?# "<" ruby-mode-syntax-table)
  (modify-syntax-entry ?$ "/" ruby-mode-syntax-table)
  (modify-syntax-entry ?\\ "'" ruby-mode-syntax-table)
  (modify-syntax-entry ?_ "w" ruby-mode-syntax-table)
  (modify-syntax-entry ?< "." ruby-mode-syntax-table)
  (modify-syntax-entry ?> "." ruby-mode-syntax-table)
  (modify-syntax-entry ?& "." ruby-mode-syntax-table)
  (modify-syntax-entry ?| "." ruby-mode-syntax-table)
  (modify-syntax-entry ?$ "." ruby-mode-syntax-table)
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
      (while (and (> indent-point (point))
		  (re-search-forward ruby-delimiter indent-point t))
	(let ((w (buffer-substring (match-beginning 0) (match-end 0)))
	      (pnt (match-beginning 0)))
	  (cond
	   ((or (string= "\"" w)	;skip string
		(string= "'" w)
		(string= "`" w))
	    (cond 
	     ((string= w (char-to-string (char-after (point))))
	      (forward-char 1))
	     ((re-search-forward (format "[^\\]%s" w) indent-point t)
		nil)
	     (t
	      (goto-char indent-point)
	      (setq in-string t))))
	   ((or (string= "/" w)
		(string= "<" w))
	    (if (string= "<" w) (setq w ">"))
	    (let (c)
	      (save-excursion
		(goto-char pnt)
		(skip-chars-backward " \t")
		(setq c (char-after (1- (point))))
		(if c
		    (setq c (char-syntax c))))
	      (cond
	       ((or (eq c ?.)
		    (and (eq c ?w)
			 (save-excursion
			   (forward-word -1)
			   (or 
			    (looking-at ruby-block-beg-re)
			    (looking-at ruby-block-mid-re)))))
		(if (search-forward w indent-point t)
		    nil
		  (goto-char indent-point)
		  (setq in-string t))))))
	   ((string= "$" w)		;skip $char
	    (forward-char 1))
	   ((string= "#" w)		;skip comment
	    (forward-line 1))
	   ((string= "(" w)		;skip to matching paren
	    (let ((orig depth))
	      (setq nest (cons (point) nest))
	      (setq depth (1+ depth))
	      (while (and (/= depth orig)
			  (re-search-forward "[()]" indent-point t))
		(cond
		 ((= (char-after (match-beginning 0)) ?\( )
		  (setq nest (cons (point) nest))
		  (setq depth (1+ depth)))
		 (t
		  (setq nest (cdr nest))
		  (setq depth (1- depth)))))
	      (if (> depth orig) (setq in-paren ?\())))
	   ((string= "[" w)		;skip to matching paren
	    (let ((orig depth))
	      (setq nest (cons (point) nest))
	      (setq depth (1+ depth))
	      (while (and (/= depth orig)
			  (re-search-forward "\\[\\|\\]" indent-point t))
		(cond
		 ((= (char-after (match-beginning 0)) ?\[ )
		  (setq nest (cons (point) nest))
		  (setq depth (1+ depth)))
		 (t
		  (setq nest (cdr nest))
		  (setq depth (1- depth)))))
	      (if (> depth orig) (setq in-paren ?\[))))
	   ((string= "{" w)		;skip to matching paren
	    (let ((orig depth))
	      (setq nest (cons (point) nest))
	      (setq depth (1+ depth))
	      (while (and (/= depth orig)
			  (re-search-forward "[{}]" indent-point t))
		(cond
		 ((= (char-after (match-beginning 0)) ?{ )
		  (setq nest (cons (point) nest))
		  (setq depth (1+ depth)))
		 (t
		  (setq nest (cdr nest))
		  (setq depth (1- depth)))))
	      (if (> depth orig) (setq in-paren ?{))))
	   ((string-match ruby-block-end-re w)
	    (setq nest (cdr nest))
	    (setq depth (1- depth)))
	   ((string-match ruby-block-beg-re w)
	    (let (c)
	      (save-excursion
		(goto-char pnt)
		(skip-chars-backward " \t")
		(setq c (char-after (1- (point)))))
	      (if (or (null c) (= c ?\n) (= c ?\;))
		  (progn
		    (setq nest (cons (point) nest))
		    (setq depth (1+ depth))))))
	   (t
	    (error (format "bad string %s" w)))))))
    (list in-string in-paren (car nest) depth)))

(defun ruby-calculate-indent (&optional parse-start)
  (save-excursion
    (beginning-of-line)
    (let ((indent-point (point))
	  (case-fold-search nil)
	  state eol
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
	(goto-char (nth 2 state))
	(setq indent
	      (if (and (eq (nth 1 state) ?\( ) (not (looking-at "$")))
		  (current-column)
		(+ (current-indentation) ruby-indent-level))))

       ((> (nth 3 state) 0)		; in nest
	(goto-char (nth 2 state))
	(forward-word -1)		; skip back a keyword
	(setq indent (+ (current-column) ruby-indent-level)))

       (t				; toplevel
	(setq indent 0)))
      (goto-char indent-point)
      (end-of-line)
      (setq eol (point))
      (beginning-of-line)
      (if (re-search-forward ruby-negative eol t)
	  (setq indent (- indent ruby-indent-level)))
      indent)))

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
  (insert ?\n)
  (save-excursion
    (forward-line -1)
    (indent-according-to-mode)
    (end-of-line)
    (delete-region (point) (progn (skip-chars-backward " \t") (point))))
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
