;; -*-Emacs-Lisp-*-
;;
;; ruby-electric.el --- electric editing commands for ruby files
;;
;; Copyright (C) 2005 by Dee Zsombor <dee dot zsombor at gmail dot com>.
;; Released under same license terms as Ruby.
;;
;; Due credit: this work was inspired by a code snippet posted by
;; Frederick Ros at http://rubygarden.org/ruby?EmacsExtensions.
;;
;; Following improvements where added:
;;
;;       - handling of strings of type 'here document'
;;       - more keywords, with special handling for 'do'
;;       - packaged into a minor mode
;;
;; Usage:
;;
;;    0) copy ruby-electric.el into directory where emacs can find it.
;;
;;    1) modify your startup file (.emacs or whatever) by adding
;;       following line:
;;
;;            (require 'ruby-electric)
;;
;;       note that you need to have font lock enabled beforehand.
;;
;;    2) toggle Ruby Electric Mode on/off with ruby-electric-mode.
;;
;; Changelog:
;;
;;  2005/Jan/14: inserts matching pair delimiters like {, [, (, ', ",
;;  ' and | .
;;
;;  2005/Jan/14: added basic Custom support for configuring keywords
;;  with electric closing.
;;
;;  2005/Jan/18: more Custom support for configuring characters for
;;  which matching expansion should occur.
;;
;;  2005/Jan/18: no longer uses 'looking-back' or regexp character
;;  classes like [:space:] since they are not implemented on XEmacs.
;;
;;  2005/Feb/01: explicitly provide default argument of 1 to
;;  'backward-word' as it requires it on Emacs 21.3
;;
;;  2005/Mar/06: now stored inside ruby CVS; customize pages now have
;;  ruby as parent; cosmetic fixes.


(require 'ruby-mode)

(defgroup ruby-electric nil
  "Minor mode providing electric editing commands for ruby files"
  :group 'ruby)

(defconst ruby-electric-expandable-bar
  "\\s-\\(do\\|{\\)\\s-+|")

(defvar ruby-electric-matching-delimeter-alist
  '((?\[ . ?\])
    (?\( . ?\))
    (?\' . ?\')
    (?\` . ?\`)
    (?\" . ?\")))

(defvar ruby-electric-expandable-do-re)

(defvar ruby-electric-expandable-keyword-re)

(defcustom ruby-electric-keywords
  '("begin"
    "case"
    "class"
    "def"
    "do"
    "for"
    "if"
    "module"
    "unless"
    "until"
    "while")
  "List of keywords for which closing 'end' is to be inserted
after typing a space."
  :type '(repeat string)
  :set (lambda (sym val)
         (set sym val)
         (setq ruby-electric-expandable-do-re
               (and (member "do" val)
                    "\\S-\\s-+\\(do\\)\\s-?$")
               ruby-electric-expandable-keyword-re
               (concat "^\\s-*"
                       (regexp-opt (remove "do" val) t)
                       "\\s-?$")))
  :group 'ruby-electric)

(defcustom ruby-electric-simple-keywords-re nil
  "Obsolete and ignored.  Customize `ruby-electric-keywords'
instead."
  :type 'regexp :group 'ruby-electric)

(defcustom ruby-electric-expand-delimiters-list '(all)
  "*List of contexts where matching delimiter should be
inserted. The word 'all' will do all insertions."
  :type '(set :extra-offset 8
              (const :tag "Everything" all )
              (const :tag "Curly brace" ?\{ )
              (const :tag "Square brace" ?\[ )
              (const :tag "Round brace" ?\( )
              (const :tag "Quote" ?\' )
              (const :tag "Double quote" ?\" )
              (const :tag "Back quote" ?\` )
              (const :tag "Vertical bar" ?\| )
              (const :tag "Hash" ?\# ))
  :group 'ruby-electric)

(defcustom ruby-electric-newline-before-closing-bracket nil
  "*Controls whether a newline should be inserted before the
closing bracket or not."
  :type 'boolean :group 'ruby-electric)

;;;###autoload
(define-minor-mode ruby-electric-mode
  "Toggle Ruby Electric minor mode.
With no argument, this command toggles the mode.  Non-null prefix
argument turns on the mode.  Null prefix argument turns off the
mode.

When Ruby Electric mode is enabled, an indented 'end' is
heuristicaly inserted whenever typing a word like 'module',
'class', 'def', 'if', 'unless', 'case', 'until', 'for', 'begin',
'do' followed by a space.  Single, double and back quotes as well
as braces are paired auto-magically.  Expansion does not occur
inside comments and strings. Note that you must have Font Lock
enabled."
  ;; initial value.
  nil
  ;;indicator for the mode line.
  " REl"
  ;;keymap
  ruby-mode-map
  (ruby-electric-setup-keymap))

(defun ruby-electric-setup-keymap()
  (define-key ruby-mode-map " " 'ruby-electric-space)
  (define-key ruby-mode-map "{" 'ruby-electric-curlies)
  (define-key ruby-mode-map "(" 'ruby-electric-matching-char)
  (define-key ruby-mode-map "[" 'ruby-electric-matching-char)
  (define-key ruby-mode-map "\"" 'ruby-electric-matching-char)
  (define-key ruby-mode-map "\'" 'ruby-electric-matching-char)
  (define-key ruby-mode-map "`" 'ruby-electric-matching-char)
  (define-key ruby-mode-map "}" 'ruby-electric-closing-char)
  (define-key ruby-mode-map ")" 'ruby-electric-closing-char)
  (define-key ruby-mode-map "]" 'ruby-electric-closing-char)
  (define-key ruby-mode-map "|" 'ruby-electric-bar)
  (define-key ruby-mode-map "#" 'ruby-electric-hash)
  (define-key ruby-mode-map (kbd "DEL") 'ruby-electric-delete-backward-char))

(defun ruby-electric-space (arg)
  (interactive "P")
  (insert (make-string (prefix-numeric-value arg) last-command-event))
  (if (ruby-electric-space-can-be-expanded-p)
      (save-excursion
        (ruby-indent-line t)
        (newline)
        (ruby-insert-end))))

(defun ruby-electric-code-at-point-p()
  (and ruby-electric-mode
       (let* ((properties (text-properties-at (point))))
         (and (null (memq 'font-lock-string-face properties))
              (null (memq 'font-lock-comment-face properties))))))

(defun ruby-electric-string-at-point-p()
  (and ruby-electric-mode
       (consp (memq 'font-lock-string-face (text-properties-at (point))))))

(defun ruby-electric-escaped-p()
  (let ((f nil))
    (save-excursion
      (while (char-equal ?\\ (preceding-char))
        (backward-char 1)
        (setq f (not f))))
    f))

(defun ruby-electric-command-char-expandable-punct-p(char)
  (or (memq 'all ruby-electric-expand-delimiters-list)
      (memq char ruby-electric-expand-delimiters-list)))

(defun ruby-electric-is-last-command-char-expandable-punct-p()
  (or (memq 'all ruby-electric-expand-delimiters-list)
      (memq last-command-event ruby-electric-expand-delimiters-list)))

(defun ruby-electric-space-can-be-expanded-p()
  (if (ruby-electric-code-at-point-p)
      (cond ((and ruby-electric-expandable-do-re
                  (looking-back ruby-electric-expandable-do-re))
             (not (ruby-electric-space--sp-has-pair-p "do")))
            ((looking-back ruby-electric-expandable-keyword-re)
             (not (ruby-electric-space--sp-has-pair-p (match-string 1)))))))

(defun ruby-electric-space--sp-has-pair-p(keyword)
  (and (boundp 'smartparens-mode)
       smartparens-mode
       (let ((plist (sp-get-pair keyword)))
         (and plist
              ;; Check for :actions '(insert)
              (memq 'insert (plist-get plist :actions))
              ;; Check for :when '(("SPC" "RET" "<evil-ret>"))
              (let ((x (plist-get plist :when)) when-space)
                (while (and x
                            (not (let ((it (car x)))
                                   (setq when-space (and (listp it)
                                                         (member "SPC" it))))))
                  (setq x (cdr x)))
                when-space)))))

(defun ruby-electric-cua-replace-region-maybe()
  (let ((func (key-binding [remap self-insert-command])))
    (when (memq func '(cua-replace-region
                       sp--cua-replace-region))
      (setq this-original-command 'self-insert-command)
      (funcall (setq this-command func))
      t)))

(defun ruby-electric-cua-delete-region-maybe()
  (let ((func (key-binding [remap delete-backward-char])))
    (when (eq func 'cua-delete-region)
      (setq this-original-command 'delete-backward-char)
      (funcall (setq this-command func))
      t)))

(defmacro ruby-electric-insert (arg &rest body)
  `(cond ((ruby-electric-cua-replace-region-maybe))
         ((and
           (null ,arg)
           (ruby-electric-is-last-command-char-expandable-punct-p))
          (insert last-command-event)
          ,@body)
         (t
          (setq this-command 'self-insert-command)
          (insert (make-string (prefix-numeric-value ,arg) last-command-event)))))

(defun ruby-electric-curlies(arg)
  (interactive "P")
  (ruby-electric-insert
   arg
   (cond
    ((ruby-electric-code-at-point-p)
     (insert "}")
     (backward-char 1)
     (redisplay)
     (cond
      ((ruby-electric-string-at-point-p) ;; %w{}, %r{}, etc.
       t)
      (ruby-electric-newline-before-closing-bracket
       (insert " ")
       (save-excursion
         (newline)
         (ruby-indent-line t)))
      (t
       (insert "  ")
       (backward-char 1))))
    ((ruby-electric-string-at-point-p)
     (save-excursion
       (backward-char 1)
       (cond
        ((char-equal ?\# (preceding-char))
         (unless (save-excursion
                   (backward-char 1)
                   (ruby-electric-escaped-p))
           (forward-char 1)
           (insert "}")))
        ((or
          (ruby-electric-command-char-expandable-punct-p ?\#)
          (ruby-electric-escaped-p))
         (setq this-command 'self-insert-command))
        (t
         (insert "#")
         (forward-char 1)
         (insert "}"))))))))

(defun ruby-electric-hash(arg)
  (interactive "P")
  (ruby-electric-insert
   arg
   (and (ruby-electric-string-at-point-p)
        (or (char-equal (following-char) ?') ;; likely to be in ''
            (save-excursion
              (backward-char 1)
              (ruby-electric-escaped-p))
            (progn
              (insert "{}")
              (backward-char 1))))))

(defmacro ruby-electric-avoid-eob(&rest body)
  `(if (eobp)
       (save-excursion
         (insert "\n")
         (backward-char)
         ,@body
         (prog1
             (ruby-electric-string-at-point-p)
           (delete-char 1)))
     ,@body))

(defun ruby-electric-matching-char(arg)
  (interactive "P")
  (ruby-electric-insert
   arg
   (let ((closing (cdr (assoc last-command-event
                              ruby-electric-matching-delimeter-alist))))
     (cond
      ((char-equal closing last-command-event)
       (if (and (not (ruby-electric-string-at-point-p))
                (ruby-electric-avoid-eob
                 (redisplay)
                 (ruby-electric-string-at-point-p)))
           (save-excursion (insert closing))
         (and (eq last-command 'ruby-electric-matching-char)
              (char-equal (following-char) closing) ;; repeated quotes
              (delete-forward-char 1))
         (setq this-command 'self-insert-command)))
      ((ruby-electric-code-at-point-p)
       (save-excursion (insert closing)))))))

(defun ruby-electric-closing-char(arg)
  (interactive "P")
  (cond
   ((ruby-electric-cua-replace-region-maybe))
   (arg
    (setq this-command 'self-insert-command)
    (insert (make-string (prefix-numeric-value arg) last-command-event)))
   ((and
     (eq last-command 'ruby-electric-curlies)
     (= last-command-event ?})) ;; {}
    (if (char-equal (following-char) ?\n) (delete-char 1))
    (delete-horizontal-space)
    (forward-char))
   ((and
     (= last-command-event (following-char))
     (memq last-command '(ruby-electric-matching-char
                          ruby-electric-closing-char))) ;; ()/[] and (())/[[]]
    (forward-char))
   (t
    (setq this-command 'self-insert-command)
    (self-insert-command 1))))

(defun ruby-electric-bar(arg)
  (interactive "P")
  (ruby-electric-insert
   arg
   (and (ruby-electric-code-at-point-p)
        (save-excursion (re-search-backward ruby-electric-expandable-bar nil t))
        (= (point) (match-end 0)) ;; looking-back is missing on XEmacs
        (save-excursion
          (insert "|")))))

(defun ruby-electric-delete-backward-char(arg)
  (interactive "P")
  (unless (ruby-electric-cua-delete-region-maybe)
    (cond ((memq last-command '(ruby-electric-matching-char
                                ruby-electric-bar))
           (delete-char 1))
          ((eq last-command 'ruby-electric-curlies)
           (cond ((eolp)
                  (cond ((char-equal (preceding-char) ?\s)
                         (setq this-command last-command))
                        ((char-equal (preceding-char) ?{)
                         (and (looking-at "[ \t\n]*}")
                              (delete-char (- (match-end 0) (match-beginning 0)))))))
                 ((char-equal (following-char) ?\s)
                  (setq this-command last-command)
                  (delete-char 1))
                 ((char-equal (following-char) ?})
                  (delete-char 1))))
          ((eq last-command 'ruby-electric-hash)
           (and (char-equal (preceding-char) ?{)
                (delete-char 1))))
    (delete-char -1)))

(provide 'ruby-electric)
