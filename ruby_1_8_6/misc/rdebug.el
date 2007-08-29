;;  This file adds support for ruby-debug (rdebug) in Emacs.
;;  Copyright (C) 2007 Martin Nordholts <enselic@gmail.com>
;;
;;  This file is based on 'rubydb3x.el' that comes with Ruby which is
;;  Copyright (C) Yukihiro Matsumoto aka Matz
;;
;;  Installation:
;;  -------------
;;
;;    1.  Make sure you have ruby-debug on your system (test by running
;;        the commmand 'rdebug -v' in a shell).
;;
;;    2.  Copy this file into e.g. ~/.elisp and make sure this is in
;;        your ~/.emacs:
;;
;;          (add-to-list 'load-path "~/.elisp")
;;          (load-library "rdebug")
;;
;;        you can then start the debugger with M-x rdebug
;;
;;    3.  Setup convenient keybindings etc. This is what I have:
;;
;;          (global-set-key [f9] 'gud-step)
;;          (global-set-key [f10] 'gud-next)
;;          (global-set-key [f11] 'gud-cont)
;;
;;          (global-set-key "\C-c\C-d" 'rdebug)
;;
;;    4. Debug like crazy!
;;
;;  Bugs:
;;  -----
;;
;;    Basic functionality works fine, though there might be a bug hiding somewhere.

(require 'gud)
(provide 'rdebug)

;; ======================================================================
;; rdebug functions

;;; History of argument lists passed to rdebug.
(defvar gud-rdebug-history nil)

(if (fboundp 'gud-overload-functions)
    (defun gud-rdebug-massage-args (file args)
      (cons file args))
  (defun gud-rdebug-massage-args (file args)
    args))

;; There's no guarantee that Emacs will hand the filter the entire
;; marker at once; it could be broken up across several strings.  We
;; might even receive a big chunk with several markers in it.  If we
;; receive a chunk of text which looks like it might contain the
;; beginning of a marker, we save it here between calls to the
;; filter.
(defvar gud-rdebug-marker-acc "")
(make-variable-buffer-local 'gud-rdebug-marker-acc)

(defun gud-rdebug-marker-filter (string)
  (setq gud-rdebug-marker-acc (concat gud-rdebug-marker-acc string))
  (let ((output ""))

    ;; Process all the complete markers in this chunk.
    (while (string-match "\\([^:\n]*\\):\\([0-9]+\\):.*\n"
			 gud-rdebug-marker-acc)
      (setq

       ;; Extract the frame position from the marker.
       gud-last-frame
       (cons (substring gud-rdebug-marker-acc (match-beginning 1) (match-end 1))
	     (string-to-int (substring gud-rdebug-marker-acc
				       (match-beginning 2)
				       (match-end 2))))


       ;; Append any text before the marker to the output we're going
       ;; to return - we don't include the marker in this text.
       output (concat output
		      (substring gud-rdebug-marker-acc 0 (match-beginning 0)))
       
       ;; Set the accumulator to the remaining text.
       gud-rdebug-marker-acc (substring gud-rdebug-marker-acc (match-end 0))))
    
    (setq output (concat output gud-rdebug-marker-acc)
	  gud-rdebug-marker-acc "")
    
    output))

(defun gud-rdebug-find-file (f)
  (save-excursion
    (let ((buf (find-file-noselect f)))
      (set-buffer buf)
;;      (gud-make-debug-menu)
      buf)))

(defvar rdebug-command-name "rdebug"
  "File name for executing rdebug.")

;;;###autoload
(defun rdebug (command-line)
  "Run rdebug on program FILE in buffer *gud-FILE*.
The directory containing FILE becomes the initial working directory
and source-file directory for your debugger."
  (interactive
   (list (read-from-minibuffer "Run rdebug (like this): "
			       (if (consp gud-rdebug-history)
				   (car gud-rdebug-history)
				 (concat rdebug-command-name " "))
			       nil nil
			       '(gud-rdebug-history . 1))))
  
  (if (not (fboundp 'gud-overload-functions))
      (gud-common-init command-line 'gud-rdebug-massage-args
		       'gud-rdebug-marker-filter 'gud-rdebug-find-file)
    (gud-overload-functions '((gud-massage-args . gud-rdebug-massage-args)
			      (gud-marker-filter . gud-rdebug-marker-filter)
			      (gud-find-file . gud-rdebug-find-file)))
    (gud-common-init command-line rdebug-command-name))
  
  (gud-def gud-break  "break %d%f:%l"   "\C-b" "Set breakpoint at current line in current file.")
;  (gud-def gud-remove "delete %d%f:%l"  "\C-d" "Remove breakpoint at current line in current file.")
  (gud-def gud-step   "step"            "\C-s" "Step one source line with display.")
  (gud-def gud-next   "next"            "\C-n" "Step one line (skip functions).")
  (gud-def gud-cont   "cont"            "\C-r" "Continue with display.")
  (gud-def gud-finish "finish"          "\C-f" "Finish executing current function.")
  (gud-def gud-up     "up %p"           "<" "Up N stack frames (numeric arg).")
  (gud-def gud-down   "down %p"         ">" "Down N stack frames (numeric arg).")
  (gud-def gud-print  "p %e"            "\C-p" "Evaluate ruby expression at point.")

  (setq comint-prompt-regexp "^(rdb:-) ")
  (if (boundp 'comint-last-output-start)
      (set-marker comint-last-output-start (point)))
  (set (make-local-variable 'paragraph-start) comint-prompt-regexp)
  (run-hooks 'rdebug-mode-hook)
  )
