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

(defconst ruby-non-block-do-re
  "\\(while\\|until\\|for\\|rescue\\)\\>"
  )

(defconst ruby-indent-beg-re
  "\\(\\s *\\(class\\|module\\|def\\)\\)\\|if\\|unless\\|case\\|while\\|until\\|for\\|begin"
    )

(defconst ruby-modifier-beg-re
  "if\\|unless\\|while\\|until"
  )

(defconst ruby-modifier-re
  (concat ruby-modifier-beg-re "\\|rescue")
  )

(defconst ruby-block-mid-re
  "then\\|else\\|elsif\\|when\\|rescue\\|ensure"
  )

(defconst ruby-block-op-re
  "and\\|or\\|not"
  )

(defconst ruby-block-hanging-re
  (concat ruby-modifier-beg-re "\\|" ruby-block-op-re)
  )

(defconst ruby-block-end-re "end")

(defconst ruby-delimiter
  (concat "[?$/%(){}#\"'`.:]\\|<<\\|\\[\\|\\]\\|\\<\\("
	  ruby-block-beg-re
	  "\\|" ruby-block-end-re
	  "\\)\\>\\|^=begin")
  )

(defconst ruby-negative
  (concat "^[ \t]*\\(\\(" ruby-block-mid-re "\\)\\>\\|\\("
	    ruby-block-end-re "\\)\\>\\|}\\|\\]\\)")
  )

(defconst ruby-operator-chars "-,.+*/%&|^~=<>:")
(defconst ruby-operator-re (concat "[" ruby-operator-chars "]"))

