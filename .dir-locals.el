;; Copyright (c) 2018 Urabe, Shyouhei.  All rights reserved.
;;
;; This file is a part of  the programming language Ruby.  Permission is hereby
;; granted, to either  redistribute and/or modify this file,  provided that the
;; conditions mentioned  in the  file COPYING  are met.   Consult the  file for
;; details.

((nil .
     ((indent-tabs-mode . nil)
      (require-final-newline . t)
      (tab-width . 8)
      (show-trailing-whitespace . t)
      (whitespace-line-column . 80))) ;; See also [Misc #12277]

 ;; (bat-mode . ((buffer-file-coding-system . utf-8-dos)))

 (ruby-mode . ((ruby-indent-level . 2)))

 (rdoc-mode . ((fill-column . 74)))

 (yaml-mode . ((yaml-indent-offset . 2)))

 (makefile-mode . ((indent-tabs-mode . t)))

 (c-mode . ((c-file-style . "ruby")))

 (c++-mode . ((c-file-style . "ruby")))

 (change-log-mode .
     ((buffer-file-coding-system . us-ascii)
      (indent-tabs-mode . t)
      (change-log-indent-text . 2)
      (add-log-time-format . (lambda (&optional x y)
        (let* ((time (or x (current-time)))
	       (system-time-locale "C")
	       (diff (+ (cadr time) 32400))
	       (lo (% diff 65536))
	       (hi (+ (car time) (/ diff 65536))))
        (format-time-string "%a %b %e %H:%M:%S %Y" (list hi lo) t)))))))
