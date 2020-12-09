;;; igo-editor.el --- SGF(Go) Editor                -*- lexical-binding: t; -*-

;; Copyright (C) 2020  AKIYAMA Kouhei

;; Author: AKIYAMA Kouhei
;; Keywords: games

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; 

;;; Code:

(require 'igo-model)
(require 'igo-sgf-parser)
(require 'igo-view)

(defcustom igo-editor-move-point-on-click t
  "If non-nil, move point to editor clicked.")

(defcustom igo-editor-status-bar-visible t
  "If non-nil, status bar is displayed by default.")

;; Editor Management

(defun igo-edit-region (begin end)
  (interactive "r")

  (let ((editors (igo-editors-in begin end)))
    (cond
     ;; create a new editor
     ((null editors)
      (let ((editor (igo-editor begin end)))
        (overlay-put (igo-editor-overlay editor) 'evaporate t) ;; auto delete
        (igo-editor-update editor)))
     ;; change begin and end
     ((= (length editors) 1)
      (igo-editor-set-region (car editors) begin end)
      (igo-editor-update (car editors)))
     ;; (>= (length editors) 2)
     (t
      (error "Multiple editors already exist.")))))

(defun igo-editor-at (&optional pos)
  (if (null pos)
      (if (mouse-event-p last-input-event)
          (progn
            (setq pos (posn-point (event-start last-input-event)))
            (if igo-editor-move-point-on-click (goto-char pos)))
        (setq pos (point))))
  (or
   (seq-some (lambda (ov) (overlay-get ov 'igo-editor)) (overlays-at pos))
   (seq-some (lambda (ov) (overlay-get ov 'igo-editor)) (overlays-at (1- pos)))
   (seq-some (lambda (ov) (overlay-get ov 'igo-editor)) (overlays-in (1- pos) (1+ pos)))
   ))

(defun igo-editors-in (begin end)
  (delq nil (mapcar (lambda (ov) (overlay-get ov 'igo-editor))
                    (overlays-in begin end))))


;;
;; Editor Overlay Object
;;

(defun igo-editor (begin end &optional buffer front-advance rear-advance)
  "Create a new editor object."

  (let* ((ov (make-overlay begin end buffer front-advance rear-advance))
         (editor (vector
                  ov ;;0:overlay
                  nil ;;1:game
                  nil ;;2:board-view
                  nil ;;3:svg
                  1.0 ;;4:image-scale
                  (list nil) ;;5:image-map
                  nil ;;6:image
                  nil ;;7:buffer text last updated (see: update-buffer-text)
                  nil ;;8:last error
                  nil ;;9:text mode
                  nil ;;10:current mode
                  (list
                   :show-status-bar igo-editor-status-bar-visible
                   :show-branches t
                   :show-move-number nil
                   :show-last-move t
                   ;;:rotate180 nil
                   ) ;;11:properties
                  )))
    ;;(message "make overlay %s" ov)
    (overlay-put ov 'igo-editor editor)
    ;;(overlay-put-ov 'evaporate t)

    (igo-editor-text-mode editor t)

    (igo-editor-update editor)

    editor))

;; Editor - Basic Accessors

(defun igo-editor-overlay (editor) (aref editor 0))
(defun igo-editor-game (editor) (aref editor 1))
(defun igo-editor-board-view (editor) (aref editor 2))
(defun igo-editor-svg (editor) (aref editor 3))
(defun igo-editor-image-scale (editor) (aref editor 4))
(defun igo-editor-image-map (editor) (aref editor 5))
(defun igo-editor-image (editor) (aref editor 6))
(defun igo-editor-last-buffer-text (editor) (aref editor 7))
(defun igo-editor-last-error (editor) (aref editor 8))
(defun igo-editor-display-mode (editor) (aref editor 9))
(defun igo-editor-curr-mode (editor) (aref editor 10))
(defun igo-editor-properties (editor) (aref editor 11))

;;(defun igo-editor--overlay-set (editor ov) (aset editor 0 ov))
(defun igo-editor--game-set (editor game) (aset editor 1 game))
(defun igo-editor--board-view-set (editor view) (aset editor 2 view))
(defun igo-editor--svg-set (editor svg) (aset editor 3 svg))
(defun igo-editor--image-scale-set (editor scale) (aset editor 4 scale))
;;(defun igo-editor--image-map-set (editor image) (aset editor 5 image))
(defun igo-editor--image-set (editor image) (aset editor 6 image))
(defun igo-editor--last-buffer-text-set (editor text) (aset editor 7 text))
(defun igo-editor--last-error-set (editor err) (aset editor 8 err))
(defun igo-editor--display-mode-set (editor dmode) (aset editor 9 dmode))
(defun igo-editor--curr-mode-set (editor mode) (aset editor 10 mode))
(defun igo-editor--properties-set (editor props) (aset editor 11 props))

(defun igo-editor-begin (editor) (overlay-start (igo-editor-overlay editor)))
(defun igo-editor-end (editor) (overlay-end (igo-editor-overlay editor)))

(defun igo-editor-board (editor)
  (if editor
      (let ((game (igo-editor-game editor)))
        (if game
            (igo-game-board game)))))

(defun igo-editor-current-node (editor)
  (if editor
      (let ((game (igo-editor-game editor)))
        (if game
            (igo-game-current-node game)))))

;; Editor - Properties

(defun igo-editor-get-property (editor key)
  (if editor
      (plist-get (igo-editor-properties editor) key)))

(defun igo-editor-set-property (editor key value)
  (if editor
      (igo-editor--properties-set
       editor
       (plist-put (igo-editor-properties editor) key value))))

(defun igo-editor-toggle-property (editor key)
  (igo-editor-set-property
   editor
   key
   (not (igo-editor-get-property editor key))))

;; Editor - Keymaps

(defun igo-editor-set-keymap (editor keymap)
  (let ((ov (igo-editor-overlay editor)))
    (if ov
        (overlay-put ov 'keymap keymap))))

(defun igo-editor-self-insert-command ()
  (interactive))

(defvar igo-editor-text-mode-map
  (let ((km (make-sparse-keymap)))
    (define-key km (kbd "C-c q") #'igo-editor-quit)
    (define-key km (kbd "C-c g") #'igo-editor-graphical-mode)
    (define-key km (kbd "C-c i") #'igo-editor-init-board)
    km))

(defvar igo-editor-graphical-mode-map
  (let ((km (make-sparse-keymap)))
    (define-key km [remap self-insert-command] #'igo-editor-self-insert-command)
    (define-key km (kbd "C-c q") #'igo-editor-quit)
    ;; display mode
    (define-key km "t" #'igo-editor-text-mode)
    (define-key km (kbd "C-c g") #'igo-editor-text-mode)
    ;; navigation
    (define-key km "a" #'igo-editor-first-node)
    (define-key km "e" #'igo-editor-last-node)
    (define-key km "b" #'igo-editor-previous-node)
    (define-key km "f" #'igo-editor-next-node)
    (define-key km "n" #'igo-editor-select-next-node)
    (define-key km [igo-editor-first mouse-1] #'igo-editor-first-node)
    (define-key km [igo-editor-previous mouse-1] #'igo-editor-previous-node)
    (define-key km [igo-editor-forward mouse-1] #'igo-editor-next-node)
    (define-key km [igo-editor-last mouse-1] #'igo-editor-last-node)
    ;; editing mode
    (define-key km "Q" #'igo-editor-move-mode)
    (define-key km "F" #'igo-editor-free-edit-mode)
    (define-key km "M" #'igo-editor-mark-edit-mode)
    ;; visibility
    (define-key km (kbd "s s") #'igo-editor-toggle-status-bar)
    (define-key km (kbd "s n") #'igo-editor-toggle-move-number)
    (define-key km (kbd "s b") #'igo-editor-toggle-branch-text)
    ;; edit
    (define-key km "c" #'igo-editor-edit-comment)
    (define-key km (kbd "C-c i") #'igo-editor-init-board)
    ;; menu
    (define-key km [igo-editor-menu mouse-1] #'igo-editor-main-menu)
    km))

(defvar igo-editor-move-mode-map
  (let ((km (make-sparse-keymap)))
    (set-keymap-parent km igo-editor-graphical-mode-map)
    (define-key km "P" #'igo-editor-pass)
    (define-key km "p" #'igo-editor-put-stone)
    (define-key km [igo-editor-pass mouse-1] #'igo-editor-pass)
    (define-key km [igo-editor-pass mouse-3] #'igo-editor-pass-click-r)
    (define-key km [igo-grid mouse-1] #'igo-editor-move-mode-board-click)
    (define-key km [igo-grid mouse-3] #'igo-editor-move-mode-board-click-r)
    km))

(defvar igo-editor-free-edit-mode-map
  (let ((km (make-sparse-keymap)))
    (set-keymap-parent km igo-editor-graphical-mode-map)
    (define-key km [igo-grid mouse-1] #'igo-editor-free-edit-board-click)
    (define-key km [igo-grid mouse-3] #'igo-editor-free-edit-board-click-r)
    (define-key km [igo-editor-free-edit-quit mouse-1] #'igo-editor-move-mode)
    (define-key km [igo-editor-free-edit-black mouse-1] #'igo-editor-free-edit-black)
    (define-key km [igo-editor-free-edit-white mouse-1] #'igo-editor-free-edit-white)
    (define-key km [igo-editor-free-edit-empty mouse-1] #'igo-editor-free-edit-empty)
    (define-key km [igo-editor-free-edit-turn mouse-1] #'igo-editor-free-edit-toggle-turn)
    (define-key km "Q" #'igo-editor-move-mode)
    (define-key km "B" #'igo-editor-free-edit-black)
    (define-key km "W" #'igo-editor-free-edit-white)
    (define-key km "E" #'igo-editor-free-edit-empty)
    (define-key km "T" #'igo-editor-free-edit-toggle-turn)
    km))

(defvar igo-editor-mark-edit-mode-map
  (let ((km (make-sparse-keymap)))
    (set-keymap-parent km igo-editor-graphical-mode-map)
    (define-key km [igo-grid mouse-1] #'igo-editor-mark-edit-board-click)
    ;;(define-key km [igo-grid mouse-3] #'igo-editor-mark-edit-board-click-r)
    (define-key km [igo-editor-mark-edit-quit mouse-1] #'igo-editor-move-mode)
    (define-key km [igo-editor-mark-edit-cross mouse-1] #'igo-editor-mark-edit-cross)
    (define-key km [igo-editor-mark-edit-circle mouse-1] #'igo-editor-mark-edit-circle)
    (define-key km [igo-editor-mark-edit-square mouse-1] #'igo-editor-mark-edit-square)
    (define-key km [igo-editor-mark-edit-triangle mouse-1] #'igo-editor-mark-edit-triangle)
    (define-key km [igo-editor-mark-edit-text mouse-1] #'igo-editor-mark-edit-text)
    (define-key km [igo-editor-mark-edit-del mouse-1] #'igo-editor-mark-edit-del)
    (define-key km "Q" #'igo-editor-move-mode)
    (define-key km "X" #'igo-editor-mark-edit-cross)
    (define-key km "O" #'igo-editor-mark-edit-circle)
    (define-key km "S" #'igo-editor-mark-edit-square)
    (define-key km "T" #'igo-editor-mark-edit-triangle)
    (define-key km "E" #'igo-editor-mark-edit-text)
    (define-key km "D" #'igo-editor-mark-edit-del)
    km))

(defvar igo-editor-main-menu-map
  '(keymap "Main Menu"
           (igo-editor-toggle-status-bar menu-item "Toggle Status Bar" igo-editor-toggle-status-bar :button (:toggle . (igo-editor-get-property (igo-editor-at) :show-status-bar)))
           (igo-editor-toggle-move-number menu-item "Toggle Move Number" igo-editor-toggle-move-number :button (:toggle . (igo-editor-get-property (igo-editor-at) :show-move-number)))
           (igo-editor-toggle-branch-text menu-item "Toggle Branch Text" igo-editor-toggle-branch-text :button (:toggle . (igo-editor-get-property (igo-editor-at) :show-branches)))
           (sep-1 menu-item "--")
           (igo-editor-quit menu-item "Quit" igo-editor-quit)
           (sep-2 menu-item "--")
           (igo-editor-text-mode menu-item "Text Mode" igo-editor-text-mode)
           (igo-editor-free-edit-mode menu-item "Free Edit" igo-editor-free-edit-mode)
           (igo-editor-mark-edit-mode menu-item "Mark Edit" igo-editor-mark-edit-mode)
           (igo-editor-edit-comment menu-item "Edit Comment" igo-editor-edit-comment)
           ))

(defun igo-editor-main-menu (&optional editor)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))
  (if editor
      (let ((fn (car (last (x-popup-menu last-input-event igo-editor-main-menu-map)))))
        (if (and (symbolp fn) (fboundp fn))
            (funcall fn editor)))))

;; Editor - Update Editor

(defun igo-editor-set-region (editor begin end)
  "Resize editor's region."
  (move-overlay (igo-editor-overlay editor) begin end)
  (igo-editor-update editor))

(defun igo-editor-update (editor)
  "Update editor state from buffer text."
  (if (igo-editor-update-model editor)
      ;; Update image if graphical mode
      (if (igo-editor-graphical-mode-p editor)
          (igo-editor-update-image editor)))

  ;; Change display mode depending on error state
  (cond
   ;; Text(Auto Recovery) => Graphical
   ((igo-editor-text-mode-p editor)
    (if (and (igo-editor-text-mode-auto-recovery-p editor)
             (null (igo-editor-last-error editor)))
        (igo-editor-graphical-mode editor)))

   ;; Graphical => Text(Auto Recovery)
   ((igo-editor-graphical-mode-p editor)
    (if (igo-editor-last-error editor)
        (igo-editor-text-mode editor t)))))

(defun igo-editor-update-model (editor)
  "Update game, last-buffer-text, last-error from buffer text."
  (let* ((begin (igo-editor-begin editor))
         (end (igo-editor-end editor))
         (curr-text (buffer-substring-no-properties begin end)))
    (if (equal curr-text (igo-editor-last-buffer-text editor))
        ;; Return nil (not update)
        nil
      ;; Re-parse buffer text
      ;;(message "Parse buffer text %s %s" begin end)
      (condition-case err
          (let ((game (igo-editor-make-game-from-sgf-buffer begin end)))

            ;; Set current node
            (let ((old-game (igo-editor-game editor)))
              (if old-game
                  ;; Reproduce the board of old-game
                  (igo-game-redo-by-path
                   game
                   (igo-node-path-from-root (igo-game-current-node old-game)))
                ;; show first branch or last node
                (igo-game-redo-all game)))

            ;; Update game and text
            (igo-editor--game-set editor game)
            (igo-editor--last-buffer-text-set editor curr-text)
            (igo-editor--last-error-set editor nil)
            ;; Return t (update)
            t)
        ;; error
        (error
         (message "SGF error %s" (error-message-string err))
         (igo-editor--game-set editor nil)
         (igo-editor--last-buffer-text-set editor curr-text)
         (igo-editor--last-error-set editor (igo-editor-split-error editor err))
         ;; Return nil (not update)
         nil)))))

;; Editor - Update Buffer Text

(defun igo-editor-update-buffer-text (editor)
  "Reflect editor state to buffer text."
  (let* ((game (igo-editor-game editor))
         (ov (igo-editor-overlay editor)))
    (if (and game ov)
        (let ((text (igo-editor-game-to-sgf-string game))
              (begin (overlay-start ov))
              (end (overlay-end ov)))
          (when (not (string= text (buffer-substring-no-properties begin end))) ;;need to modify?
            ;; Record last update text
            (igo-editor--last-buffer-text-set editor text)
            ;; Replace text from BEGIN to END
            (igo-editor-replace-buffer-text begin end text))))))

(defun igo-editor-update-buffer-text-forced (editor &optional game)
  (igo-editor-replace-buffer-text
   (igo-editor-begin editor)
   (igo-editor-end editor)
   (igo-editor-game-to-sgf-string (or game (igo-editor-game editor)))))

(defun igo-editor-game-to-sgf-string (game)
  (igo-sgf-string-from-game-tree
   (igo-game-root-node game)
   (igo-board-w (igo-game-board game))
   (igo-board-h (igo-game-board game))
   'black))

(defun igo-editor-replace-buffer-text (begin end text)
  (save-excursion
    (goto-char begin)
    (insert text)
    (delete-region (point) (+ (point) (- end begin)))
    (if (equal (char-after) ?\n)
        (insert ?\n) )))

;; Editor - Error

(defun igo-editor-show-last-error (editor)
  (if (and editor (igo-editor-last-error editor))
      (let ((begin (igo-editor-last-error-begin editor))
            (end (igo-editor-last-error-end editor))
            (msg (igo-editor-last-error-message editor)))
        (if (= begin end)
            (message "%s: %s" begin msg)
          (message "%s-%s: %s" begin end msg)))))

(defun igo-editor-split-error (editor err)
  "Return ((begin-relative . end-relative) . message)"
  (if err
      (let ((err-str (error-message-string err)))
        ;; <msg>
        ;; <point>: <msg>
        ;; <begin>-<end>: <msg>
        (if (string-match "^\\(\\([0-9]+\\)\\(-\\([0-9]+\\)\\)?:\\)? *\\(.*\\)$" err-str)
            (let* ((editor-begin (igo-editor-begin editor))
                   (begin-str (match-string-no-properties 2 err-str))
                   (end-str (match-string-no-properties 4 err-str))
                   (begin (if begin-str (- (string-to-number begin-str)
                                           editor-begin)))
                   (end (if end-str (- (string-to-number end-str)
                                       editor-begin)))
                   (msg (match-string-no-properties 5 err-str)))

              ;; ((begin-relative . end-relative) . message)
              (cons
               (cond
                ((and begin end) (cons begin end))
                (begin (cons begin (1+ begin)))
                (t (cons 0 (- (igo-editor-end editor) (igo-editor-begin editor)))))
               msg))))))

(defun igo-editor-last-error-begin (editor)
  (+ (caar (igo-editor-last-error editor)) (igo-editor-begin editor)))
(defun igo-editor-last-error-end (editor)
  (+ (cdar (igo-editor-last-error editor)) (igo-editor-begin editor)))
(defun igo-editor-last-error-message (editor)
  (cdr (igo-editor-last-error editor)))


;; Editor - Display Mode(Text or Graphical)

(defun igo-editor-text-mode-p (editor)
  (or
   (eq (igo-editor-display-mode editor) 'text)
   (eq (igo-editor-display-mode editor) 'text-auto-recovery)))

(defun igo-editor-text-mode-auto-recovery-p (editor)
  (eq (igo-editor-display-mode editor) 'text-auto-recovery))

(defun igo-editor-graphical-mode-p (editor)
  (eq (igo-editor-display-mode editor) 'graphical))

(defun igo-editor-text-mode (&optional editor auto-recovery)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))
  (when (and editor (not (igo-editor-text-mode-p editor)))
    (let ((ov (igo-editor-overlay editor)))
      (igo-editor-mode-set editor nil) ;;clear editing mode
      (overlay-put ov 'display nil)
      (igo-editor-set-keymap editor igo-editor-text-mode-map)
      (igo-editor--svg-set editor nil)
      (igo-editor--image-set editor nil)
      (igo-editor--display-mode-set
       editor (if auto-recovery 'text-auto-recovery 'text)))))

(defun igo-editor-graphical-mode (&optional editor)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))
  (when (and editor
             (not (igo-editor-graphical-mode-p editor)))
    (if (igo-editor-last-error editor)
        (igo-editor-show-last-error editor)

      (igo-editor--display-mode-set editor 'graphical)
      (igo-editor-update-image editor)
      (igo-editor-set-keymap editor igo-editor-graphical-mode-map) ;;Unnecessary? (set keymap in start move mode)
      (igo-editor-move-mode editor))))

;; Editor - Image

(defun igo-editor-status-bar-top (editor)
  0)
(defun igo-editor-board-top (editor)
  (if (igo-editor-get-property editor :show-status-bar)
      igo-ui-bar-h 0))
(defun igo-editor-board-pixel-h (editor)
  (igo-board-view-pixel-h (igo-editor-board-view editor)))
(defun igo-editor-main-bar-top (editor)
  (+ (igo-editor-board-top editor)
     (igo-editor-board-pixel-h editor)))
(defun igo-editor-image-h (editor)
  (ceiling
   (* (igo-editor-image-scale editor)
      (+ (igo-editor-main-bar-top editor)
         igo-ui-bar-h))))
(defun igo-editor-board-pixel-w (editor)
  (igo-board-view-pixel-w (igo-editor-board-view editor)))
(defun igo-editor-image-w (editor)
  (ceiling
   (* (igo-editor-image-scale editor)
      (igo-editor-board-pixel-w editor))))

(defun igo-editor-update-image (editor &optional recreate)
  "Update svg, image, overlay from game model."
  (let ((game (igo-editor-game editor))
        (board (igo-editor-board editor))
        (board-view (igo-editor-board-view editor))
        (svg (igo-editor-svg editor))
        (image-map (igo-editor-image-map editor))
        (image-scale (igo-editor-image-scale editor)))
    (when game
      ;; Create a new SVG Tree
      (when (or recreate
                (null svg)
                ;; Board size changed
                (or
                 (null board-view)
                 (/= (igo-board-view-w board-view) (igo-board-w board))
                 (/= (igo-board-view-h board-view) (igo-board-h board))))
        ;; Determine Scaling Factor
        (setq image-scale (image-compute-scaling-factor image-scaling-factor))
        (igo-editor--image-scale-set editor image-scale)

        ;; New Board View (Determine grid interval and board pixel sizes)
        (setq board-view (igo-board-view board))
        (igo-editor--board-view-set editor board-view)

        ;; New SVG Root
        (setq svg (svg-create (igo-editor-image-w editor)
                              (igo-editor-image-h editor)
                              :transform (format "scale(%s)" image-scale)))
        (igo-editor--svg-set editor svg)
        ;; Clear clickable areas
        (igo-editor-clear-image-map editor)

        ;; Initialize SVG Parts
        (if (igo-editor-get-property editor :show-status-bar)
            (igo-editor-create-status-bar editor svg board))
        (igo-editor-create-svg-board editor svg board-view image-map image-scale)
        (igo-editor-create-navi-bar editor))

      ;; Update game status
      (if (igo-editor-get-property editor :show-status-bar)
          (igo-editor-update-status-bar editor svg board game))

      ;; Update intersections
      (igo-board-view-update-stones board-view svg board)

      (igo-board-view-update-move-numbers
       board-view svg
       (igo-editor-get-property editor :show-move-number)
       game)

      (igo-editor-update-branches-text editor)

      (igo-board-view-update-last-move-mark
       board-view svg
       (and (igo-editor-get-property editor :show-last-move)
            (not (igo-editor-get-property editor :show-move-number)))
       game)

      (igo-board-view-update-marks board-view svg t game)

      ;; Update image descriptor & display property
      (let ((image (svg-image svg :scale 1.0 :map (car image-map))))
        (overlay-put (igo-editor-overlay editor) 'display image)
        (igo-editor--image-set editor image)))))

(defun igo-editor-clear-image-map (editor)
  (setcar (igo-editor-image-map editor) nil))

(defun igo-editor-create-svg-board (editor svg board-view image-map image-scale)
  (igo-board-view-create-board board-view svg 0 (igo-editor-board-top editor))
  (igo-ui-push-clickable-rect
   image-map
   'igo-grid
   (igo-board-view-clickable-left board-view)
   (igo-board-view-clickable-top board-view (igo-editor-board-top editor))
   (igo-board-view-clickable-width board-view)
   (igo-board-view-clickable-height board-view)
   image-scale))

(defun igo-editor-create-status-bar (editor svg board)
  (let* ((bar-w (igo-editor-board-pixel-w editor))
         (bar (igo-ui-create-bar svg
                                 0
                                 (igo-editor-status-bar-top editor)
                                 bar-w
                                 "status-bar")))
    (svg-circle
     bar
     (- bar-w (/ igo-ui-bar-h 2))
     (/ igo-ui-bar-h 2)
     (/ (* 3 igo-ui-bar-h) 10)
     :gradient "stone-black"
     :id "status-stone-b")
    (svg-circle
     bar
     (/ igo-ui-bar-h 2)
     (/ igo-ui-bar-h 2)
     (/ (* 3 igo-ui-bar-h) 10)
     :gradient "stone-white"
     :id "status-stone-w")
    ))

(defun igo-editor-update-status-bar (editor svg board game)
  (let ((bar (car (dom-by-id svg "^status-bar$"))))
    (when bar
      (let* ((bar-w (igo-editor-board-pixel-w editor))
             (bar-y 0)
             (turn-line-h 4)
             (text-y (+ bar-y (/ (- igo-ui-bar-h igo-ui-font-h) 2) igo-ui-font-ascent))
             (w-prisoners (igo-board-get-prisoners board 'white))
             (b-prisoners (igo-board-get-prisoners board 'black)))
        ;; Turn
        (svg-rectangle
         bar
         (if (igo-black-p (igo-game-turn game))
             (- bar-w igo-ui-bar-h)
           0)
         (+ bar-y (- igo-ui-bar-h turn-line-h))
         igo-ui-bar-h turn-line-h :fill "#f00" :id "status-turn")
        ;; Prisoners(Captured Stones)
        (if (> b-prisoners 0)
            (svg-text
             bar
             (number-to-string b-prisoners)
             :x (+ igo-ui-bar-h (/ igo-ui-bar-h 8))
             :y text-y
             :font-family igo-ui-font-family :font-size igo-ui-font-h
             :text-anchor "start" :fill "#fff" :id "status-prisoners-w")
          (let ((n (car (dom-by-id bar "status-prisoners-w"))))
            (if n (dom-remove-node bar n))))
        (if (> w-prisoners 0)
            (svg-text
             bar
             (number-to-string w-prisoners)
             :x (- bar-w igo-ui-bar-h (/ igo-ui-bar-h 8))
             :y text-y
             :font-family igo-ui-font-family :font-size igo-ui-font-h
             :text-anchor "end" :fill "#fff" :id "status-prisoners-b")
          (let ((n (car (dom-by-id bar "status-prisoners-b"))))
            (if n (dom-remove-node bar n))))
        ;; Move Number
        (svg-text
         bar
         (number-to-string (1+ (igo-node-move-number (igo-game-current-node game))))
         :x (/ bar-w 2)
         :y text-y
         :font-family igo-ui-font-family :font-size igo-ui-font-h
         :text-anchor "middle" :fill "#fff" :id "status-move-number")
        ))))

(defun igo-editor-update-branches-text (editor)
  (let* ((game (igo-editor-game editor))
         (board (igo-game-board game))
         (board-view (igo-editor-board-view editor))
         (svg (igo-editor-svg editor))
         (image-map (igo-editor-image-map editor))
         (curr-node (igo-game-current-node game)))
    (igo-board-view-update-branches
     board-view
     svg
     (igo-editor-get-property editor :show-branches)
     board curr-node
     ;; called when branch is pass
     (lambda (index num-nodes text text-color turn class-name)
       (igo-editor-put-branch-text-on-button
        svg image-map board-view 'igo-editor-pass text text-color turn class-name)))))

(defun igo-editor-put-branch-text-on-button (svg image-map board-view button-id text text-color turn class-name)
  (let ((xy (igo-ui-left-top-of-clickable-area image-map button-id)))
    (if xy
        (let* ((grid-interval (igo-board-view-interval board-view))
               (font-size (igo-svg-font-size-on-board grid-interval))
               (x (+ (car xy) (/ font-size 2)))
               (y (cdr xy))
               (group (svg-node svg 'g :class class-name)))
          (svg-rectangle group
                         (- x (/ font-size 2))
                         (- y (/ font-size 2))
                         font-size font-size
                         :fill (if (igo-black-p turn) "#ccc" "#444"))
          (igo-svg-text-on-board group x y grid-interval text text-color)))))


(defun igo-editor-set-property-and-update-image
    (editor key value &optional recreate)
  (if (null editor) (setq editor (igo-editor-at)))
  (when editor
    (igo-editor-set-property editor key value)
    (igo-editor-update-image editor recreate)))

(defun igo-editor-toggle-property-and-update-image
    (editor key &optional recreate)
  (if (null editor) (setq editor (igo-editor-at)))
  (when editor
    (igo-editor-set-property-and-update-image
     editor
     key
     (not (igo-editor-get-property editor key))
     recreate)))

(defun igo-editor-set-status-bar-visible (editor visible)
  ;;needs recreate image
  (igo-editor-set-property-and-update-image editor :show-status-bar visible t))

(defun igo-editor-set-move-number-visible (editor visible)
  (igo-editor-set-property-and-update-image editor :show-move-number visible))

(defun igo-editor-set-branch-text-visible (editor visible)
  (igo-editor-set-property-and-update-image editor :show-branches visible))

(defun igo-editor-toggle-status-bar (&optional editor)
  (interactive)
  (igo-editor-toggle-property-and-update-image
   editor :show-status-bar t));;needs recreate image

(defun igo-editor-toggle-move-number (&optional editor)
  (interactive)
  (igo-editor-toggle-property-and-update-image
   editor :show-move-number))

(defun igo-editor-toggle-branch-text (&optional editor)
  (interactive)
  (igo-editor-toggle-property-and-update-image
   editor :show-branches))

;; Editor - Input on Image

(defun igo-editor-last-input-event-as-intersection-click (&optional editor)
  (if (null editor) (setq editor (igo-editor-at)))
  (if editor
      (let ((game (igo-editor-game editor))
            (board-view (igo-editor-board-view editor)))
        (if (and game
                 board-view
                 (mouse-event-p last-input-event))
            (let* ((board (igo-game-board game))
                   (image-scale (igo-editor-image-scale editor))
                   (xy (posn-object-x-y (event-start last-input-event)))
                   (x (igo-board-view-to-grid-x board-view (round (/ (float (car xy)) image-scale))))
                   (y (igo-board-view-to-grid-y board-view (round (/ (float (cdr xy)) image-scale))
                                                (igo-editor-board-top editor))))

              (when (and (>= x 0)
                         (>= y 0)
                         (< x (igo-board-w board))
                         (< y (igo-board-h board)))
                (list :pos (igo-board-xy-to-pos board x y)
                      :x x
                      :y y
                      :editor editor)))))))

;; Editor - Destroy

(defun igo-editor-quit (&optional editor)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))
  (if editor
      (delete-overlay (igo-editor-overlay editor))))

;; Editor - Navigation

(defun igo-editor-previous-node ()
  "Move current node to previous node."
  (interactive)
  (let ((editor (igo-editor-at)))
    (if editor
        (let ((game (igo-editor-game editor)))
          (when game
            (igo-game-undo game)
            (igo-editor-update-image editor)
            (igo-editor-show-comment editor))))))

(defun igo-editor-next-node ()
  "Move current node to next node."
  (interactive)
  (let ((editor (igo-editor-at)))
    (if editor
        (let ((game (igo-editor-game editor)))
          (when game
            (cond
             ;; Default node (last visited or only 1 node)
             ((igo-node-next-node-default (igo-game-current-node game))
              (igo-game-redo game)
              (igo-editor-update-image editor)
              (igo-editor-show-comment editor))
             ;; Select node
             ;;((>= (length (igo-node-next-nodes (igo-game-current-node game))) 2)
             ;; (igo-editor-select-next-node editor))
             ))))))

(defun igo-editor-first-node ()
  "Move current node to first (root) node."
  (interactive)
  (let ((editor (igo-editor-at)))
    (if editor
        (let ((game (igo-editor-game editor)))
          (when game
            (igo-game-undo-all game)
            (igo-editor-update-image editor)
            (igo-editor-show-comment editor))))))

(defun igo-editor-last-node ()
  "Move current node to last node that can be selected by default."
  (interactive)
  (let ((editor (igo-editor-at)))
    (if editor
        (let ((game (igo-editor-game editor)))
          (when game
            (igo-game-redo-all game)
            (igo-editor-update-image editor)
            (igo-editor-show-comment editor))))))

(defun igo-editor-select-next-node (&optional editor)
  "Move current node to selected next node."
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))
  (let* ((game (if editor (igo-editor-game editor))))
    (if game
        (let* ((curr-node (igo-game-current-node game))
               (next-nodes (igo-node-next-nodes curr-node))
               (num-next-nodes (length next-nodes)))

          (cond
           ((= num-next-nodes 0)
            (message "There is no next node."))

           ((= num-next-nodes 1)
            (igo-game-apply-node game (car next-nodes))
            (igo-editor-update-image editor)
            (igo-editor-show-comment editor))

           ((>= num-next-nodes 2)
            (let* ((ch (read-char (format "Select next node (%c-%c): "
                                          ?A (+ ?A num-next-nodes -1))))
                   (index (- (downcase ch) ?a)))
              (if (and (>= index 0) (< index num-next-nodes))
                  (progn
                    (igo-game-apply-node game (nth index next-nodes))
                    (igo-editor-update-image editor)
                    (igo-editor-show-comment editor))
                (message "Out of range.")))))))))

;; Editor - Modified

(defun igo-editor-update-on-modified (editor)
  (igo-editor-update-image editor)
  (igo-editor-update-buffer-text editor))

;; Editor - Editing Mode

(defconst igo-editor-mode-idx-start 0)
(defconst igo-editor-mode-idx-stop 1)
(defconst igo-editor-mode-idx-properties 2)

(defun igo-editor-mode-create (start stop &optional properties)
  (vector start stop properties))

(defun igo-editor-mode-set (editor mode)
  ;; stop current mode
  (let ((curr-mode (igo-editor-curr-mode editor)))
    (when curr-mode
      (funcall (aref curr-mode igo-editor-mode-idx-stop) editor curr-mode)
      (igo-editor--curr-mode-set editor nil)))
  ;; start current mode
  (when mode
    (funcall (aref mode igo-editor-mode-idx-start) editor mode)
    (igo-editor--curr-mode-set editor mode)))

(defun igo-editor-mode-set-property (mode key value)
  (let ((cell (assq key (aref mode igo-editor-mode-idx-properties))))
    (if cell
        (setcdr cell value)
      (aset mode igo-editor-mode-idx-properties
            (cons (cons key value)
                  (aref mode igo-editor-mode-idx-properties))))))

(defun igo-editor-mode-get-property (mode key)
  (cdr (assq key (aref mode igo-editor-mode-idx-properties))))

(defun igo-editor-set-mode-property (editor key value)
  (if editor
      (let ((mode (igo-editor-curr-mode editor)))
        (if mode
            (igo-editor-mode-set-property mode key value)))))

(defun igo-editor-get-mode-property (editor key)
  (if editor
      (let ((mode (igo-editor-curr-mode editor)))
        (if mode
            (igo-editor-mode-get-property mode key)))))


;; Editor - Move Mode

(defun igo-editor-move-mode (&optional editor)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))

  (when editor
    (igo-editor-mode-set
     editor
     (igo-editor-mode-create
      #'igo-editor-move-mode-start
      #'igo-editor-move-mode-stop
      nil))
    (igo-editor-update-image editor)))

(defun igo-editor-move-mode-start (editor mode)
  (igo-editor-set-keymap editor igo-editor-move-mode-map)
  (igo-editor-create-navi-bar editor)
  (message "Move Mode"))

(defun igo-editor-move-mode-stop (editor mode)
  (igo-editor-set-keymap editor igo-editor-graphical-mode-map))

(defun igo-editor-create-navi-bar (editor)
  (let ((svg (igo-editor-svg editor))
        (board (igo-editor-board editor))
        (image-map (igo-editor-image-map editor))
        (image-scale (igo-editor-image-scale editor)))
    (when (and svg board image-map)
      (igo-ui-remove-clickable-areas-under image-map
                                           (car (dom-by-id svg "^main-bar$")))
      (let* ((bar-y (igo-editor-main-bar-top editor))
             (bar (igo-ui-create-bar svg 0 bar-y (igo-editor-board-pixel-w editor)
                                     "main-bar"))
             (pos (cons igo-ui-bar-padding-h (+ bar-y igo-ui-bar-padding-v))))
        (igo-ui-create-button bar 'igo-editor-menu pos "Menu" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-first pos "|<" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-previous pos " <" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-forward pos "> " image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-last pos ">|" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-pass pos "Pass" image-map image-scale)
        ;;(igo-ui-create-button bar 'igo-editor-resign pos "Resign" image-map image-scale)
        ))))

(defun igo-editor-move-mode-board-click ()
  (interactive)
  (let* ((ev (igo-editor-last-input-event-as-intersection-click)))
    (if ev ;;editor and game are not null
        (igo-editor-put-stone
         (plist-get ev :editor)
         (plist-get ev :pos)))))

(defun igo-editor-move-mode-board-click-r ()
  (interactive)
  (let* ((ev (igo-editor-last-input-event-as-intersection-click)))
    (if ev ;;editor and game are not null
        (let* ((editor (plist-get ev :editor))
               (pos (plist-get ev :pos))
               (game (igo-editor-game editor))
               (curr-node (igo-game-current-node game))
               (clicked-node (seq-find (lambda (nn) (= (igo-node-move nn) pos))
                                       (igo-node-next-nodes curr-node))))
          (if clicked-node
              (igo-editor-move-mode-branch-click-r editor curr-node clicked-node)
)))))

(defun igo-editor-pass-click-r ()
  (interactive)
  (let* ((editor (igo-editor-at))
         (curr-node (igo-editor-current-node editor)))
    (if curr-node
        (igo-editor-move-mode-branch-click-r
         editor curr-node (igo-node-find-next-by-move curr-node igo-pass)))))

(defun igo-editor-move-mode-branch-click-r (editor curr-node clicked-node)
  (if (and editor curr-node clicked-node)
      (let ((fun (x-popup-menu
                  last-input-event
                  `("Branch"
                    ("Branch"
                     ("Put Here" .
                      ,(lambda ()
                         (igo-game-apply-node (igo-editor-game editor) clicked-node)))
                     ("Delete This Branch" .
                      ,(lambda ()
                         (igo-node-delete-next curr-node clicked-node)
                         t))
                     ("Change Order to Previous" .
                      ,(lambda ()
                         (igo-node-change-next-node-order curr-node clicked-node -1)))
                     ("Change Order to Next" .
                      ,(lambda ()
                         (igo-node-change-next-node-order curr-node clicked-node 1))))))))
        (when (and fun (funcall fun))
          (igo-editor-update-on-modified editor)))))

(defun igo-editor-put-stone (editor pos)
  (interactive
   (let* ((editor (igo-editor-at))
          (board (igo-editor-board editor)))
     (if (null board) (error "No game board."))

     (let ((xy-str (read-string (format "Input X(1-%s) Y(1-%s): "
                                        (igo-board-w board)
                                        (igo-board-h board)))))
       (if (string-match "^ *\\([0-9]+\\) +\\([0-9]+\\)" xy-str)
           (let ((x (1- (string-to-number (match-string 1 xy-str))))
                 (y (1- (string-to-number (match-string 2 xy-str)))))
             (if (and (>= x 0) (>= y 0) (< x (igo-board-w board)) (< y (igo-board-h board)))
                 (list editor (igo-board-xy-to-pos board x y))
               (error "Out of board.")))
         (error "Invalid coordinate.")))))

  (if (null editor) (setq editor (igo-editor-at)))

  (let ((game (if editor (igo-editor-game editor))))
    (when game

      ;; insert text to buffer
      ;; (if (igo-game-legal-move-p game pos)
      ;;     (let* ((curr-node (igo-game-current-node game))
      ;;            (curr-loc (igo-node-get-sgf-location curr-node)))
      ;;       (if (and (null (igo-node-find-next-by-move curr-node move))
      ;;                curr-loc)
      ;;           ;;    (;B[AA];W[BB]) Insert CC&DD after BB
      ;;           ;; => (;B[AA];W[BB];B[CC];W[DD])

      ;;           ;;    (;B[AA];W[BB];B[CC];W[DD]) Insert DD after BB
      ;;           ;; => (;B[AA];W[BB](;B[CC];W[DD])(;B[DD]))

      ;;           ;;    (;B[AA];W[BB](;B[CC];W[DD])(;B[DD])) Insert EE after BB
      ;;           ;; => (;B[AA];W[BB](;B[CC];W[DD])(;B[DD])(;B[EE]))

      ;;           (if (null (igo-node-next-nodes node))
      ;;               (save-excursion
      ;;                 (goto-char (igo-node-sgf-end curr-loc))
      ;;                 (insert 
      ;;                  (concat ";" (if (igo-black-p turn) "B" "W") "[" "]"))))
      ;;           )))

      ;; put stone to game object
      ;;    (if (igo-editor-set-intersection-setup-at editor pos 'black)

      (if (igo-game-put-stone game pos)
          (progn
            (if (not (igo-editor-show-comment editor))
                (message "Put at %s %s"
                         (1+ (igo-board-pos-to-x (igo-game-board game) pos))
                         (1+ (igo-board-pos-to-y (igo-game-board game) pos))))
            (igo-editor-update-on-modified editor))
        (message "Ilegal move."))
      )))

(defun igo-editor-pass (&optional editor)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))

  (when editor
    (let* ((game (igo-editor-game editor)))
      (if (igo-game-pass game)
          (progn
            (message "Pass")
            (igo-editor-show-comment editor)
            (igo-editor-update-on-modified editor))
        (message "ilegal move."))
      )))

;; Editor - Free Edit Mode

(defun igo-editor-free-edit-mode (&optional editor istate)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))

  (when editor
    (igo-editor-mode-set
     editor
     (igo-editor-mode-create
      #'igo-editor-free-edit-mode-start
      #'igo-editor-free-edit-mode-stop
      (list
       (cons :istate (or istate 'black)))
      ) )
    (igo-editor-update-image editor)))

(defun igo-editor-free-edit-mode-start (editor mode)
  (igo-editor-set-keymap editor igo-editor-free-edit-mode-map)
  (igo-editor-create-free-edit-bar editor)
  (message "Free Edit Mode"))

(defun igo-editor-free-edit-mode-stop (editor mode)
  (igo-editor-set-keymap editor igo-editor-graphical-mode-map))

(defun igo-editor-create-free-edit-bar (editor)
  (let ((svg (igo-editor-svg editor))
        (board (igo-editor-board editor))
        (image-map (igo-editor-image-map editor))
        (image-scale (igo-editor-image-scale editor)))
    (when (and svg board image-map)
      (igo-ui-remove-clickable-areas-under image-map
                                           (car (dom-by-id svg "^main-bar$")))
      (let* ((bar-y (igo-editor-main-bar-top editor))
             (bar (igo-ui-create-bar svg 0 bar-y (igo-editor-board-pixel-w editor)
                                     "main-bar"))
             (pos (cons igo-ui-bar-padding-h (+ bar-y igo-ui-bar-padding-v))))
        (igo-ui-create-button bar 'igo-editor-free-edit-quit pos "Quit" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-free-edit-black pos "Black" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-free-edit-white pos "White" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-free-edit-empty pos "Empty" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-free-edit-turn pos "Turn" image-map image-scale)
        ))))

(defun igo-editor-free-edit-select (istate)
  (igo-editor-set-mode-property (igo-editor-at) :istate istate)
  (message "Select %s" (symbol-name istate)))

(defun igo-editor-free-edit-black ()
  (interactive)
  (igo-editor-free-edit-select 'black))

(defun igo-editor-free-edit-white ()
  (interactive)
  (igo-editor-free-edit-select 'white))

(defun igo-editor-free-edit-empty ()
  (interactive)
  (igo-editor-free-edit-select 'empty))

(defun igo-editor-free-edit-board-click ()
  (interactive)
  (let ((ev (igo-editor-last-input-event-as-intersection-click)))
    (if ev
        (let* ((editor (plist-get ev :editor))
               (pos (plist-get ev :pos))
               (game (igo-editor-game editor)))
          (if game
              (igo-editor-edit-intersection editor pos))))))

(defun igo-editor-edit-intersection (editor pos)
  (if (igo-editor-set-intersection-setup-at
       editor pos
       (igo-editor-get-mode-property editor :istate))
      (igo-editor-update-on-modified editor)
    (message "not changed")))

(defun igo-editor-set-intersection-setup-at (editor pos istate)
  "Add stone to setup property of current node."
  (igo-editor-set-setup-value
   editor
   istate
   #'igo-same-intersection-state-p
   (lambda (changes) (igo-board-changes-get-at changes pos))
   (lambda (game) (igo-board-get-at (igo-game-board game) pos))
   (lambda (changes istate) (igo-board-changes-set-at changes pos istate))
   (lambda (game istate) (igo-board-set-at (igo-game-board game) pos istate))
   (lambda (changes) (igo-board-changes-delete-at changes pos))
   'empty))

(defun igo-editor-free-edit-toggle-turn (&optional editor)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))
  (if editor
      (let ((game (igo-editor-game editor)))
        (if game
            (if (igo-editor-set-turn-setup
                 editor (igo-opposite-color (igo-game-turn game)))
                (progn
                  (igo-editor-update-on-modified editor)
                  (message "%s's turn."
                           (if (igo-black-p (igo-game-turn game))
                               "black" "white")))
              (message "Failed to change turn"))))))

(defun igo-editor-set-turn-setup (editor color)
  "Set turn to setup property of current node."
  (igo-editor-set-setup-value
   editor
   color
   #'igo-same-color-p
   #'igo-board-changes-turn
   #'igo-game-turn
   #'igo-board-changes-turn-set
   #'igo-game-set-turn
   (lambda (changes) (igo-board-changes-turn-set changes nil))
   'black))

(defun igo-editor-set-setup-value (editor
                                   new-value
                                   same-value-p
                                   get-from-changes
                                   get-from-game
                                   set-to-changes
                                   set-to-game
                                   delete-from-changes
                                   initial-value)
  "Add setup value to setup property of current node."
  (let* ((game (igo-editor-game editor))
         (curr-node (igo-game-current-node game)))

    ;; Ensure current node is a setup node
    ;;@todo insert setup node
    (if (not (igo-node-setup-p curr-node))
        (error "Not root node."))

    (when (igo-node-setup-p curr-node)

      (let* ((setup-changes (igo-node-get-setup-property curr-node))
             (undo-changes (igo-game-get-undo-board-changes game))
             (setup-value (funcall get-from-changes setup-changes)))

        (if setup-value
            ;; value change is already in setup changes
            ;; undo-value => curr-value == setup-value => new-value
            (when (not (funcall same-value-p new-value setup-value))
              (let ((undo-value (or (funcall get-from-changes undo-changes)
                                    initial-value)))
                ;; modify setup&undo changes
                (if (and undo-value (funcall same-value-p new-value undo-value))
                    ;; (new-value == undo-value)
                    ;; delete change value
                    (progn
                      (funcall delete-from-changes setup-changes)
                      (funcall delete-from-changes undo-changes)
                      ;;@todo erase setup node? (if empty)(if non-root)
                      ;; (if (igo-board-changes-empty-p setup-changes)
                      ;;     )
                      )
                  ;; (new-value != undo-value)
                  ;; modify setup change, keep undo change
                  (funcall set-to-changes setup-changes new-value))
                ;; modify game value
                (funcall set-to-game game new-value)
                t))

          ;; value change is not in setup changes
          ;; curr-value => new-value
          (let ((curr-value (funcall get-from-game game)))
            (when (not (funcall same-value-p new-value curr-value))
              ;; create new setup-changes
              (if (null setup-changes)
                  (igo-node-set-setup-property
                   curr-node
                   (setq setup-changes
                         (igo-board-changes nil nil nil nil nil nil nil))))
              ;; add change for setup&undo
              (funcall set-to-changes setup-changes new-value)
              (funcall set-to-changes undo-changes curr-value)
              (funcall set-to-game game new-value)
              t)))))))

;; Editor - Mark Edit Mode

(defun igo-editor-mark-edit-mode (&optional editor)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))

  (when editor
    (igo-editor-mode-set
     editor
     (igo-editor-mode-create
      #'igo-editor-mark-edit-mode-start
      #'igo-editor-mark-edit-mode-stop
      (list
       (cons :mark-type 'cross))
      ) )
    (igo-editor-update-image editor)))

(defun igo-editor-mark-edit-mode-start (editor mode)
  (igo-editor-set-keymap editor igo-editor-mark-edit-mode-map)
  (igo-editor-create-mark-edit-bar editor)
  (message "Mark Edit Mode"))

(defun igo-editor-mark-edit-mode-stop (editor mode)
  (igo-editor-set-keymap editor igo-editor-graphical-mode-map))

(defun igo-editor-create-mark-edit-bar (editor)
  (let ((svg (igo-editor-svg editor))
        (board (igo-editor-board editor))
        (image-map (igo-editor-image-map editor))
        (image-scale (igo-editor-image-scale editor)))
    (when (and svg board image-map)
      (igo-ui-remove-clickable-areas-under image-map
                                           (car (dom-by-id svg "^main-bar$")))
      (let* ((bar-y (igo-editor-main-bar-top editor))
             (bar (igo-ui-create-bar svg 0 bar-y (igo-editor-board-pixel-w editor)
                                     "main-bar"))
             (pos (cons igo-ui-bar-padding-h (+ bar-y igo-ui-bar-padding-v))))
        (igo-ui-create-button bar 'igo-editor-mark-edit-quit pos "Quit" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-mark-edit-cross pos "X" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-mark-edit-circle pos "O" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-mark-edit-square pos "SQ" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-mark-edit-triangle pos "TR" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-mark-edit-text pos "tExt" image-map image-scale)
        (igo-ui-create-button bar 'igo-editor-mark-edit-del pos "Del" image-map image-scale)
        ))))

(defun igo-editor-mark-edit-select (mark-type)
  (igo-editor-set-mode-property (igo-editor-at) :mark-type mark-type)
  (message "Select %s mark" (if (null mark-type) "delete"
                         (symbol-name mark-type))))

(defun igo-editor-mark-edit-cross ()
  (interactive)
  (igo-editor-mark-edit-select 'cross))

(defun igo-editor-mark-edit-circle ()
  (interactive)
  (igo-editor-mark-edit-select 'circle))

(defun igo-editor-mark-edit-square ()
  (interactive)
  (igo-editor-mark-edit-select 'square))

(defun igo-editor-mark-edit-triangle ()
  (interactive)
  (igo-editor-mark-edit-select 'triangle))

(defun igo-editor-mark-edit-text ()
  (interactive)
  (igo-editor-mark-edit-select 'text))

(defun igo-editor-mark-edit-del ()
  (interactive)
  (igo-editor-mark-edit-select nil))

(defun igo-editor-mark-edit-board-click ()
  (interactive)
  (let ((ev (igo-editor-last-input-event-as-intersection-click)))
    (if ev
        (let* ((editor (plist-get ev :editor))
               (pos (plist-get ev :pos))
               (game (igo-editor-game editor))
               (curr-node (igo-game-current-node game))
               (mark-type (igo-editor-get-mode-property editor :mark-type)))

          ;; Rewrite the mark on the intersection POS.
          (cond
           ((eq mark-type 'text)
            (igo-node-set-mark-at curr-node pos mark-type
                                     (read-string "Text: ")))
           ((or (eq mark-type 'cross)
                (eq mark-type 'circle)
                (eq mark-type 'square)
                (eq mark-type 'triangle))
            (igo-node-set-mark-at curr-node pos mark-type))
           ((null mark-type)
            (igo-node-delete-mark-at curr-node pos)))

          ;; Update
          (igo-editor-update-on-modified editor)))))

;; Editor - Comment

(defun igo-editor-edit-comment (&optional editor)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))

  (let ((curr-node (igo-editor-current-node editor)))
    (if curr-node
        (let* ((old-comment (or (igo-node-get-comment curr-node) ""))
               (new-comment (read-from-minibuffer "Comment: " old-comment)))
          (when (not (string= new-comment old-comment))
            (if (string= new-comment "")
                (igo-node-delete-comment curr-node)
              (igo-node-set-comment curr-node new-comment))
            (igo-editor-update-on-modified editor))))))

(defun igo-editor-show-comment (&optional editor)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))
  (let ((curr-node (igo-editor-current-node editor)))
    (if curr-node
        (let ((comment (igo-node-get-comment curr-node)))
          (when comment
            (message "%s" comment)
            t)))))

;; Editor - Initialize

(defun igo-editor-init-board (&optional editor)
  (interactive)
  (if (null editor) (setq editor (igo-editor-at)))
  (if editor
      (let* ((board (igo-editor-board editor))
             (default-w (if board (igo-board-w board) igo-board-default-w))
             (default-h (if board (igo-board-h board) igo-board-default-h))
             (w (read-number "Board Width(1-52): " default-w))
             (h (read-number "Board Height(1-52): " default-h))
             (new-game (igo-game w h)))

        ;; Update buffer text
        (igo-editor-update-buffer-text-forced editor new-game)

        ;; Update editor
        (igo-editor-update editor))))

;;
;; model
;;

(defun igo-editor-make-game-from-sgf-buffer (begin end) ;;@todo igo-model.elへ移動すべき。igo-game-from-sgf-bufferみたいな名前で。
  (let* ((sgf-tree
          (save-excursion
            (save-restriction
              (narrow-to-region begin end)
              (goto-char (point-min))
              (igo-sgf-parse-tree (current-buffer)))))
         (game-tree (igo-sgf-root-tree-to-game-tree sgf-tree))
         (size (igo-sgf-tree-get-board-size sgf-tree))
         (game (igo-game (car size) (cdr size) game-tree)))

    game))

;;
;; UI
;;

(setq igo-ui-font-family "Times New Roman")
(setq igo-ui-font-h 18)
(setq igo-ui-font-ascent 16)
(setq igo-ui-button-padding-v 4)
(setq igo-ui-button-padding-h 8)
(setq igo-ui-button-margin-v 4)
(setq igo-ui-button-margin-h 4)
(setq igo-ui-button-h (+ (* 2 igo-ui-button-padding-v) igo-ui-font-h))
(setq igo-ui-bar-h (+ (* 2 igo-ui-button-margin-v)
                      (* 2 igo-ui-button-padding-v)
                      igo-ui-font-h))
(setq igo-ui-bar-padding-v 4)
(setq igo-ui-bar-padding-h 4)

(defun igo-ui-text-width (text)
  (/ (* igo-ui-font-h (string-width text)) 2))

(defun igo-ui-create-bar (svg bar-x bar-y bar-w id)
  (let* ((bar (svg-node svg 'g :class "ui-bar" :id id))
         (bar-h igo-ui-bar-h))
    (svg-rectangle bar bar-x bar-y bar-w bar-h :fill "#333")
    bar))

(defun igo-ui-create-button (svg id pos text image-map image-scale)
  (let* ((text-w (igo-ui-text-width text))
         (btn-x (car pos))
         (btn-y (cdr pos))
         (btn-w (+ (* 2 igo-ui-button-padding-h) text-w))
         (btn-h igo-ui-button-h)
         (r (/ igo-ui-font-h 3))
         (group (svg-node svg 'g
                          :id (symbol-name id)
                          :transform (format "translate(%s %s)" btn-x btn-y))))
    (svg-rectangle
     group 0 0 btn-w btn-h :rx r :ry r :fill "#fff")
    (svg-text
     group text
     :x (/ btn-w 2)
     :y (+ igo-ui-button-padding-v igo-ui-font-ascent)
     :font-family igo-ui-font-family
     :font-size igo-ui-font-h
     :text-anchor "middle")
    ;; Advance POS
    (incf (car pos) (+ btn-w igo-ui-button-margin-h))
    ;; Add clickable area to map property of Image Descriptor
    (igo-ui-push-clickable-rect image-map id btn-x btn-y btn-w btn-h image-scale)))

(defun igo-ui-push-clickable-rect (image-map id x y w h image-scale)
  (if image-map
      (let ((left (floor (* (float x) image-scale)))
            (top (floor (* (float y) image-scale)))
            (right (ceiling (* (float (+ x w)) image-scale)))
            (bottom (ceiling (* (float (+ y h)) image-scale))))
        (push (list
               (cons 'rect (cons (cons left top) (cons right bottom)))
               id
               (list 'pointer 'hand))
              (car image-map)))))

(defun igo-ui-find-clickable-area (image-map id)
  (seq-find (lambda (area) (eq (cadr area) id)) (car image-map)))

(defun igo-ui-left-top-of-clickable-area (image-map id)
  (let* ((area (igo-ui-find-clickable-area image-map id))
         (shape (car area)))
    (if shape
        (cond
         ((eq (car shape) 'rect) (cadr shape))
         ;;@todo circle
         ;;@todo poly
         ))))

(defun igo-ui-remove-clickable-area (image-map id)
  ;; @todo Use cl-remove-if?
  (let ((areas (car image-map))
        prev)
    (while (and areas (not (eq (cadr (car areas)) id)))
      (setq prev areas)
      (setq areas (cdr areas)))
    (if areas
        (if prev
            (setcdr prev (cdr areas))
          (setcar image-map (cdr areas)))))
  image-map)

(defun igo-ui-remove-clickable-areas-under (image-map dom-node)
  "Remove all clickable areas from IMAGE-MAP that matches the id of children of DOM-NODE."
  ;;@todo all children? all descendants?
  (dolist (child (dom-children dom-node))
    (let ((child-id (dom-attr child 'id)))
      (if child-id
          (igo-ui-remove-clickable-area image-map (intern child-id))))))

(provide 'igo-editor)
;;; igo-editor.el ends here
