;;;
;;;  ruby-mode.el -
;;;
;;;  $Author: matz $
;;;  $Date: 2007/01/24 14:46:10 $
;;;  created at: Fri Feb  4 14:49:13 JST 1994
;;;

(defconst ruby-mode-revision "$Revision: 1.74.2.14.2.1 $")

(defconst ruby-mode-version
  (progn
   (string-match "[0-9.]+" ruby-mode-revision)
   (substring ruby-mode-revision (match-beginning 0) (match-end 0))))

(defconst ruby-block-beg-re
  "class\\|module\\|def\\|if\\|unless\\|case\\|while\\|until\\|for\\|begin\\|do"
  )

(defconst ruby-non-block-do-re
  "\\(while\\|until\\|for\\|rescue\\)\\>[^_]"
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

(defconst ruby-block-end-re "\\<end\\>")

(defconst ruby-here-doc-beg-re
  "<<\\(-\\)?\\(\\([a-zA-Z0-9_]+\\)\\|[\"]\\([^\"]+\\)[\"]\\|[']\\([^']+\\)[']\\)")

(defun ruby-here-doc-end-match ()
  (concat "^"
	  (if (match-string 1) "[ \t]*" nil)
	  (regexp-quote
	   (or (match-string 3)
	       (match-string 4)
	       (match-string 5)))))

(defconst ruby-delimiter
  (concat "[?$/%(){}#\"'`.:]\\|<<\\|\\[\\|\\]\\|\\<\\("
	  ruby-block-beg-re
	  "\\)\\>\\|" ruby-block-end-re
	  "\\|^=begin\\|" ruby-here-doc-beg-re)
  )

(defconst ruby-negative
  (concat "^[ \t]*\\(\\(" ruby-block-mid-re "\\)\\>\\|"
	    ruby-block-end-re "\\|}\\|\\]\\)")
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
  (define-key ruby-mode-map "\e\C-b" 'ruby-backward-sexp)
  (define-key ruby-mode-map "\e\C-f" 'ruby-forward-sexp)
  (define-key ruby-mode-map "\e\C-p" 'ruby-beginning-of-block)
  (define-key ruby-mode-map "\e\C-n" 'ruby-end-of-block)
  (define-key ruby-mode-map "\e\C-h" 'ruby-mark-defun)
  (define-key ruby-mode-map "\e\C-q" 'ruby-indent-exp)
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

(defcustom ruby-indent-tabs-mode nil
  "*Indentation can insert tabs in ruby mode if this is non-nil."
  :type 'boolean :group 'ruby)

(defcustom ruby-indent-level 2
  "*Indentation of ruby statements."
  :type 'integer :group 'ruby)

(defcustom ruby-comment-column 32
  "*Indentation column of comments."
  :type 'integer :group 'ruby)

(defcustom ruby-deep-arglist t
  "*Deep indent lists in parenthesis when non-nil.
Also ignores spaces after parenthesis when 'space."
  :group 'ruby)

(defcustom ruby-deep-indent-paren '(?\( ?\[ ?\] t)
  "*Deep indent lists in parenthesis when non-nil. t means continuous line.
Also ignores spaces after parenthesis when 'space."
  :group 'ruby)

(defcustom ruby-deep-indent-paren-style 'space
  "Default deep indent style."
  :options '(t nil space) :group 'ruby)

(eval-when-compile (require 'cl))
(defun ruby-imenu-create-index-in-block (prefix beg end)
  (let ((index-alist '()) (case-fold-search nil)
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
  (setq comment-column ruby-comment-column)
  (make-variable-buffer-local 'comment-start-skip)
  (setq comment-start-skip "#+ *")
  (setq indent-tabs-mode ruby-indent-tabs-mode)
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

(defun ruby-special-char-p (&optional pnt)
  (setq pnt (or pnt (point)))
  (let ((c (char-before pnt)) (b (and (< (point-min) pnt) (char-before (1- pnt)))))
    (cond ((or (eq c ??) (eq c ?$)))
	  ((and (eq c ?:) (or (not b) (eq (char-syntax b) ? ))))
	  ((eq c ?\\) (eq b ??)))))

(defun ruby-expr-beg (&optional option)
  (save-excursion
    (store-match-data nil)
    (let ((space (skip-chars-backward " \t"))
	  (start (point)))
      (cond
       ((bolp) t)
       ((progn
	  (forward-char -1)
	  (and (looking-at "\\?")
	       (or (eq (char-syntax (char-before (point))) ?w)
		   (ruby-special-char-p))))
	nil)
       ((and (eq option 'heredoc) (< space 0)) t)
       ((or (looking-at ruby-operator-re)
	    (looking-at "[\\[({,;]")
	    (and (looking-at "[!?]")
		 (or (not (eq option 'modifier))
		     (bolp)
		     (save-excursion (forward-char -1) (looking-at "\\Sw$"))))
	    (and (looking-at ruby-symbol-re)
		 (skip-chars-backward ruby-symbol-chars)
		 (cond
		  ((or (looking-at (concat "\\<\\(" ruby-block-beg-re
					   "|" ruby-block-op-re
					   "|" ruby-block-mid-re "\\)\\>")))
		   (goto-char (match-end 0))
		   (not (looking-at "\\s_")))
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
	  ((error "unterminated string")))))

(defun ruby-deep-indent-paren-p (c)
  (cond ((listp ruby-deep-indent-paren)
	 (let ((deep (assoc c ruby-deep-indent-paren)))
	   (cond (deep
		  (or (cdr deep) ruby-deep-indent-paren-style))
		 ((memq c ruby-deep-indent-paren)
		  ruby-deep-indent-paren-style))))
	((eq c ruby-deep-indent-paren) ruby-deep-indent-paren-style)
	((eq c ?\( ) ruby-deep-arglist)))

(defun ruby-parse-partial (&optional end in-string nest depth pcol indent)
  (or depth (setq depth 0))
  (or indent (setq indent 0))
  (when (re-search-forward ruby-delimiter end 'move)
    (let ((pnt (point)) w re expand)
      (goto-char (match-beginning 0))
      (cond
       ((and (memq (char-before) '(?@ ?$)) (looking-at "\\sw"))
	(goto-char pnt))
       ((looking-at "[\"`]")		;skip string
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
	       (looking-at "%[QqrxWw]?\\([^a-zA-Z0-9 \t\n]\\)"))
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
	       (looking-at "?\\(\\\\C-\\|\\\\M-\\)*\\\\?."))
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
       ((looking-at "[\\[{(]")
	(let ((deep (ruby-deep-indent-paren-p (char-after))))
	  (if (and deep (or (not (eq (char-after) ?\{)) (ruby-expr-beg)))
	      (progn
		(and (eq deep 'space) (looking-at ".\\s +[^# \t\n]")
		     (setq pnt (1- (match-end 0))))
		(setq nest (cons (cons (char-after (point)) pnt) nest))
		(setq pcol (cons (cons pnt depth) pcol))
		(setq depth 0))
	    (setq nest (cons (cons (char-after (point)) pnt) nest))
	    (setq depth (1+ depth))))
	(goto-char pnt)
	)
       ((looking-at "[])}]")
	(if (ruby-deep-indent-paren-p (matching-paren (char-after)))
	    (setq depth (cdr (car pcol)) pcol (cdr pcol))
	  (setq depth (1- depth)))
	(setq nest (cdr nest))
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
       ((looking-at (concat "\\<\\(" ruby-block-beg-re "\\)\\>"))
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
       ((looking-at ":\\(['\"]\\)\\(\\\\.\\|[^\\\\]\\)*\\1")
	(goto-char (match-end 0)))
       ((looking-at ":\\([-,.+*/%&|^~<>]=?\\|===?\\|<=>\\)")
	(goto-char (match-end 0)))
       ((looking-at ":\\([a-zA-Z_][a-zA-Z_0-9]*[!?=]?\\)?")
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
	  (let* ((id-end (goto-char (match-end 0)))
		 (line-end-position (save-excursion (end-of-line) (point)))
		 (state (list in-string nest depth pcol indent)))
	    ;; parse the rest of the line
	    (while (and (> line-end-position (point))
			(setq state (apply 'ruby-parse-partial
					   line-end-position state))))
	    (setq in-string (car state)
		  nest (nth 1 state)
		  depth (nth 2 state)
		  pcol (nth 3 state)
		  indent (nth 4 state))
	    ;; skip heredoc section
	    (if (re-search-forward (concat "^" re "$") end 'move)
		(forward-line 1)
	      (setq in-string id-end)
	      (goto-char end))))
	 (t
	  (goto-char pnt))))
       ((looking-at "^__END__$")
	(goto-char pnt))
       ((looking-at ruby-here-doc-beg-re)
	(if (re-search-forward (ruby-here-doc-end-match)
			       indent-point t)
	    (forward-line 1)
	  (setq in-string (match-end 0))
	  (goto-char indent-point)))
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
  (+ pos (* (or nest 1) ruby-indent-level)))

(defun ruby-calculate-indent (&optional parse-start)
  (save-excursion
    (beginning-of-line)
    (let ((indent-point (point))
	  (case-fold-search nil)
	  state bol eol begin op-end
	  (paren (progn (skip-syntax-forward " ")
			(and (char-after) (matching-paren (char-after)))))
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
	(goto-char (setq begin (cdr (nth 1 state))))
	(let ((deep (ruby-deep-indent-paren-p (car (nth 1 state)))))
	  (if deep
	      (cond ((and (eq deep t) (eq (car (nth 1 state)) paren))
		     (skip-syntax-backward " ")
		     (setq indent (1- (current-column))))
		    ((let ((s (ruby-parse-region (point) indent-point)))
		       (and (nth 2 s) (> (nth 2 s) 0)
			    (or (goto-char (cdr (nth 1 s))) t)))
		     (forward-word -1)
		     (setq indent (ruby-indent-size (current-column) (nth 2 state))))
		    (t
		     (setq indent (current-column))
		     (cond ((eq deep 'space))
			   (paren (setq indent (1- indent)))
			   (t (setq indent (ruby-indent-size (1- indent) 1))))))
	    (if (nth 3 state) (goto-char (nth 3 state))
	      (goto-char parse-start) (back-to-indentation))
	    (setq indent (ruby-indent-size (current-column) (nth 2 state))))
	  (and (eq (car (nth 1 state)) paren)
	       (ruby-deep-indent-paren-p (matching-paren paren))
	       (search-backward (char-to-string paren))
	       (setq indent (current-column)))))
       ((and (nth 2 state) (> (nth 2 state) 0)) ; in nest
	(if (null (cdr (nth 1 state)))
	    (error "invalid nest"))
	(goto-char (cdr (nth 1 state)))
	(forward-word -1)		; skip back a keyword
	(setq begin (point))
	(cond
	 ((looking-at "do\\>[^_]")	; iter block is a special case
	  (if (nth 3 state) (goto-char (nth 3 state))
	    (goto-char parse-start) (back-to-indentation))
	  (setq indent (ruby-indent-size (current-column) (nth 2 state))))
	 (t
	  (setq indent (+ (current-column) ruby-indent-level)))))
       
       ((and (nth 2 state) (< (nth 2 state) 0)) ; in negative nest
	(setq indent (ruby-indent-size (current-column) (nth 2 state)))))
      (when indent
	(goto-char indent-point)
	(end-of-line)
	(setq eol (point))
	(beginning-of-line)
	(cond
	 ((and (not (ruby-deep-indent-paren-p paren))
	       (re-search-forward ruby-negative eol t))
	  (and (not (eq ?_ (char-after (match-end 0))))
	       (setq indent (- indent ruby-indent-level))))
	 ((and
	   (save-excursion
	     (beginning-of-line)
	     (not (bobp)))
	   (or (ruby-deep-indent-paren-p t)
	       (null (car (nth 1 state)))))
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
	  ;; skip the comment at the end
	  (skip-chars-backward " \t")
	  (let (end (pos (point)))
	    (beginning-of-line)
	    (while (and (re-search-forward "#" pos t)
			(setq end (1- (point)))
			(or (ruby-special-char-p end)
			    (and (setq state (ruby-parse-region parse-start end))
				 (nth 0 state))))
	      (setq end nil))
	    (goto-char (or end pos))
	    (skip-chars-backward " \t")
	    (setq begin (if (nth 0 state) pos (cdr (nth 1 state))))
	    (setq state (ruby-parse-region parse-start (point))))
	  (or (bobp) (forward-char -1))
	  (and
	   (or (and (looking-at ruby-symbol-re)
		    (skip-chars-backward ruby-symbol-chars)
		    (looking-at (concat "\\<\\(" ruby-block-hanging-re "\\)\\>"))
		    (not (eq (point) (nth 3 state)))
		    (save-excursion
		      (goto-char (match-end 0))
		      (not (looking-at "[a-z_]"))))
	       (and (looking-at ruby-operator-re)
		    (not (ruby-special-char-p))
		    ;; operator at the end of line
		    (let ((c (char-after (point))))
		      (and
;; 		       (or (null begin)
;; 			   (save-excursion
;; 			     (goto-char begin)
;; 			     (skip-chars-forward " \t")
;; 			     (not (or (eolp) (looking-at "#")
;; 				      (and (eq (car (nth 1 state)) ?{)
;; 					   (looking-at "|"))))))
		       (or (not (eq ?/ c))
			   (null (nth 0 (ruby-parse-region (or begin parse-start) (point)))))
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
			      (t t))))
		       (not (eq ?, c))
		       (setq op-end t)))))
	   (setq indent
		 (cond
		  ((and
		    (null op-end)
		    (not (looking-at (concat "\\<\\(" ruby-block-hanging-re "\\)\\>")))
		    (eq (ruby-deep-indent-paren-p t) 'space)
		    (not (bobp)))
		   (save-excursion
		     (widen)
		     (goto-char (or begin parse-start))
		     (skip-syntax-forward " ")
		     (current-column)))
		  ((car (nth 1 state)) indent)
		  (t
		   (+ indent ruby-indent-level))))))))
      indent)))

(defun ruby-electric-brace (arg)
  (interactive "P")
  (insert-char last-command-char 1)
  (ruby-indent-line t)
  (delete-char -1)
  (self-insert-command (prefix-numeric-value arg)))

(eval-when-compile
  (defmacro defun-region-command (func args &rest body)
    (let ((intr (car body)))
      (when (featurep 'xemacs)
	(if (stringp intr) (setq intr (cadr body)))
	(and (eq (car intr) 'interactive)
	     (setq intr (cdr intr))
	     (setcar intr (concat "_" (car intr)))))
      (cons 'defun (cons func (cons args body))))))

(defun-region-command ruby-beginning-of-defun (&optional arg)
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

(defun-region-command ruby-end-of-defun (&optional arg)
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
    (setq down (looking-at (if (< n 0) ruby-block-end-re
			     (concat "\\<\\(" ruby-block-beg-re "\\)\\>"))))
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
	  (save-excursion
	    (back-to-indentation)
	    (if (looking-at (concat "\\<\\(" ruby-block-mid-re "\\)\\>"))
		(setq done nil))))))
  (back-to-indentation))

(defun-region-command ruby-beginning-of-block (&optional arg)
  "Move backward to next beginning-of-block"
  (interactive "p")
  (ruby-move-to-block (- (or arg 1))))

(defun-region-command ruby-end-of-block (&optional arg)
  "Move forward to next beginning-of-block"
  (interactive "p")
  (ruby-move-to-block (or arg 1)))

(defun-region-command ruby-forward-sexp (&optional cnt)
  (interactive "p")
  (if (and (numberp cnt) (< cnt 0))
      (ruby-backward-sexp (- cnt))
    (let ((i (or cnt 1)))
      (condition-case nil
	  (while (> i 0)
	    (skip-syntax-forward " ")
	    (cond ((looking-at "\\?\\(\\\\[CM]-\\)*\\\\?\\S ")
		   (goto-char (match-end 0)))
		  ((progn
		     (skip-chars-forward ",.:;|&^~=!?\\+\\-\\*")
		     (looking-at "\\s("))
		   (goto-char (scan-sexps (point) 1)))
		  ((and (looking-at (concat "\\<\\(" ruby-block-beg-re "\\)\\>"))
			(not (eq (char-before (point)) ?.))
			(not (eq (char-before (point)) ?:)))
		   (ruby-end-of-block)
		   (forward-word 1))
		  ((looking-at "\\(\\$\\|@@?\\)?\\sw")
		   (while (progn
			    (while (progn (forward-word 1) (looking-at "_")))
			    (cond ((looking-at "::") (forward-char 2) t)
				  ((> (skip-chars-forward ".") 0))
				  ((looking-at "\\?\\|!\\(=[~=>]\\|[^~=]\\)")
				   (forward-char 1) nil)))))
		  ((let (state expr)
		     (while
			 (progn
			   (setq expr (or expr (ruby-expr-beg)
					  (looking-at "%\\sw?\\Sw\\|[\"'`/]")))
			   (nth 1 (setq state (apply 'ruby-parse-partial nil state))))
		       (setq expr t)
		       (skip-chars-forward "<"))
		     (not expr))))
	    (setq i (1- i)))
	((error) (forward-word 1)))
      i)))

(defun-region-command ruby-backward-sexp (&optional cnt)
  (interactive "p")
  (if (and (numberp cnt) (< cnt 0))
      (ruby-forward-sexp (- cnt))
    (let ((i (or cnt 1)))
      (condition-case nil
	  (while (> i 0)
	    (skip-chars-backward " \t\n,.:;|&^~=!?\\+\\-\\*")
	    (forward-char -1)
	    (cond ((looking-at "\\s)")
		   (goto-char (scan-sexps (1+ (point)) -1))
		   (case (char-before)
		     (?% (forward-char -1))
		     ('(?q ?Q ?w ?W ?r ?x)
		      (if (eq (char-before (1- (point))) ?%) (forward-char -2))))
		   nil)
		  ((looking-at "\\s\"\\|\\\\\\S_")
		   (let ((c (char-to-string (char-before (match-end 0)))))
		     (while (and (search-backward c)
				 (oddp (skip-chars-backward "\\")))))
		   nil)
		  ((looking-at "\\s.\\|\\s\\")
		   (if (ruby-special-char-p) (forward-char -1)))
		  ((looking-at "\\s(") nil)
		  (t
		   (forward-char 1)
		   (while (progn (forward-word -1)
				 (case (char-before)
				   (?_ t)
				   (?. (forward-char -1) t)
				   ((?$ ?@)
				    (forward-char -1)
				    (and (eq (char-before) (char-after)) (forward-char -1)))
				   (?:
				    (forward-char -1)
				    (eq (char-before) :)))))
		   (if (looking-at ruby-block-end-re)
		       (ruby-beginning-of-block))
		   nil))
	    (setq i (1- i)))
	((error)))
      i)))

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

(defun ruby-indent-exp (&optional shutup-p)
  "Indent each line in the balanced expression following point syntactically.
If optional SHUTUP-P is non-nil, no errors are signalled if no
balanced expression is found."
  (interactive "*P")
  (let ((here (point-marker)) start top column (nest t))
    (set-marker-insertion-type here t)
    (unwind-protect
	(progn
	  (beginning-of-line)
	  (setq start (point) top (current-indentation))
	  (while (and (not (eobp))
		      (progn
			(setq column (ruby-calculate-indent start))
			(cond ((> column top)
			       (setq nest t))
			      ((and (= column top) nest)
			       (setq nest nil) t))))
	    (ruby-indent-to column)
	    (beginning-of-line 2)))
      (goto-char here)
      (set-marker here nil))))

(defun ruby-add-log-current-method ()
  "Return current method string."
  (condition-case nil
      (save-excursion
	(let ((mlist nil) (indent 0))
	  ;; get current method (or class/module)
	  (if (re-search-backward
	       (concat "^[ \t]*\\(def\\|class\\|module\\)[ \t]+"
		       "\\(" 
		       ;; \\. for class method
			"\\(" ruby-symbol-re "\\|\\." "\\)" 
			"+\\)")
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
	  ;; the last $', $", $` in the respective string is not variable
	  ;; the last ?', ?", ?` in the respective string is not ascii code
	  ("\\(^\\|[\[ \t\n<+\(,=]\\)\\(['\"`]\\)\\(\\\\.\\|\\2\\|[^'\"`\n\\\\]\\)*?\\\\?[?$]\\(\\2\\)"
	   (2 (7 . nil))
	   (4 (7 . nil)))
	  ;; $' $" $` .... are variables
	  ;; ?' ?" ?` are ascii codes
	  ("\\(^\\|[^\\\\]\\)\\(\\\\\\\\\\)*[?$]\\([#\"'`]\\)" 3 (1 . nil))
	  ;; regexps
	  ("\\(^\\|[=(,~?:;<>]\\|\\(^\\|\\s \\)\\(if\\|elsif\\|unless\\|while\\|until\\|when\\|and\\|or\\|&&\\|||\\)\\|g?sub!?\\|scan\\|split!?\\)\\s *\\(/\\)[^/\n\\\\]*\\(\\\\.[^/\n\\\\]*\\)*\\(/\\)"
	   (4 (7 . ?/))
	   (6 (7 . ?/)))
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

  (defun ruby-font-lock-here-docs (limit)
    (if (re-search-forward ruby-here-doc-beg-re limit t)
	(let (beg)
	  (beginning-of-line)
          (forward-line)
	  (setq beg (point))
	  (if (re-search-forward (ruby-here-doc-end-match) nil t)
	      (progn
		(set-match-data (list beg (point)))
		t)))))

  (defun ruby-font-lock-maybe-here-docs (limit)
    (let (beg)
      (save-excursion
	(if (re-search-backward ruby-here-doc-beg-re nil t)
	    (progn
	      (beginning-of-line)
              (forward-line)
	      (setq beg (point)))))
      (if (and beg
	       (let ((end-match (ruby-here-doc-end-match)))
                 (and (not (re-search-backward end-match beg t))
		      (re-search-forward end-match nil t))))
	  (progn
	    (set-match-data (list beg (point)))
	    t)
          nil)))

  (defvar ruby-font-lock-keywords
    (list
     ;; functions
     '("^\\s *def\\s +\\([^( \t\n]+\\)"
       1 font-lock-function-name-face)
     ;; keywords
     (cons (concat
	    "\\(^\\|[^_:.@$]\\|\\.\\.\\)\\b\\(defined\\?\\|\\("
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
	    "\\)\\>\\)")
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
     ;; "here" document
     '(ruby-font-lock-here-docs
       0 font-lock-string-face t)
     '(ruby-font-lock-maybe-here-docs
       0 font-lock-string-face t)
     `(,ruby-here-doc-beg-re
       0 font-lock-string-face t)
     ;; general delimited string
     '("\\(^\\|[[ \t\n<+(,=]\\)\\(%[xrqQwW]?\\([^<[{(a-zA-Z0-9 \n]\\)[^\n\\\\]*\\(\\\\.[^\n\\\\]*\\)*\\(\\3\\)\\)"
       (2 font-lock-string-face))
     ;; constants
     '("\\(^\\|[^_]\\)\\b\\([A-Z]+\\(\\w\\|_\\)*\\)"
       2 font-lock-type-face)
     ;; symbols
     '("\\(^\\|[^:]\\)\\(:\\([-+~]@?\\|[/%&|^`]\\|\\*\\*?\\|<\\(<\\|=>?\\)?\\|>[>=]?\\|===?\\|=~\\|\\[\\]=?\\|\\(\\w\\|_\\)+\\([!?=]\\|\\b_*\\)\\|#{[^}\n\\\\]*\\(\\\\.[^}\n\\\\]*\\)*}\\)\\)"
       2 font-lock-reference-face)
     ;; expression expansion
     '("#\\({[^}\n\\\\]*\\(\\\\.[^}\n\\\\]*\\)*}\\|\\(\\$\\|@\\|@@\\)\\(\\w\\|_\\)+\\)"
       0 font-lock-variable-name-face t)
     ;; warn lower camel case
     ;'("\\<[a-z]+[a-z0-9]*[A-Z][A-Za-z0-9]*\\([!?]?\\|\\>\\)"
     ;  0 font-lock-warning-face)
     )
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
