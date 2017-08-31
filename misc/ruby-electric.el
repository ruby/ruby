;;; ruby-electric.el --- Minor mode for electrically editing ruby code
;;
;; Authors: Dee Zsombor <dee dot zsombor at gmail dot com>
;;          Yukihiro Matsumoto
;;          Nobuyoshi Nakada
;;          Akinori MUSHA <knu@iDaemons.org>
;;          Jakub Kuźma <qoobaa@gmail.com>
;; Maintainer: Akinori MUSHA <knu@iDaemons.org>
;; Created: 6 Mar 2005
;; URL: https://github.com/knu/ruby-electric.el
;; Keywords: languages ruby
;; License: The same license terms as Ruby
;; Version: 2.3.1

;;; Commentary:
;;
;; `ruby-electric-mode' accelerates code writing in ruby by making
;; some keys "electric" and automatically supplying with closing
;; parentheses and "end" as appropriate.
;;
;; This work was originally inspired by a code snippet posted by
;; [Frederick Ros](https://github.com/sleeper).
;;
;; Add the following line to enable ruby-electric-mode under
;; ruby-mode.
;;
;;     (eval-after-load "ruby-mode"
;;       '(add-hook 'ruby-mode-hook 'ruby-electric-mode))
;;
;; Type M-x customize-group ruby-electric for configuration.

;;; Code:

(require 'ruby-mode)

(eval-when-compile
  (require 'cl))

(defgroup ruby-electric nil
  "Minor mode providing electric editing commands for ruby files"
  :group 'ruby)

(defconst ruby-electric-expandable-bar-re
  "\\s-\\(do\\|{\\)\\s-*|")

(defconst ruby-electric-delimiters-alist
  '((?\{ :name "Curly brace"  :handler ruby-electric-curlies       :closing ?\})
    (?\[ :name "Square brace" :handler ruby-electric-matching-char :closing ?\])
    (?\( :name "Round brace"  :handler ruby-electric-matching-char :closing ?\))
    (?\' :name "Quote"        :handler ruby-electric-matching-char)
    (?\" :name "Double quote" :handler ruby-electric-matching-char)
    (?\` :name "Back quote"   :handler ruby-electric-matching-char)
    (?\| :name "Vertical bar" :handler ruby-electric-bar)
    (?\# :name "Hash"         :handler ruby-electric-hash)))

(defvar ruby-electric-matching-delimeter-alist
  (apply 'nconc
         (mapcar #'(lambda (x)
                     (let ((delim (car x))
                           (plist (cdr x)))
                       (if (eq (plist-get plist :handler) 'ruby-electric-matching-char)
                           (list (cons delim (or (plist-get plist :closing)
                                                 delim))))))
                 ruby-electric-delimiters-alist)))

(defvar ruby-electric-expandable-keyword-re)

(defmacro ruby-electric--try-insert-and-do (string &rest body)
  (declare (indent 1))
  `(let ((before (point))
         (after (progn
                  (insert ,string)
                  (point))))
     (unwind-protect
         (progn ,@body)
       (delete-region before after)
       (goto-char before))))