(defconst ruby-symbol-chars "a-zA-Z0-9_")
(defconst ruby-symbol-re (concat "[" ruby-symbol-chars "]"))

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
  (define-key ruby-mode-map "\e\C-h" 'ruby-mark-defun)
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
  (modify-syntax-entry ?\\ "\\" ruby-mode-syntax-table)
  (modify-syntax-entry ?$ "." ruby-mode-syntax-table)
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

(defvar ruby-deep-arglist t
  "*Deep indent argument lists when non-nil.
Also ignores spaces after parenthesis when 'space.")

(eval-when-compile (require 'cl))
(defun ruby-imenu-create-index-in-block (prefix beg end)
  (let ((index-alist '()) (nest '()) (case-fold-search nil)
	name next pos decl sing)
    (goto-char beg)
    (while (re-search-forward "^\\s *\\(\\(class\\>\\(\\s *<<\\)?\\|module\\>\\)\\s *\\([^\(<\n ]+\\)\\|\\(def\\|alias\\)\\>\\s *\\([^\(\n ]+\\)\\)" end t)
      (setq sing (match-beginning 3))
      (setq decl (match-string 5))
      (setq next (match-end 0))
      (setq name (or (match-string 4) (match-string 6)))
      (setq pos (match-beginning 0))
      (cond
       ((string= "alias" decl)
	(if prefix (setq name (concat prefix name)))
	(push (cons name pos) index-alist))
       ((string= "def" decl)
	(if prefix
	    (setq name
		  (cond
		   ((string-match "^self\." name)
		    (concat (substring prefix 0 -1) (substring name 4)))
		  (t (concat prefix name)))))
	(push (cons name pos) index-alist)
	(ruby-accurate-end-of-block end))
       (t
	(if (string= "self" name)
	    (if prefix (setq name (substring prefix 0 -1)))
	  (if prefix (setq name (concat (substring prefix 0 -1) "::" name)))
	  (push (cons name pos) index-alist))
	(ruby-accurate-end-of-block end)
	(setq beg (point))
	(setq index-alist
	      (nconc (ruby-imenu-create-index-in-block
		      (concat name (if sing "." "#"))
		      next beg) index-alist))
	(goto-char beg))))
    index-alist))

(defun ruby-imenu-create-index ()
  (nreverse (ruby-imenu-create-index-in-block nil (point-min) nil)))

(defun ruby-accurate-end-of-block (&optional end)
  (let (state)
    (or end (setq end (point-max)))
    (while (and (setq state (apply 'ruby-parse-partial end state))
		(>= (nth 2 state) 0) (< (point) end)))))

(defun ruby-mode-variables ()
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
  (make-local-variable 'paragraph-start)
  (setq paragraph-start (concat "$\\|" page-delimiter))
  (make-local-variable 'paragraph-separate)
  (setq paragraph-separate paragraph-start)
  (make-local-variable 'paragraph-ignore-fill-prefix)
  (setq paragraph-ignore-fill-prefix t))

;;;###autoload
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
  (setq mode-name "Ruby")
  (setq major-mode 'ruby-mode)
  (ruby-mode-variables)

  (make-local-variable 'imenu-create-index-function)
  (setq imenu-create-index-function 'ruby-imenu-create-index)

  (make-local-variable 'add-log-current-defun-function)
  (setq add-log-current-defun-function 'ruby-add-log-current-method)

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
	(and (< x 0) (error "invalid nest"))
	(setq shift (current-column))
	(beginning-of-line)
	(setq beg (point))
	(back-to-indentation)
	(setq top (current-column))
	(skip-chars-backward " \t")
	(if (>= shift top) (setq shift (- shift top))
	  (setq shift 0))
	(if (and (bolp)
		 (= x top))
	    (move-to-column (+ x shift))
	  (move-to-column top)
	  (delete-region beg (point))
	  (beginning-of-line)
	  (indent-to x)
	  (move-to-column (+ x shift))))))

(defun ruby-expr-beg (&optional option)
  (save-excursion
    (store-match-data nil)
    (let ((space (skip-chars-backward " \t")))
      (cond
       ((bolp) t)
       ((looking-at "\\?")
	(or (bolp) (forward-char -1))
	(not (looking-at "\\sw")))
       (t
	(forward-char -1)
	(or (looking-at ruby-operator-re)
	    (looking-at "[\\[({,;]")
	    (and (or (not (eq option 'heredoc))
		     (< space 0))
		 (looking-at "[!?]")
		 (or (not (eq option 'modifier))
		     (bolp)
		     (save-excursion (forward-char -1) (looking-at "\\Sw"))))
	    (and (looking-at ruby-symbol-re)
		 (skip-chars-backward ruby-symbol-chars)
		 (cond
		  ((or (looking-at ruby-block-beg-re)
		       (looking-at ruby-block-op-re)
		       (looking-at ruby-block-mid-re))
		   (goto-char (match-end 0))
		   (looking-at "\\>"))
		  ((eq option 'expr-qstr)
		   (looking-at "[a-zA-Z][a-zA-z0-9_]* +%[^ \t]"))
		  ((eq option 'expr-re)
		   (looking-at "[a-zA-Z][a-zA-z0-9_]* +/[^ \t]"))
		  (t nil)))))))))

(defun ruby-forward-string (term &optional end no-error expand)
  (let ((n 1) (c (string-to-char term))
	(re (if expand
		(concat "[^\\]\\(\\\\\\\\\\)*\\([" term "]\\|\\(#{\\)\\)")
	      (concat "[^\\]\\(\\\\\\\\\\)*[" term "]"))))
    (while (and (re-search-forward re end no-error)
		(if (match-beginning 3)
		    (ruby-forward-string "}{" end no-error nil)
		  (> (setq n (if (eq (char-before (point)) c)
				     (1- n) (1+ n))) 0)))
      (forward-char -1))
    (cond ((zerop n))
	  (no-error nil)
	  (error "unterminated string"))))

(defun ruby-parse-partial (&optional end in-string nest depth pcol indent)
  (or depth (setq depth 0))
  (or indent (setq indent 0))
  (when (re-search-forward ruby-delimiter end 'move)
    (let ((pnt (point)) w re expand)
      (goto-char (match-beginning 0))
      (cond
       ((and (memq (char-before) '(?@ ?$)) (looking-at "\\sw"))
	(goto-char pnt))
       ((or (looking-at "\"")		;skip string
	    (looking-at "`"))
	(cond
	 ((and (not (eobp))
	       (ruby-forward-string (buffer-substring (point) (1+ (point))) end t t))
	  nil)
	 (t
	  (setq in-string (point))
	  (goto-char end))))
       ((looking-at "'")
	(cond
	 ((and (not (eobp))
	       (re-search-forward "[^\\]\\(\\\\\\\\\\)*'" end t))
	  nil)
	 (t
	  (setq in-string (point))
	  (goto-char end))))
       ((looking-at "/")
	(cond
	 ((and (not (eobp)) (ruby-expr-beg 'expr-re))
	  (if (ruby-forward-string "/" end t t)
	      nil
	    (setq in-string (point))
	    (goto-char end)))
	 (t
	  (goto-char pnt))))
       ((looking-at "%")
	(cond
	 ((and (not (eobp))
	       (ruby-expr-beg 'expr-qstr)
	       (not (looking-at "%="))
	       (looking-at "%[QqrxWw]?\\(.\\)"))
	  (goto-char (match-beginning 1))
	  (setq expand (not (memq (char-before) '(?q ?w))))
	  (setq w (match-string 1))
	  (cond
	   ((string= w "[") (setq re "]["))
	   ((string= w "{") (setq re "}{"))
	   ((string= w "(") (setq re ")("))
	   ((string= w "<") (setq re "><"))
	   ((and expand (string= w "\\"))
	    (setq w (concat "\\" w))))
	  (unless (cond (re (ruby-forward-string re end t expand))
			(expand (ruby-forward-string w end t t))
			(t (re-search-forward
			    (if (string= w "\\")
				"\\\\[^\\]*\\\\"
			      (concat "[^\\]\\(\\\\\\\\\\)*" w))
			    end t)))
	    (setq in-string (point))
	    (goto-char end)))
	 (t
	  (goto-char pnt))))
       ((looking-at "\\?")		;skip ?char
	(cond
	 ((and (ruby-expr-beg)
	       (looking-at "?\\(\\\\C-\\|\\\\M-\\)*."))
	  (goto-char (match-end 0)))
	 (t
	  (goto-char pnt))))
       ((looking-at "\\$")		;skip $char
	(goto-char pnt)
	(forward-char 1))
       ((looking-at "#")		;skip comment
	(forward-line 1)
	(goto-char (point))
	)
       ((and (looking-at "(") ruby-deep-arglist)
	(and (eq ruby-deep-arglist 'space) (looking-at ".\\s +")
	     (setq pnt (match-end 0)))
	(setq nest (cons (cons (char-after (point)) pnt) nest))
	(setq pcol (cons (cons pnt depth) pcol))
	(setq depth 0)
	(goto-char pnt)
	)
       ((looking-at "[\\[{(]")
	(setq nest (cons (cons (char-after (point)) pnt) nest))
	(setq depth (1+ depth))
	(goto-char pnt)
	)
       ((and (looking-at ")") ruby-deep-arglist)
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
		       (setq w (char-after (point)))
		       (or (eq ?_ w)
			   (eq ?. w))))
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
       ((looking-at "def\\s +[^(\n;]*")
	(if (or (bolp)
		(progn
		  (forward-char -1)
		  (not (eq ?_ (char-after (point))))))
	    (progn
	      (setq nest (cons (cons nil pnt) nest))
	      (setq depth (1+ depth))))
	(goto-char (match-end 0)))
       ((looking-at ruby-block-beg-re)
	(and
	 (save-match-data
	   (or (not (looking-at "do\\>[^_]"))
	       (save-excursion
		 (back-to-indentation)
		 (not (looking-at ruby-non-block-do-re)))))
	 (or (bolp)
	     (progn
	       (forward-char -1)
	       (setq w (char-after (point)))
	       (not (or (eq ?_ w)
			(eq ?. w)))))
	 (goto-char pnt)
	 (setq w (char-after (point)))
	 (not (eq ?_ w))
	 (not (eq ?! w))
	 (not (eq ?? w))
	 (skip-chars-forward " \t")
	 (goto-char (match-beginning 0))
	 (or (not (looking-at ruby-modifier-re))
	     (ruby-expr-beg 'modifier))
	 (goto-char pnt)
	 (setq nest (cons (cons nil pnt) nest))
	 (setq depth (1+ depth)))
	(goto-char pnt))
       ((looking-at ":\\([a-zA-Z_][a-zA-Z_0-9]*\\)?")
	(goto-char (match-end 0)))
       ((or (looking-at "\\.\\.\\.?")
	    (looking-at "\\.[0-9]+")
	    (looking-at "\\.[a-zA-Z_0-9]+")
	    (looking-at "\\."))
	(goto-char (match-end 0)))
       ((looking-at "^=begin")
	(if (re-search-forward "^=end" end t)
	    (forward-line 1)
	  (setq in-string (match-end 0))
	  (goto-char end)))
       ((looking-at "<<")
	(cond
	 ((and (ruby-expr-beg 'heredoc)
	       (looking-at "<<\\(-\\)?\\(\\([\"'`]\\)\\([^\n]+?\\)\\3\\|\\sw+\\)"))
	  (setq re (regexp-quote (or (match-string 4) (match-string 2))))
	  (if (match-beginning 1) (setq re (concat "\\s *" re)))
	  (if (re-search-forward (concat "^" re "$") end 'move)
	      (forward-line 1)
	    (setq in-string (match-end 0))
	    (goto-char end)))
	 (t
	  (goto-char pnt))))
       ((looking-at "^__END__$")
	(goto-char pnt))
       (t
	(error (format "bad string %s"
		       (buffer-substring (point) pnt)
		       ))))))
  (list in-string nest depth pcol))

(defun ruby-parse-region (start end)
  (let (state)
    (save-excursion
      (if start
	  (goto-char start)
	(ruby-beginning-of-indent))
      (save-restriction
	(narrow-to-region (point) end)
	(while (and (> end (point))
		    (setq state (apply 'ruby-parse-partial end state))))))
    (list (nth 0 state)			; in-string
	  (car (nth 1 state))		; nest
	  (nth 2 state)			; depth
	  (car (car (nth 3 state)))	; pcol
	  ;(car (nth 5 state))		; indent
	  )))

(defun ruby-indent-size (pos nest)
  (+ pos (* (if nest nest 1) ruby-indent-level)))

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
	  (if (and (eq (car (nth 1 state)) ?\( ) ruby-deep-arglist)
	      (let ((column (current-column))
		    (s (ruby-parse-region (point) indent-point)))
		(cond
		 ((and (nth 2 s) (> (nth 2 s) 0))
		  (goto-char (cdr (nth 1 s)))
		  (forward-word -1)
		  (setq indent (ruby-indent-size (current-column) (nth 2 state))))
		 (t
		  (setq indent (current-column)))))
	    (cond
	     ((nth 3 state)
	      (goto-char (nth 3 state))
	      (setq indent (ruby-indent-size (current-column) (nth 2 state))))
	     (t
	      (goto-char parse-start)
	      (back-to-indentation)
	      (setq indent (ruby-indent-size (current-column) (nth 2 state)))))
	    ))
	 ((and (nth 2 state)(> (nth 2 state) 0)) ; in nest
	  (if (null (cdr (nth 1 state)))
	      (error "invalid nest"))
	  (goto-char (cdr (nth 1 state)))
	  (forward-word -1)		; skip back a keyword
	  (cond
	   ((looking-at "do\\>[^_]")	; iter block is a special case
	    (cond
	     ((nth 3 state)
	      (goto-char (nth 3 state))
	      (setq indent (ruby-indent-size (current-column) (nth 2 state))))
	     (t
	      (goto-char parse-start)
	      (back-to-indentation)
	      (setq indent (ruby-indent-size (current-column) (nth 2 state))))))
	   (t
	    (setq indent (+ (current-column) ruby-indent-level)))))

	 ((and (nth 2 state) (< (nth 2 state) 0)) ; in negative nest
	  (setq indent (ruby-indent-size (current-column) (nth 2 state)))))

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
	    (let ((pos (point)))
	      (while (and (re-search-backward "#" bol t)
			  (eq (char-before) ??))
		(forward-char -1))
	      (skip-chars-backward " \t")
	      (and
	       (setq state (ruby-parse-region parse-start (point)))
	       (nth 0 state)
	       (goto-char pos)))
	    (or (bobp) (forward-char -1))
	    (and
	     (or (and (looking-at ruby-symbol-re)
		      (skip-chars-backward ruby-symbol-chars)
		      (looking-at ruby-block-hanging-re)
		      (not (eq (point) (nth 3 state)))
		      (save-excursion
			(goto-char (match-end 0))
			(not (looking-at "[a-z_]"))))
		 (and (looking-at ruby-operator-re)
		      (not (eq (char-after (1- (point))) ??))
		      (not (eq (char-after (1- (point))) ?$))
		      (or (not (eq ?/ (char-after (point))))
			  (null (nth 0 (ruby-parse-region parse-start (point)))))
		      (or (not (eq ?| (char-after (point))))
			  (save-excursion
			    (or (eolp) (forward-char -1))
			    (cond
			     ((search-backward "|" nil t)
			      (skip-chars-backward " \t\n")
			      (and (not (eolp))
				   (progn
				     (forward-char -1)
				     (not (looking-at "{")))
				   (progn
				     (forward-word -1)
				     (not (looking-at "do\\>[^_]")))))
			     (t t))))))
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
  (and (re-search-forward (concat "^\\(" ruby-block-end-re "\\)\\($\\|\\b[^_]\\)")
			  nil 'move (or arg 1))
       (progn (beginning-of-line) t))
  (forward-line 1))

(defun ruby-move-to-block (n)
  (let (start pos done down)
    (setq start (ruby-calculate-indent))
    (setq down (looking-at (if (< n 0) ruby-block-end-re ruby-block-beg-re)))
    (while (and (not done) (not (if (< n 0) (bobp) (eobp))))
      (forward-line n)
      (cond
       ((looking-at "^\\s *$"))
       ((looking-at "^\\s *#"))
       ((and (> n 0) (looking-at "^=begin\\>"))
	(re-search-forward "^=end\\>"))
       ((and (< n 0) (looking-at "^=end\\>"))
	(re-search-backward "^=begin\\>"))
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
		(setq done nil))))))
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
  (newline)
  (save-excursion
    (end-of-line 0)
    (indent-according-to-mode)
    (delete-region (point) (progn (skip-chars-backward " \t") (point))))
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

(defun ruby-mark-defun ()
  "Put mark at end of this Ruby function, point at beginning."
  (interactive)
  (push-mark (point))
  (ruby-end-of-defun)
  (push-mark (point) nil t)
  (ruby-beginning-of-defun)
  (re-search-backward "^\n" (- (point) 1) t))

(defun ruby-add-log-current-method ()
  "Return current method string."
  (condition-case nil
      (save-excursion
	(let ((mlist nil) (indent 0))
	  ;; get current method (or class/module)
	  (if (re-search-backward
	       (concat "^[ \t]*\\(def\\|class\\|module\\)[ \t]+"
		       "\\(" ruby-symbol-re "+\\)")
	       nil t)
	      (progn
		(setq mlist (list (match-string 2)))
		(goto-char (match-beginning 1))
		(setq indent (current-column))
		(beginning-of-line)))
	  ;; nest class/module
	  (while (and (> indent 0)
		      (re-search-backward
		       (concat
			"^[ \t]*\\(class\\|module\\)[ \t]+"
			"\\([A-Z]" ruby-symbol-re "+\\)")
		       nil t))
	    (goto-char (match-beginning 1))
	    (if (< (current-column) indent)
		(progn
		  (setq mlist (cons (match-string 2) mlist))
		  (setq indent (current-column))
		  (beginning-of-line))))
	  ;; generate string
	  (if (consp mlist)
	      (mapconcat (function identity) mlist "::")
	    nil)))))

(cond
 ((featurep 'font-lock)
  (or (boundp 'font-lock-variable-name-face)
      (setq font-lock-variable-name-face font-lock-type-face))

  (setq ruby-font-lock-syntactic-keywords
	'(
	  ;; #{ }, #$hoge, #@foo are not comments
	  ("\\(#\\)[{$@]" 1 (1 . nil))
	  ;; the last $' in the string ,'...$' is not variable
	  ;; the last ?' in the string ,'...?' is not ascii code
	  ("\\(^\\|[[\\s <+(,=]\\)\\('\\)[^'\n\\\\]*\\(\\\\.[^'\n\\\\]*\\)*[?$]\\('\\)"
	   (2 (7 . nil))
	   (4 (7 . nil)))
	  ;; the last $` in the string ,`...$` is not variable
	  ;; the last ?` in the string ,`...?` is not ascii code
	  ("\\(^\\|[[\\s <+(,=]\\)\\(`\\)[^`\n\\\\]*\\(\\\\.[^`\n\\\\]*\\)*[?$]\\(`\\)"
	   (2 (7 . nil))
	   (4 (7 . nil)))
	  ;; the last $" in the string ,"...$" is not variable
	  ;; the last ?" in the string ,"...?" is not ascii code
	  ("\\(^\\|[[\\s <+(,=]\\)\\(\"\\)[^\"\n\\\\]*\\(\\\\.[^\"\n\\\\]*\\)*[?$]\\(\"\\)"
	   (2 (7 . nil))
	   (4 (7 . nil)))
	  ;; $' $" $` .... are variables
	  ;; ?' ?" ?` are ascii codes
	  ("[?$][#\"'`]" 0 (1 . nil))
	  ;; regexps
	  ("\\(^\\|[=(,~?:;]\\|\\(^\\|\\s \\)\\(if\\|elsif\\|unless\\|while\\|until\\|when\\|and\\|or\\|&&\\|||\\)\\|g?sub!?\\|scan\\|split!?\\)\\s *\\(/\\)[^/\n\\\\]*\\(\\\\.[^/\n\\\\]*\\)*\\(/\\)"
	   (4 (7 . ?/))
	   (6 (7 . ?/)))
	  ;; %Q!...!
	  ("\\(^\\|[[\\s <+(,=]\\)%[xrqQ]?\\([^a-zA-Z0-9 \n]\\)[^\n\\\\]*\\(\\\\.[^\n\\\\]*\\)*\\(\\2\\)"
	   (2 (7 . nil))
	   (4 (7 . nil)))
	  ("^\\(=\\)begin\\(\\s \\|$\\)" 1 (7 . nil))
	  ("^\\(=\\)end\\(\\s \\|$\\)" 1 (7 . nil))))

  (cond ((featurep 'xemacs)
	 (put 'ruby-mode 'font-lock-defaults
	      '((ruby-font-lock-keywords)
		nil nil nil
		beginning-of-line
		(font-lock-syntactic-keywords
		 . ruby-font-lock-syntactic-keywords))))
	(t
	 (add-hook 'ruby-mode-hook
	    '(lambda ()
	       (make-local-variable 'font-lock-defaults)
	       (make-local-variable 'font-lock-keywords)
	       (make-local-variable 'font-lock-syntax-table)
	       (make-local-variable 'font-lock-syntactic-keywords)
	       (setq font-lock-defaults '((ruby-font-lock-keywords) nil nil))
	       (setq font-lock-keywords ruby-font-lock-keywords)
	       (setq font-lock-syntax-table ruby-font-lock-syntax-table)
	       (setq font-lock-syntactic-keywords ruby-font-lock-syntactic-keywords)))))

  (defun ruby-font-lock-docs (limit)
    (if (re-search-forward "^=begin\\(\\s \\|$\\)" limit t)
	(let (beg)
	  (beginning-of-line)
	  (setq beg (point))
	  (forward-line 1)
	  (if (re-search-forward "^=end\\(\\s \\|$\\)" limit t)
	      (progn
		(set-match-data (list beg (point)))
		t)))))

  (defun ruby-font-lock-maybe-docs (limit)
    (let (beg)
      (save-excursion
	(if (and (re-search-backward "^=\\(begin\\|end\\)\\(\\s \\|$\\)" nil t)
		 (string= (match-string 1) "begin"))
	    (progn
	      (beginning-of-line)
	      (setq beg (point)))))
      (if (and beg (and (re-search-forward "^=\\(begin\\|end\\)\\(\\s \\|$\\)" nil t)
			(string= (match-string 1) "end")))
	  (progn
	    (set-match-data (list beg (point)))
	    t)
	nil)))

  (defvar ruby-font-lock-syntax-table
    (let* ((tbl (copy-syntax-table ruby-mode-syntax-table)))
      (modify-syntax-entry ?_ "w" tbl)
      tbl))

  (defvar ruby-font-lock-keywords
    (list
     ;; functions
     '("^\\s *def\\s +\\([^( ]+\\)"
       1 font-lock-function-name-face)
     ;; keywords
     (cons (concat
	    "\\(^\\|[^_:.@$]\\|\\.\\.\\)\\b\\("
	    (mapconcat
	     'identity
	     '("alias"
	       "and"
	       "begin"
	       "break"
	       "case"
	       "catch"
	       "class"
	       "def"
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
	       "throw"
	       "super"
	       "unless"
	       "undef"
	       "until"
	       "when"
	       "while"
	       "yield"
	       )
	     "\\|")
	    "\\)\\>")
	   2)
     ;; variables
     '("\\(^\\|[^_:.@$]\\|\\.\\.\\)\\b\\(nil\\|self\\|true\\|false\\)\\>"
       2 font-lock-variable-name-face)
     ;; variables
     '("\\(\\$\\([^a-zA-Z0-9 \n]\\|[0-9]\\)\\)\\W"
       1 font-lock-variable-name-face)
     '("\\(\\$\\|@\\|@@\\)\\(\\w\\|_\\)+"
       0 font-lock-variable-name-face)
     ;; embedded document
     '(ruby-font-lock-docs
       0 font-lock-comment-face t)
     '(ruby-font-lock-maybe-docs
       0 font-lock-comment-face t)
     ;; constants
     '("\\(^\\|[^_]\\)\\b\\([A-Z]+\\(\\w\\|_\\)*\\)"
       2 font-lock-type-face)
     ;; symbols
     '("\\(^\\|[^:]\\)\\(:\\([-+~]@?\\|[/%&|^`]\\|\\*\\*?\\|<\\(<\\|=>?\\)?\\|>[>=]?\\|===?\\|=~\\|\\[\\]=?\\|\\(\\w\\|_\\)+\\([!?=]\\|\\b_*\\)\\|#{[^}\n\\\\]*\\(\\\\.[^}\n\\\\]*\\)*}\\)\\)"
       2 font-lock-reference-face)
     ;; expression expansion
     '("#\\({[^}\n\\\\]*\\(\\\\.[^}\n\\\\]*\\)*}\\|\\(\\$\\|@\\|@@\\)\\(\\w\\|_\\)+\\)"
       0 font-lock-variable-name-face t))
    "*Additional expressions to highlight in ruby mode."))

 ((featurep 'hilit19)
  (hilit-set-mode-patterns
   'ruby-mode
   '(("[^$\\?]\\(\"[^\\\"]*\\(\\\\\\(.\\|\n\\)[^\\\"]*\\)*\"\\)" 1 string)
     ("[^$\\?]\\('[^\\']*\\(\\\\\\(.\\|\n\\)[^\\']*\\)*'\\)" 1 string)
     ("[^$\\?]\\(`[^\\`]*\\(\\\\\\(.\\|\n\\)[^\\`]*\\)*`\\)" 1 string)
     ("^\\s *#.*$" nil comment)
     ("[^$@?\\]\\(#[^$@{\n].*$\\)" 1 comment)
     ("[^a-zA-Z_]\\(\\?\\(\\\\[CM]-\\)*.\\)" 1 string)
     ("^\\s *\\(require\\|load\\).*$" nil include)
     ("^\\s *\\(include\\|alias\\|undef\\).*$" nil decl)
     ("^\\s *\\<\\(class\\|def\\|module\\)\\>" "[)\n;]" defun)
     ("[^_]\\<\\(begin\\|case\\|else\\|elsif\\|end\\|ensure\\|for\\|if\\|unless\\|rescue\\|then\\|when\\|while\\|until\\|do\\|yield\\)\\>\\([^_]\\|$\\)" 1 defun)
     ("[^_]\\<\\(and\\|break\\|next\\|raise\\|fail\\|in\\|not\\|or\\|redo\\|retry\\|return\\|super\\|yield\\|catch\\|throw\\|self\\|nil\\)\\>\\([^_]\\|$\\)" 1 keyword)
     ("\\$\\(.\\|\\sw+\\)" nil type)
     ("[$@].[a-zA-Z_0-9]*" nil struct)
     ("^__END__" nil label))))
 )


(provide 'ruby-mode)
