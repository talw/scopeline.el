;;; scopeline.el --- Show scope info of blocks in buffer at end of scope -*- lexical-binding: t; -*-

;; URL: https://github.com/meain/scopeline.el
;; Keywords: scope, context, tree-sitter, convenience
;; SPDX-License-Identifier: Apache-2.0
;; Package-Requires: ((emacs "26.1") (tree-sitter "0.15.0"))
;; Version: 0.1

;;; Commentary:
;; This package lets you show the scope info of blocks like function
;; definitions, loops, conditions etc.  It does this by adding the
;; first line of these blocks at the end of the last char of that
;; block.  It makes use of `tree-sitter' to figure out block start and
;; end.
;;
;; The package exposes a single minor mode `scopeline-mode' which you
;; can use to enable or disable the functionality.
;;
;; Here is a sample `use-package' configuration
;;
;; (use-package scopeline
;;   :after tree-sitter
;;   :config (add-hook 'tree-sitter-mode-hook #'scopeline-mode))
;;
;; You can find more info in the README for the project at
;; https://github.com/meain/scopeline.el

;;; Code:
(require 'subr-x)
(require 'tree-sitter)

(defgroup scopeline nil
  "Show info about the block at the end of the block."
  :group 'tools)

(defvar-local scopeline--overlays '() "List to keep overlays applies in buffer.")
(defvar scopeline-overlay-prefix "  ¤ " "Prefix to use for overlay.")
(defvar scopeline-min-lines 5 "Minimum number of lines for block before we show scope info.")
(defface scopeline-face
  '((default :inherit font-lock-comment-face))
  "Face for showing scope info."
  :group 'blamer)
(defvar scopeline-targets ;; TODO: Add more language modes
  '(
    ;; TODO: Should this be more complex queries (for example gets
    ;; name of func for func) as it might look weird if only the
    ;; return type is on the first line in case of c-mode entries
    (c-mode . ("function_definition" "for_statement" "if_statement" "while_statement"))
    (css-mode . ("rule_set"))
    (go-mode . ("function_declaration" "func_literal" "method_declaration" "if_statement" "for_statement" "type_declaration"))
    (html-mode . ("element"))
    (javascript-mode . ("function" "function_declaration" "if_statement" "for_statement" "while_statement"))
    (js-mode . ("function" "function_declaration" "if_statement" "for_statement" "while_statement"))
    (js2-mode . ("function" "function_declaration" "if_statement" "for_statement" "while_statement"))
    (js3-mode . ("function" "function_declaration" "if_statement" "for_statement" "while_statement"))
    (json-mode . ("pair"))
    (mhtml-mode . ("element"))
    (nix-mode . ("bind"))
    (python-mode . ("function_definition" "if_statement" "for_statement"))
    (rust-mode . ("function_item" "for_expression" "if_expression"))
    (sh-mode . ("function_definition" "if_statement" "while_statement" "for_statement" "case_statement"))
    (yaml-mode . ("block_mapping_pair")))
  "Tree-sitter entities for scopeline target.")

(defun scopeline--add-overlay (pos text)
  "Add overlay at `POS' with the specified `TEXT'."
  (let ((ov (make-overlay pos pos)))
    (overlay-put ov 'after-string
                 (propertize (format "%s%s" scopeline-overlay-prefix text)
                             'face 'scopeline-face))
    ;; FIXME: If we have overlays at the same point, it does not get
    ;; added multiple times to the list but does get shown multiple
    ;; times in the buffer
    (add-to-list 'scopeline--overlays ov)))

(defun scopeline--delete-all-overlays ()
  "Delete all scopeline related overlays."
  (dolist (ov scopeline--overlays)
    (delete-overlay ov))
  (setq scopeline--overlays '()))

(defun scopeline--show ()
  "Show all the scopeline items in buffer."
  (when-let* ((scopeline-targets-for-mode (cdr (assq major-mode scopeline-targets)))
              (query-s (string-join
                        (seq-map (lambda (ct)
                                   (format "(%s) @entity" ct))
                                 scopeline-targets-for-mode)
                        "\n"))
              (query (tsc-make-query tree-sitter-language query-s))
              (root-node (tsc-root-node tree-sitter-tree))
              (matches (tsc-query-matches query root-node #'tsc--buffer-substring-no-properties)))
    (seq-map (lambda (x) ; TODO: seq-map might not be the best option here
               (let* ((entity (seq-elt (cdr x) 0))
                      (pos (tsc-node-byte-range (cdr entity)))
                      (start-pos (byte-to-position (car pos)))
                      (end-pos (byte-to-position (cdr pos)))
                      (start-line (line-number-at-pos start-pos))
                      (end-line (line-number-at-pos end-pos))
                      (line-difference (- end-line start-line)))
                 (if (> line-difference scopeline-min-lines)
                     (scopeline--add-overlay
                      (save-excursion
                        (goto-char end-pos)
                        (end-of-line)
                        (point))
                      (save-excursion
                        (goto-char start-pos)
                        (string-trim (thing-at-point 'line)))))))
             ;; Reversing the matches here so that it shows up in
             ;; correct order for indent based languages like python
             (reverse matches))))

;;;###autoload
(define-minor-mode scopeline-mode
  "Show scopeline of first line on last line."
  :lighter " scopeline"
  (if scopeline-mode
      (progn
        (add-hook 'tree-sitter-after-first-parse-hook #'scopeline--redisplay nil t)
        (add-hook 'tree-sitter-after-change-functions #'scopeline--redisplay nil t))
    (progn
      (remove-hook 'tree-sitter-after-change-functions #'scopeline--redisplay t)
      (scopeline--delete-all-overlays))))

(defun scopeline--redisplay (&rest _)
  "Re-display all the scopeline entries."
  (scopeline--delete-all-overlays)
  (scopeline--show))

(provide 'scopeline)
;;; scopeline.el ends here