(defconst ruby-modifier-beg-symbol-re
  (regexp-opt ruby-modifier-beg-keywords 'symbols))

(defun ruby-electric--modifier-keyword-at-point-p ()
  "Test if there is a modifier keyword at point."
  (and (looking-at ruby-modifier-beg-symbol-re)
       (let ((end (match-end 1)))
         (not (looking-back "\\."))
         (save-excursion
           (let ((indent1 (ruby-electric--try-insert-and-do "\n"
                            (ruby-calculate-indent)))
                 (indent2 (save-excursion
                            (goto-char end)
                            (ruby-electric--try-insert-and-do " x\n"
                              (ruby-calculate-indent)))))
             (= indent1 indent2))))))

(defconst ruby-block-mid-symbol-re
  (regexp-opt ruby-block-mid-keywords 'symbols))

(defun ruby-electric--block-mid-keyword-at-point-p ()
  "Test if there is a block mid keyword at point."
  (and (looking-at ruby-block-mid-symbol-re)
       (looking-back "^\\s-*")))

(defconst ruby-block-beg-symbol-re
  (regexp-opt ruby-block-beg-keywords 'symbols))

(defun ruby-electric--block-beg-keyword-at-point-p ()
  "Test if there is a block beginning keyword at point."
  (and (looking-at ruby-block-beg-symbol-re)
       (if (string= (match-string 1) "do")
           (looking-back "\\s-")
         (not (looking-back "\\.")))
       ;; (not (ruby-electric--modifier-keyword-at-point-p)) ;; implicit assumption
       ))

(defcustom ruby-electric-keywords-alist
  '(("begin" . end)
    ("case" . end)
    ("class" . end)
    ("def" . end)
    ("do" . end)
    ("else" . reindent)
    ("elsif" . reindent)
    ("end" . reindent)
    ("ensure" . reindent)
    ("for" . end)
    ("if" . end)
    ("module" . end)
    ("rescue" . reindent)
    ("unless" . end)
    ("until" . end)
    ("when" . reindent)
    ("while" . end))
  "Alist of keywords and actions to define how to react to space
or return right after each keyword.  In each (KEYWORD . ACTION)
cons, ACTION can be set to one of the following values:

    `reindent'  Reindent the line.

    `end'       Reindent the line and auto-close the keyword with
                end if applicable.

    `nil'       Do nothing.
"
  :type '(repeat (cons (string :tag "Keyword")
                       (choice :tag "Action"
                               :menu-tag "Action"
                               (const :tag "Auto-close with end"
                                      :value end)
                               (const :tag "Auto-reindent"
                                      :value reindent)
                               (const :tag "None"
                                      :value nil))))
  :set (lambda (sym val)
         (set sym val)
         (let (keywords)
           (dolist (x val)
             (let ((keyword (car x))
                   (action (cdr x)))
               (if action
                   (setq keywords (cons keyword keywords)))))
           (setq ruby-electric-expandable-keyword-re
                 (concat (regexp-opt keywords 'symbols)
                         "$"))))
  :group 'ruby-electric)

(defvar ruby-electric-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map " " 'ruby-electric-space/return)
    (define-key map [remap delete-backward-char] 'ruby-electric-delete-backward-char)
    (define-key map [remap newline] 'ruby-electric-space/return)
    (define-key map [remap newline-and-indent] 'ruby-electric-space/return)
    (define-key map [remap electric-newline-and-maybe-indent] 'ruby-electric-space/return)
    (define-key map [remap reindent-then-newline-and-indent] 'ruby-electric-space/return)
    (dolist (x ruby-electric-delimiters-alist)
      (let* ((delim   (car x))
             (plist   (cdr x))
             (name    (plist-get plist :name))
             (func    (plist-get plist :handler))
             (closing (plist-get plist :closing)))
        (define-key map (char-to-string delim) func)
        (if closing
            (define-key map (char-to-string closing) 'ruby-electric-closing-char))))
    map)
  "Keymap used in ruby-electric-mode")

(defcustom ruby-electric-expand-delimiters-list '(all)
  "*List of contexts where matching delimiter should be inserted.
The word 'all' will do all insertions."
  :type `(set :extra-offset 8
              (const :tag "Everything" all)
              ,@(apply 'list
                       (mapcar #'(lambda (x)
                                   `(const :tag ,(plist-get (cdr x) :name)
                                           ,(car x)))
                               ruby-electric-delimiters-alist)))
  :group 'ruby-electric)

(defcustom ruby-electric-newline-before-closing-bracket nil
  "*Non-nil means a newline should be inserted before an
automatically inserted closing bracket."
  :type 'boolean :group 'ruby-electric)

(defcustom ruby-electric-autoindent-on-closing-char nil
  "*Non-nil means the current line should be automatically
indented when a closing character is manually typed in."
  :type 'boolean :group 'ruby-electric)

(defvar ruby-electric-mode-hook nil
  "Called after `ruby-electric-mode' is turned on.")

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
  ruby-electric-mode-map
  (if ruby-electric-mode
      (run-hooks 'ruby-electric-mode-hook)))

(defun ruby-electric-space/return-fallback ()
  (if (or (eq this-original-command 'ruby-electric-space/return)
          (null (ignore-errors
                  ;; ac-complete may fail if there is nothing left to complete
                  (call-interactively this-original-command)
                  (setq this-command this-original-command))))
      ;; fall back to a globally bound command
      (let ((command (global-key-binding (char-to-string last-command-event) t)))
        (and command
             (call-interactively (setq this-command command))))))

(defun ruby-electric-space/return (arg)
  (interactive "*P")
  (and (boundp 'sp-last-operation)
       (setq sp-delayed-pair nil))
  (cond ((or arg
             (region-active-p))
         (or (= last-command-event ?\s)
             (setq last-command-event ?\n))
         (ruby-electric-replace-region-or-insert))
        ((ruby-electric-space/return-can-be-expanded-p)
         (let (action)
           (save-excursion
             (goto-char (match-beginning 0))
             (let* ((keyword (match-string 1))
                    (allowed-actions
                     (cond ((ruby-electric--modifier-keyword-at-point-p)
                            '(reindent)) ;; no end necessary
                           ((ruby-electric--block-mid-keyword-at-point-p)
                            '(reindent)) ;; ditto
                           ((ruby-electric--block-beg-keyword-at-point-p)
                            '(end reindent)))))
               (if allowed-actions
                   (setq action
                         (let ((action (cdr (assoc keyword ruby-electric-keywords-alist))))
                           (and (memq action allowed-actions)
                                action))))))
           (cond ((eq action 'end)
                  (ruby-indent-line)
                  (save-excursion
                    (newline)
                    (ruby-electric-end)))
                 ((eq action 'reindent)
                  (ruby-indent-line)))
           (ruby-electric-space/return-fallback)))
        ((and (eq this-original-command 'newline-and-indent)
              (ruby-electric-comment-at-point-p))
         (call-interactively (setq this-command 'comment-indent-new-line)))
        (t
         (ruby-electric-space/return-fallback))))

(defun ruby-electric--get-faces-at-point ()
  (let* ((point (point))
         (value (or
                 (get-text-property point 'read-face-name)
                 (get-text-property point 'face))))
    (if (listp value) value (list value))))

(defun ruby-electric--faces-include-p (pfaces &rest faces)
  (and ruby-electric-mode
       (loop for face in faces
             thereis (memq face pfaces))))

(defun ruby-electric--faces-at-point-include-p (&rest faces)
  (apply 'ruby-electric--faces-include-p
         (ruby-electric--get-faces-at-point)
         faces))

(defun ruby-electric-code-face-p (faces)
  (not (ruby-electric--faces-include-p
        faces
        'font-lock-string-face
        'font-lock-comment-face
        'enh-ruby-string-delimiter-face
        'enh-ruby-heredoc-delimiter-face
        'enh-ruby-regexp-delimiter-face
        'enh-ruby-regexp-face)))

(defun ruby-electric-code-at-point-p ()
  (ruby-electric-code-face-p
   (ruby-electric--get-faces-at-point)))

(defun ruby-electric-string-face-p (faces)
  (ruby-electric--faces-include-p
   faces
   'font-lock-string-face
   'enh-ruby-string-delimiter-face
   'enh-ruby-heredoc-delimiter-face
   'enh-ruby-regexp-delimiter-face
   'enh-ruby-regexp-face))

(defun ruby-electric-string-at-point-p ()
  (ruby-electric-string-face-p
   (ruby-electric--get-faces-at-point)))

(defun ruby-electric-comment-at-point-p ()
  (ruby-electric--faces-at-point-include-p
   'font-lock-comment-face))

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

(defun ruby-electric-space/return-can-be-expanded-p()
  (and (ruby-electric-code-at-point-p)
       (looking-back ruby-electric-expandable-keyword-re)))

(defun ruby-electric-replace-region-or-insert ()
  (and (region-active-p)
       (bound-and-true-p delete-selection-mode)
       (fboundp 'delete-selection-helper)
       (delete-selection-helper (get 'self-insert-command 'delete-selection)))
  (insert (make-string (prefix-numeric-value current-prefix-arg)
                       last-command-event))
  (setq this-command 'self-insert-command))

(defmacro ruby-electric-insert (arg &rest body)
  `(cond ((and
           (null ,arg)
           (ruby-electric-command-char-expandable-punct-p last-command-event))
          (let ((region-beginning
                 (cond ((region-active-p)
                        (prog1
                            (save-excursion
                              (goto-char (region-beginning))
                              (insert last-command-event)
                              (point))
                          (goto-char (region-end))))
                       (t
                        (insert last-command-event)
                        nil)))
                (faces-at-point
                 (ruby-electric--get-faces-at-point)))
            ,@body
            (and region-beginning
                 ;; If no extra character is inserted, go back to the
                 ;; region beginning.
                 (eq this-command 'self-insert-command)
                 (goto-char region-beginning))))
         ((ruby-electric-replace-region-or-insert))))

(defun ruby-electric-curlies (arg)
  (interactive "*P")
  (ruby-electric-insert
   arg
   (cond
    ((or (ruby-electric-code-at-point-p)
         (ruby-electric--faces-include-p
          faces-at-point
          'enh-ruby-string-delimiter-face
          'enh-ruby-regexp-delimiter-face))
     (save-excursion
       (insert "}")
       (font-lock-fontify-region (line-beginning-position) (point)))
     (cond
      ((or (ruby-electric-string-at-point-p)  ;; %w{}, %r{}, etc.
           (looking-back "%[QqWwRrxIis]{"))
       (if region-beginning
           (forward-char 1)))
      (ruby-electric-newline-before-closing-bracket
       (cond (region-beginning
              (save-excursion
                (goto-char region-beginning)
                (newline))
              (newline)
              (forward-char 1)
              (indent-region region-beginning (line-end-position)))
             (t
              (insert " ")
              (save-excursion
                (newline)
                (ruby-indent-line t)))))
      (t
       (if region-beginning
           (save-excursion
             (goto-char region-beginning)
             (insert " "))
         (insert " "))
       (insert " ")
       (backward-char 1)
       (and region-beginning
            (forward-char 1)))))
    ((ruby-electric-string-at-point-p)
     (let ((start-position (1- (or region-beginning (point)))))
       (cond
        ((char-equal ?\# (char-before start-position))
         (unless (save-excursion
                   (goto-char (1- start-position))
                   (ruby-electric-escaped-p))
           (insert "}")
           (or region-beginning
               (backward-char 1))))
        ((or
          (ruby-electric-command-char-expandable-punct-p ?\#)
          (save-excursion
            (goto-char start-position)
            (ruby-electric-escaped-p)))
         (if region-beginning
             (goto-char region-beginning))
         (setq this-command 'self-insert-command))
        (t
         (save-excursion
           (goto-char start-position)
           (insert "#"))
         (insert "}")
         (or region-beginning
             (backward-char 1))))))
    (t
     (delete-char -1)
     (ruby-electric-replace-region-or-insert)))))

(defun ruby-electric-hash (arg)
  (interactive "*P")
  (ruby-electric-insert
   arg
   (if (ruby-electric-string-at-point-p)
       (let ((start-position (1- (or region-beginning (point)))))
         (cond
          ((char-equal (following-char) ?')) ;; likely to be in ''
          ((save-excursion
             (goto-char start-position)
             (ruby-electric-escaped-p)))
          (region-beginning
           (save-excursion
             (goto-char (1+ start-position))
             (insert "{"))
           (insert "}"))
          (t
           (insert "{")
           (save-excursion
             (insert "}")))))
     (delete-char -1)
     (ruby-electric-replace-region-or-insert))))

(defun ruby-electric-matching-char (arg)
  (interactive "*P")
  (ruby-electric-insert
   arg
   (let ((closing (cdr (assoc last-command-event
                              ruby-electric-matching-delimeter-alist))))
     (cond
      ;; quotes
      ((char-equal closing last-command-event)
       (cond ((not (ruby-electric-string-face-p faces-at-point))
              (if region-beginning
                  ;; escape quotes of the same kind, backslash and hash
                  (let ((re (format "[%c\\%s]"
                                    last-command-event
                                    (if (char-equal last-command-event ?\")
                                        "#" "")))
                        (bound (point)))
                    (save-excursion
                      (goto-char region-beginning)
                      (while (re-search-forward re bound t)
                        (let ((end (point)))
                          (replace-match "\\\\\\&")
                          (setq bound (+ bound (- (point) end))))))))
              (insert closing)
              (or region-beginning
                  (backward-char 1)))
             (t
              (and (eq last-command 'ruby-electric-matching-char)
                   (char-equal (following-char) closing) ;; repeated quotes
                   (delete-char 1))
              (setq this-command 'self-insert-command))))
      ((ruby-electric-code-at-point-p)
       (insert closing)
       (or region-beginning
           (backward-char 1)))))))

(defun ruby-electric-closing-char(arg)
  (interactive "*P")
  (cond
   (arg
    (ruby-electric-replace-region-or-insert))
   ((and
     (eq last-command 'ruby-electric-curlies)
     (= last-command-event ?})
     (not (char-equal (preceding-char) last-command-event))) ;; {}
    (if (char-equal (following-char) ?\n) (delete-char 1))
    (delete-horizontal-space)
    (forward-char))
   ((and
     (= last-command-event (following-char))
     (not (char-equal (preceding-char) last-command-event))
     (memq last-command '(ruby-electric-matching-char
                          ruby-electric-closing-char))) ;; ()/[] and (())/[[]]
    (forward-char))
   (t
    (ruby-electric-replace-region-or-insert)
    (if ruby-electric-autoindent-on-closing-char
        (ruby-indent-line)))))

(defun ruby-electric-bar(arg)
  (interactive "*P")
  (ruby-electric-insert
   arg
   (cond ((and (ruby-electric-code-at-point-p)
               (looking-back ruby-electric-expandable-bar-re))
          (save-excursion (insert "|")))
         (t
          (delete-char -1)
          (ruby-electric-replace-region-or-insert)))))

(defun ruby-electric-delete-backward-char(arg)
  (interactive "*p")
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
  (delete-char (- arg)))

(put 'ruby-electric-delete-backward-char 'delete-selection 'supersede)

(defun ruby-electric-end ()
  (interactive)
  (if (eq (char-syntax (preceding-char)) ?w)
      (insert " "))
  (insert "end")
  (save-excursion
    (if (eq (char-syntax (following-char)) ?w)
        (insert " "))
    (ruby-indent-line t)))

(provide 'ruby-electric)

;;; ruby-electric.el ends here
