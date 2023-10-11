;; -*- lexical-binding:t -*-
;;; j-mode.el --- Major mode for editing J programs

;; Copyright (C) 2012 Zachary Elliott
;; Copyright (C) 2023 LdBeth
;;
;; Authors: Zachary Elliott <ZacharyElliott1@gmail.com>
;; URL: http://github.com/ldbeth/j-mode
;; Version: 2.0.0
;; Keywords: J, Langauges

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Provides font-lock and basic REPL integration for the
;; [J programming language](http://www.jsoftware.com)

;;; Installation

;; The only method of installation is to check out the project, add it to the
;; load path, and load normally. This may change one day.
;;
;; Put this in your emacs config
;;   (add-to-list 'load-path "/path/to/j-mode/")
;;   (load "j-mode")
;;
;; Add for detection of j source files if the auto-load fails
;;   (add-to-list 'auto-mode-alist '("\\.ij[rstp]$" . j-mode)))

;;; License:

;; This program is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free Software
;; Foundation; either version 3 of the License, or (at your option) any later
;; version.
;;
;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
;; details.
;;
;; You should have received a copy of the GNU General Public License along with
;; GNU Emacs; see the file COPYING.  If not, write to the Free Software
;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,
;; USA.

;;; Code:

;; Required eval depth for older systems
;; (setq max-lisp-eval-depth (max 500 max-lisp-eval-depth))
(require 'j-font-lock)
(require 'j-console)
(require 'j-help)
(eval-when-compile (require 'rx))


(defconst j-mode-version "1.1.1"
  "`j-mode' version")

(defgroup j nil
  "A mode for J"
  :group 'languages
  :prefix "j-")

(defcustom j-mode-hook nil
  "Hook called by `j-mode'"
  :type 'hook
  :group 'j)

(defcustom j-indent-offset 2
  "Amount of offset per level of indentation."
  :type 'natnum
  :group 'j)

(defconst j-indenting-keywords-regexp
  (rx (or (seq bow
               (or (regexp
                    (regexp-opt
                     '(;;"do\\."
                       "if." "else." "elseif."
                       "select." "case." "fcase."
                       "throw."
                       "try." "except." "catch." "catcht."
                       "while." "whilst."
                       "for.")))
                   (seq (or "for" "goto" "label")
                        (regexp "_[a-zA-Z]+\\."))))
          (seq (regexp "[_a-zA-Z0-9]+")
               (* "\s") "=" (or "." ":") (* "\s")
               "{{"))))
(defconst j-dedenting-keywords-regexp
  (rx (or "}}"
          (seq bow
               (regexp (regexp-opt '("end."
                                     "else." "elseif."
                                     "case." "fcase."
                                     "catch." "catcht." "except.")))))))

(defun j-thing-outside-string (thing-regexp)
  "Look for REGEXP from `point' til `point-at-eol' outside strings and
comments. Match-data is set for THING-REGEXP. Returns nil if no match was
found, else beginning and end of the match."
  (save-excursion
    (if (not (search-forward-regexp thing-regexp (pos-eol) t))
        nil
        (let* ((thing-begin (match-beginning 0))
               (thing-end (match-end 0))
               (parse (save-excursion
                        (parse-partial-sexp (pos-eol) thing-end))))
          (if (or (nth 3 parse) (nth 4 parse))
              nil
              (list thing-begin thing-end))))))

(defun j-compute-indentation ()
  "Return what indentation should be in effect, disregarding
contents of current line."
  (let ((indent 0))
    (save-excursion
      ;; skip empty/comment lines, if that leaves us in the first line, return 0
      (while (and (= (forward-line -1) 0)
                  (if (looking-at "\\s *\\\\?$")
                      t
                    (setq indent (save-match-data
                                   (back-to-indentation)
                                   (if (and (looking-at j-indenting-keywords-regexp)
                                            (progn
                                              (goto-char (match-end 0))
                                              (not (j-thing-outside-string "\\<end\\."))))
                                       (+ (current-indentation) j-indent-offset)
                                     (current-indentation))))
                    nil))))
    indent))

(defun j-indent-line ()
  "Indent current line correctly."
  (interactive)
  (let ((old-point (point)))
    (save-match-data
      (back-to-indentation)
      (let* ((tentative-indent (j-compute-indentation))
             ;;FIXME doesn't handle comments correctly
             (indent (if (looking-at j-dedenting-keywords-regexp)
                         (- tentative-indent j-indent-offset)
                         tentative-indent))
             (delta (- indent (current-indentation))))
;;         (message "###DEBUGi:%d t:%d" indent tentative-indent)
        (indent-line-to indent)
        (back-to-indentation)
        (goto-char (max (point) (+ old-point delta))))
      )))

(defvar j-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c !")   'j-console)
    (define-key map (kbd "C-c C-c") 'j-console-execute-buffer)
    (define-key map (kbd "C-c C-r") 'j-console-execute-region)
    (define-key map (kbd "C-c C-l") 'j-console-execute-line)
    (define-key map (kbd "C-c h")   'j-help-lookup-symbol)
    (define-key map (kbd "C-c C-h") 'j-help-lookup-symbol-at-point)
    map)
  "Keymap for J major mode")

(defvar j-mode-menu nil "Drop-down menu for j-mode interaction")
(easy-menu-define j-mode-menu j-mode-map "J Mode menu"
  '("J"
    ["Start J Console" j-console t]
    ["Execute Buffer" j-console-execute-buffer t]
    ["Execute Region" j-console-execute-region t]
    ["Execute Line" j-console-execute-line t]
    "---"
    ["J Symbol Look-up" j-help-lookup-symbol t]
    ["J Symbol Dynamic Look-up" j-help-lookup-symbol-at-point t]
    ["Help on J-mode" describe-mode t]))

;;;###autoload
(define-derived-mode j-mode prog-mode "J"
  "Major mode for editing J"
  :group 'j
  :syntax-table j-font-lock-syntax-table
  (setq-local comment-start
              "NB. "
              comment-start-skip
              "\\(\\(^\\|[^\\\\\n]\\)\\(\\\\\\\\\\)*\\)NB. *"
              comment-column 40
              indent-tabs-mode nil
              indent-line-function #'j-indent-line
              font-lock-comment-start-skip
              "NB. *"
              font-lock-defaults
              '(j-font-lock-keywords
                nil nil nil nil
                ;;(font-lock-mark-block-function . mark-defun)
                (font-lock-syntactic-face-function
                 . j-font-lock-syntactic-face-function))))


;;;###autoload
(add-to-list 'auto-mode-alist '("\\.ij[rstp]$" . j-mode))

(provide 'j-mode)

;;; j-mode.el ends here
