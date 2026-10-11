;;; etaf-rss-app.el --- Application shell of the RSS reader -*- lexical-binding: t; -*-

;; Copyright (C) 2026 ETAF contributors
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; The application layer binds one reader model to the Views.  `etaf-rss-app'
;; is the only place that reads the model's reactive sources, so a service
;; reply or a key press repaints the whole reader in one place, and it owns
;; the session lifecycle: the palette is provided for its subtree, the reader
;; loads on mount, and the session's timers and pending requests are released
;; on unmount.
;;
;; `etaf-rss-open' adds what a Component cannot own by itself: the buffer
;; name, the buffer-local keymap, and the window-fitted page size.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'etaf)
(require 'etaf-ui)
(require 'etaf-rss-theme)
(require 'etaf-rss-service)
(require 'etaf-rss-model)
(require 'etaf-rss-views)

;;; ---------------------------------------------------------------------------
;;; Buffer state and keymap
;;; ---------------------------------------------------------------------------

(defcustom etaf-rss-buffer-name "*ETAF RSS*"
  "Buffer opened by `etaf-rss-open'."
  :type 'string
  :group 'etaf-rss)

(defvar-local etaf-rss--model nil
  "Reader session shown by the current buffer's runtime.")

(defvar etaf-rss-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-n") #'etaf-rss--next-row)
    (define-key map (kbd "C-p") #'etaf-rss--previous-row)
    (define-key map (kbd "n") #'etaf-rss--next-unread)
    (define-key map (kbd "p") #'etaf-rss--previous-unread)
    (define-key map (kbd "<wheel-up>") #'etaf-rss--wheel-up)
    (define-key map (kbd "<wheel-down>") #'etaf-rss--wheel-down)
    (define-key map (kbd "<home>") #'etaf-rss--first-row)
    (define-key map (kbd "<end>") #'etaf-rss--last-row)
    (define-key map (kbd "<next>") #'etaf-rss--next-page)
    (define-key map (kbd "<prior>") #'etaf-rss--previous-page)
    (define-key map (kbd "RET") #'etaf-rss--activate)
    (define-key map (kbd "o") #'etaf-rss--open-in-browser)
    (define-key map (kbd "s") #'etaf-rss--toggle-star)
    (define-key map (kbd "m") #'etaf-rss--toggle-read)
    (define-key map (kbd "A") #'etaf-rss--mark-all-read)
    (define-key map (kbd "M") #'etaf-rss--mark-above-read)
    (define-key map (kbd "a") #'etaf-rss--prompt-add-feed)
    (define-key map (kbd "d") #'etaf-rss--prompt-remove-feed)
    (define-key map (kbd "i") #'etaf-rss--import-opml)
    (define-key map (kbd "e") #'etaf-rss--export-opml)
    (define-key map (kbd "/") #'etaf-rss--search)
    (define-key map (kbd "S") #'etaf-rss--search)
    (define-key map (kbd "1") #'etaf-rss--all)
    (define-key map (kbd "2") #'etaf-rss--unread)
    (define-key map (kbd "3") #'etaf-rss--starred)
    (define-key map (kbd "v") #'etaf-rss--toggle-pane)
    (define-key map (kbd "g") #'etaf-rss--refresh)
    (define-key map (kbd "R") #'etaf-rss--refresh-all)
    (define-key map (kbd "G") #'etaf-rss--last-row)
    (define-key map (kbd "T") #'etaf-rss--cycle-theme)
    (define-key map (kbd "C-c h") #'etaf-rss--help)
    (define-key map (kbd "q") #'etaf-rss-close)
    map)
  "Keymap of the buffer opened by `etaf-rss-open'.
It keeps Ebox's TAB focus cycling and RET activation and replaces the
scrolling keys with reader commands: arrows move the selection and SPC
scrolls the article.")

(defun etaf-rss--direction (direction)
  "Move the RSS selection with DIRECTION and return the result symbol."
  (pcase direction
    ('down (etaf-rss--next-row) 'handled)
    ('up (etaf-rss--previous-row) 'handled)
    (_ 'release)))

(defvar etaf-rss--command-maps
  (list (cons 'etaf-rss--model
              (let ((map (make-sparse-keymap)))
                (define-key map [wheel-up] #'etaf-rss--wheel-up)
                (define-key map [wheel-down] #'etaf-rss--wheel-down)
                ;; These are scroll or window keys in the renderer's own
                ;; minor-mode map, which wins over a major-mode map.  The
                ;; reader owns them here where it can win.
                (define-key map (kbd "n") #'etaf-rss--next-unread)
                (define-key map (kbd "q") #'etaf-rss-close)
                (define-key map (kbd "<next>") #'etaf-rss--next-page)
                (define-key map (kbd "<prior>") #'etaf-rss--previous-page)
                (define-key map (kbd "C-v") #'etaf-rss--scroll-page-down)
                (define-key map (kbd "M-v") #'etaf-rss--scroll-page-up)
                (define-key map (kbd "SPC") #'etaf-rss--scroll-page-down)
                (define-key map (kbd "S-SPC") #'etaf-rss--scroll-page-up)
                (define-key map (kbd "RET") #'etaf-rss--activate)
                map)))
  "Reader bindings that must beat the renderer's own minor-mode map.
`emulation-mode-map-alists' entries take precedence over every minor mode, so
this alist lets the reader replace renderer scroll keys instead of having
them silently shadowed.  The alist is enabled only in an opened buffer.")

(defun etaf-rss--current-model ()
  "Return the model of the current RSS reader buffer."
  (or etaf-rss--model
      (user-error "当前 buffer 不是 etaf-rss 阅读器")))

;;; ---------------------------------------------------------------------------
;;; Commands
;;; ---------------------------------------------------------------------------

(defun etaf-rss--next-row ()
  "Select the next article."
  (interactive)
  (etaf-rss-move-selection (etaf-rss--current-model) 1))

(defun etaf-rss--previous-row ()
  "Select the previous article."
  (interactive)
  (etaf-rss-move-selection (etaf-rss--current-model) -1))

(defun etaf-rss--next-unread ()
  "Select the next unread article."
  (interactive)
  (etaf-rss-next-unread (etaf-rss--current-model) 1))

(defun etaf-rss--previous-unread ()
  "Select the previous unread article."
  (interactive)
  (etaf-rss-next-unread (etaf-rss--current-model) -1))

(defun etaf-rss--first-row ()
  "Select the first article."
  (interactive)
  (etaf-rss-select-first (etaf-rss--current-model)))

(defun etaf-rss--last-row ()
  "Select the last article."
  (interactive)
  (etaf-rss-select-last (etaf-rss--current-model)))

(defun etaf-rss--next-page ()
  "Select one page further down the article list."
  (interactive)
  (etaf-rss-move-selection (etaf-rss--current-model)
                           (max 1 (etaf-rss--read (etaf-rss--current-model)
                                                  :page-size))))

(defun etaf-rss--previous-page ()
  "Select one page further up the article list."
  (interactive)
  (etaf-rss-move-selection (etaf-rss--current-model)
                           (- (max 1 (etaf-rss--read (etaf-rss--current-model)
                                                     :page-size)))))

(defun etaf-rss--list-focused-p (model)
  "Return non-nil when MODEL's single visible pane is the article list.
A wide frame shows both columns, so its arrow-free page keys scroll the
article instead."
  (and (etaf-rss--compact-layout-p model)
       (eq (etaf-rss--read model :pane) 'list)))

(defun etaf-rss--scroll-page-down ()
  "Scroll the article one page, or page the list when it owns the pane."
  (interactive)
  (let ((model (etaf-rss--current-model)))
    (if (etaf-rss--list-focused-p model)
        (etaf-rss--next-page)
      (etaf-rss-scroll-reader model
                              (max 1 (etaf-rss--read model :reader-rows))))))

(defun etaf-rss--scroll-page-up ()
  "Scroll the article one page up, or page the list when it owns the pane."
  (interactive)
  (let ((model (etaf-rss--current-model)))
    (if (etaf-rss--list-focused-p model)
        (etaf-rss--previous-page)
      (etaf-rss-scroll-reader model
                              (- (max 1 (etaf-rss--read model :reader-rows)))))))

(defun etaf-rss--activate ()
  "Open the Host at point, or the selected article in the reading pane."
  (interactive)
  (condition-case nil
      (etaf-activate)
    (user-error
     (etaf-rss-activate-selection (etaf-rss--current-model)))))

(defun etaf-rss--open-in-browser ()
  "Open the selected article in the browser."
  (interactive)
  (condition-case error
      (etaf-rss-open-article (etaf-rss--current-model))
    (etaf-rss-error (message "%s" (error-message-string error)))))

(defun etaf-rss--toggle-star ()
  "Toggle the star of the selected article."
  (interactive)
  (condition-case error
      (etaf-rss-toggle-star (etaf-rss--current-model))
    (etaf-rss-error (message "%s" (error-message-string error)))))

(defun etaf-rss--toggle-read ()
  "Toggle the read state of the selected article."
  (interactive)
  (condition-case error
      (etaf-rss-toggle-read (etaf-rss--current-model))
    (etaf-rss-error (message "%s" (error-message-string error)))))

(defun etaf-rss--mark-all-read ()
  "Mark every article of the current scope read, after a confirmation."
  (interactive)
  (let* ((model (etaf-rss--current-model))
         (count (etaf-rss--read model :list-total))
         (label (etaf-rss--read model :scope-label)))
    (if (or (<= count 0)
            (yes-or-no-p (format "把「%s」的 %d 篇都标为已读？" label count)))
      (etaf-rss-mark-all-read model)
      (etaf-rss--note model "已取消"))))

(defun etaf-rss--mark-above-read ()
  "Mark the selected article and everything above it read."
  (interactive)
  (condition-case error
      (etaf-rss-mark-above-read (etaf-rss--current-model))
    (etaf-rss-error (message "%s" (error-message-string error)))))

(defun etaf-rss--prompt-add-feed ()
  "Subscribe to a feed the user types."
  (interactive)
  (let* ((model (etaf-rss--current-model))
         (url (read-string "订阅地址（RSS/Atom/JSON 或站点首页）：")))
    (when (and url (not (string-empty-p (string-trim url))))
      (let ((folder (read-string "归到文件夹（可留空）：")))
        (condition-case error
            (etaf-rss-add-feed model url folder)
          (etaf-rss-error (message "%s" (error-message-string error))))))))

(defun etaf-rss--prompt-remove-feed ()
  "Unsubscribe the feed of the current scope, after a confirmation."
  (interactive)
  (let* ((model (etaf-rss--current-model))
         (feed (and (eq (plist-get (etaf-rss--read model :scope) :kind) :feed)
                    (etaf-rss--feed model
                                    (plist-get (etaf-rss--read model :scope) :id)))))
    (cond
     ((null feed) (message "当前范围不是单个订阅：先在侧栏选中一个订阅"))
     ((yes-or-no-p (format "退订「%s」？（收藏的文章会保留）"
                           (or (plist-get feed :title) "")))
      (condition-case error
          (etaf-rss-remove-feed model (plist-get feed :id))
        (etaf-rss-error (message "%s" (error-message-string error)))))
     (t (etaf-rss--note model "已取消")))))

(defun etaf-rss--import-opml ()
  "Import subscriptions from an OPML file."
  (interactive)
  (let* ((model (etaf-rss--current-model))
         (path (read-file-name "导入 OPML：")))
    (when (and path (not (string-empty-p path)) (file-readable-p path))
      (condition-case error
          (etaf-rss-import-opml model path)
        (etaf-rss-error (message "%s" (error-message-string error)))))))

(defun etaf-rss--export-opml ()
  "Export subscriptions to an OPML file."
  (interactive)
  (let* ((model (etaf-rss--current-model))
         (path (read-file-name "导出 OPML 到：" nil nil nil "etaf-rss.opml")))
    (when (and path (not (string-empty-p path)))
      (condition-case error
          (etaf-rss-export-opml model path)
        (etaf-rss-error (message "%s" (error-message-string error)))))))

(defun etaf-rss--search ()
  "Search the stored articles for a keyword."
  (interactive)
  (let* ((model (etaf-rss--current-model))
         (keyword (read-string "搜索文章（标题、摘要或正文）：")))
    (if (or (null keyword) (string-empty-p (string-trim keyword)))
        (etaf-rss--note model "输入关键词后开始搜索")
      (condition-case error
          (etaf-rss-search model keyword)
        (etaf-rss-error (etaf-rss--note model (error-message-string error)))))))

(defun etaf-rss--all ()
  "Show every stored article."
  (interactive)
  (etaf-rss-locate (etaf-rss--current-model) :all))

(defun etaf-rss--unread ()
  "Show the unread articles."
  (interactive)
  (etaf-rss-locate (etaf-rss--current-model) :unread))

(defun etaf-rss--starred ()
  "Show the starred articles."
  (interactive)
  (etaf-rss-locate (etaf-rss--current-model) :starred))

(defun etaf-rss--toggle-pane ()
  "Switch between the article list and the reading pane."
  (interactive)
  (etaf-rss-toggle-pane (etaf-rss--current-model)))

(defun etaf-rss--refresh ()
  "Reload the sidebar and list, then re-fetch the current scope's feeds."
  (interactive)
  (etaf-rss-refresh (etaf-rss--current-model)))

(defun etaf-rss--refresh-all ()
  "Re-fetch every subscribed feed."
  (interactive)
  (let ((model (etaf-rss--current-model)))
    (etaf-rss-refresh-feeds model (list :kind :all))
    (etaf-rss--note model "正在刷新全部订阅…")))

(defun etaf-rss--wheel (event delta)
  "Scroll the reading pane or move the article selection by DELTA at EVENT."
  (let* ((position (event-start event))
         (window (posn-window position)))
    (when (window-live-p window)
      (with-current-buffer (window-buffer window)
        (let* ((model (etaf-rss--current-model))
               (pixels (posn-x-y position))
               (xy (and (consp pixels)
                        (cons (/ (float (car pixels)) (window-font-width window))
                              (/ (float (cdr pixels)) (window-font-height window))))))
          (if (and (null (posn-area position))
                   (etaf-rss--reader-hit-p
                    xy (window-body-width window)
                    (etaf-rss--read model :layout)))
              (etaf-rss-scroll-reader model delta)
            (etaf-rss-move-selection model delta)))))))

(defun etaf-rss--reader-hit-p (xy columns layout)
  "Return non-nil when text-cell position XY hits the reading pane.
COLUMNS is the body width of the event window and LAYOUT its layout."
  (and (consp xy) (numberp (car xy)) (numberp (cdr xy))
       (if (eq layout 'wide)
           (> (car xy) (+ etaf-rss--sidebar-columns
                          (etaf-rss--list-columns columns layout)))
         t)))

(defun etaf-rss--wheel-up (event)
  "Scroll the article or select the previous row at EVENT."
  (interactive "e")
  (etaf-rss--wheel event -1))

(defun etaf-rss--wheel-down (event)
  "Scroll the article or select the next row at EVENT."
  (interactive "e")
  (etaf-rss--wheel event 1))

(defun etaf-rss--cycle-theme ()
  "Switch the reader to the other palette."
  (interactive)
  (let ((model (etaf-rss--current-model)))
    (etaf-rss-cycle-theme model)
    (when-let* ((buffer (plist-get model :buffer)))
      (with-current-buffer buffer (etaf-rss--remap-canvas-face)))
    (etaf-rss--repaint-palette model)))

(defun etaf-rss--help ()
  "Show the reader's key bindings."
  (interactive)
  (message
   (concat "j/k 或滚轮选择 · 单击选中 · 双击/RET 阅读 · n/p 上下未读"
           " · s 收藏 · m 标已读 · A 全部已读 · M 以上已读"
           " · SPC/C-v 翻页 · o 浏览器打开"
           " · 1/2/3 全部/未读/收藏 · / 搜索"
           " · a 订阅 · d 退订 · i 导入 OPML · e 导出 OPML"
           " · v 切换列表/阅读 · g 刷新 · R 刷新全部 · T 深浅色 · q 关闭")))

;;; ---------------------------------------------------------------------------
;;; Buffer helpers
;;; ---------------------------------------------------------------------------

(defun etaf-rss--remap-canvas-face ()
  "Paint this buffer's unpainted cells with the palette background.
Ebox paints whole character cells, so a window body that is not a whole number
of cells keeps a sub-cell remainder at its right or bottom edge.  Remapping
the default face shows the reader background there instead of the frame's."
  (face-remap-set-base 'default (list :background (etaf-rss-color :bg))))

;;; ---------------------------------------------------------------------------
;;; Application Component and entry points
;;; ---------------------------------------------------------------------------

(defvar etaf-rss--remounting nil
  "Non-nil while the view is replaced so the palette repaints.
The unmount before the new mount must not dispose the session, and the mount
itself must not load the feeds again.")

(defconst etaf-rss--footer-hint
  "j/k 选择 · RET 阅读 · s 收藏 · m 已读 · g 刷新 · / 搜索 · ? 帮助"
  "Binding summary at the right edge of the reader's status bar.")

(etaf-define-component etaf-rss--app-sidebar
    (&key session compact on-locate on-toggle on-add on-import on-export)
  "Render the subscription sidebar for SESSION.
This child reads only the subscription state, so a selection or reading
change never re-renders it."
  :view
  (etaf-rss--view-sidebar
   :compact compact
   :smart (nth 0 (etaf-rss--sidebar session))
   :folders (nth 1 (etaf-rss--sidebar session))
   :on-locate on-locate :on-toggle on-toggle
   :on-add on-add :on-import on-import :on-export on-export))

(etaf-define-component etaf-rss--app-header
    (&key session on-search on-refresh on-add on-locate)
  "Render the content header and the narrow layout's scope chips."
  :view
  (flex :flex-direction 'column :width 'stretch :flex-shrink 0
        :gap '((lh 0) (ch 0))
    (etaf-rss--view-header
     :title (etaf-rss--read session :scope-label)
     :subtitle (etaf-rss--read session :scope-subtitle)
     :refreshing (etaf-rss--read session :refreshing)
     :loading (etaf-rss--read session :loading)
     :sources (when (eq (etaf-rss--read session :layout) 'narrow)
                (etaf-rss--source-menu session))
     :on-locate on-locate
     :on-search on-search :on-refresh on-refresh :on-add on-add)
    (box :if (eq (etaf-rss--read session :layout) 'narrow) :height '(lh 1))
    (etaf-rss--view-chips
     :if (eq (etaf-rss--read session :layout) 'narrow)
     :smart (nth 0 (etaf-rss--sidebar session))
     :on-locate on-locate)))

(etaf-define-component etaf-rss--app-list (&key session on-press)
  "Render the article list for SESSION.
Only writes to the list state (selection, rows, loading) re-render this
child; the keyed rows keep their instances, so a move touches two rows."
  :view
  (etaf-rss--view-list
   :entries (etaf-rss--view-entries session)
   :start (1+ (nth 1 (etaf-rss--page-rows session)))
   :total (etaf-rss--read session :list-total)
   :loaded (length (etaf-rss--read session :rows))
   :compact (eq (etaf-rss--read session :layout) 'narrow)
   :loading (etaf-rss--read session :loading)
   :refreshing (etaf-rss--read session :refreshing)
   :empty-note (etaf-rss--empty-note session)
   :on-press on-press))

(etaf-define-component etaf-rss--app-reader (&key session)
  "Render the reading pane for SESSION.
It re-renders when the open article, its lines or its scroll change, never
when the list selection does."
  :view
  (etaf-rss--view-reader
   :title (etaf-rss--read session :reader-title)
   :meta (etaf-rss--read session :reader-meta)
   :lines (etaf-rss--visible-lines session)
   :loading (etaf-rss--read session :reader-loading)
   :error (etaf-rss--read session :reader-error)
   :starred (etaf-rss--read session :reader-starred)
   :scroll (etaf-rss--read session :reader-scroll)
   :total (length (etaf-rss--read session :reader-lines))
   :empty-note "选择左边的文章开始阅读"))

(etaf-define-component etaf-rss--app-footer (&key session)
  "Render the status bar of SESSION."
  :view
  (etaf-rss--view-footer
   :message (etaf-rss--read session :message)
   :error (etaf-rss--read session :error)
   :summary (etaf-rss--read session :scope-subtitle)
   :refreshing (etaf-rss--read session :refreshing)
   :done (etaf-rss--read session :refresh-done)
   :total (etaf-rss--read session :refresh-total)
   :compact (etaf-rss--compact-layout-p session)
   :hint (if (etaf-rss--compact-layout-p session)
             "j/k · RET · g · ?"
           etaf-rss--footer-hint)))

(etaf-define-component etaf-rss-app (&key model)
  "Render the RSS reader for MODEL and own its session lifecycle.
MODEL must come from `etaf-rss-create'.  Mounting provides the palette for
its subtree, fits the layout and loads the feed list; unmounting releases the
session's timers and pending requests.  The shell reads only the layout and
pane choice; each pane is a child Component with its own state reads, so an
interaction repaints the smallest subtree that changed."
  :bindings ((session (or model
                          (signal 'etaf-rss-error
                                  '("etaf-rss-app needs the :model from `etaf-rss-create'"))))
             (palette (etaf-rss--ref session :theme))
             (on-locate (lambda (scope) (etaf-rss-locate session scope)))
             (on-select-source (lambda (key)
                                 (etaf-rss-locate
                                  session
                                  (if (member key '(:all :unread :starred))
                                      key
                                    (list :kind :feed :id key)))))
             (on-toggle (lambda (name) (etaf-rss-toggle-folder session name)))
             (on-search (lambda () (etaf-rss--search-in session)))
             (on-refresh (lambda () (etaf-rss-refresh session)))
             (on-add (lambda () (etaf-rss--add-in session)))
             (on-import (lambda () (etaf-rss--import-in session)))
             (on-export (lambda () (etaf-rss--export-in session)))
             (on-press (lambda (index) (etaf-rss-press-row session index)))
             (on-pane (lambda (target) (etaf-rss-show-pane session target))))
  :setup
  (progn
    (etaf-theme-provide palette)
    (etaf-on-mounted
     (lambda ()
       (etaf-rss--start session)
       (unless etaf-rss--remounting
         (etaf-rss-refresh session))))
    (etaf-on-unmounted
     (lambda ()
       (unless etaf-rss--remounting
         (etaf-rss--dispose session)))))
  :view
  (flex :flex-direction 'column :width '(vw 100) :height '(vh 100)
        :padding-top '(lh 1) :padding-bottom '(lh 1)
        :on-direction #'etaf-rss--direction
        :color (etaf-rss-color :ink) :bgcolor (etaf-rss-color :bg)
    (flex :width 'stretch :flex-grow 1 :flex-basis 'auto :min-height '(lh 0)
          :align-items 'stretch
      (etaf-rss--app-sidebar
       :if (eq (etaf-rss--read session :layout) 'wide)
       :session session
       :on-locate on-locate :on-toggle on-toggle
       :on-add on-add :on-import on-import :on-export on-export)
      (etaf-rss--app-sidebar
       :if (eq (etaf-rss--read session :layout) 'medium)
       :compact t :session session
       :on-locate on-locate :on-toggle on-toggle
       :on-add on-add :on-import on-import :on-export on-export)
      (flex :if (or (not (etaf-rss--compact-layout-p session))
                    (eq (etaf-rss--read session :pane) 'list))
            :flex-direction 'column :flex-grow 1 :flex-basis '(ch 0)
            :min-width '(ch 0) :min-height '(lh 0)
            :padding '((lh 1) (ch 2))
            :gap '((lh 0) (ch 0))
        (etaf-rss--app-header
         :session session
         :on-search on-search :on-refresh on-refresh :on-add on-add
         :on-locate on-select-source)
        (etaf-rss--app-list :session session :on-press on-press))
      (etaf-rss--app-reader
       :if (or (not (etaf-rss--compact-layout-p session))
               (eq (etaf-rss--read session :pane) 'reader))
       :session session))
    (etaf-rss--view-tabs
     :if (etaf-rss--compact-layout-p session)
     :pane (etaf-rss--read session :pane)
     :layout (etaf-rss--read session :layout)
     :on-pane on-pane)
    (etaf-rss--app-footer :session session)))

(defun etaf-rss--source-menu (session)
  "Return SESSION's source chooser: the fixed scopes, folders and feeds.
It is the narrow layout's replacement for the sidebar, so every scope stays
reachable with one menu selection; the keys are scope keywords for the fixed
scopes and feed IDs for feeds."
  (let ((sidebar (etaf-rss--sidebar session)))
    (append
     (mapcar (lambda (item)
               (list :key (plist-get item :key) :label (plist-get item :label)))
             (nth 0 sidebar))
     (cl-loop for folder in (nth 1 sidebar)
              unless (plist-get folder :top)
              append (cons (list :key (format "folder:%s" (plist-get folder :name))
                                 :label (format "文件夹 · %s" (plist-get folder :name))
                                 :disabled t)
                           (mapcar (lambda (feed)
                                     (list :key (plist-get feed :id)
                                           :label (format "    %s" (plist-get feed :title))))
                                   (plist-get folder :feeds)))))))

(defun etaf-rss--empty-note (session)
  "Return the empty-list note for SESSION's current state."
  (cond
   ((etaf-rss--read session :loading) "正在加载…")
   ((eq (plist-get (etaf-rss--read session :scope) :kind) :search)
    "没有匹配的文章：换个关键词，或按 1 回到全部")
   ((zerop (length (etaf-rss--read session :feeds)))
    "还没有订阅：按 a 添加地址，或 i 导入 OPML")
   (t "这里还没有文章：按 g 刷新")))

(defun etaf-rss--search-in (session)
  "Prompt for a keyword and search SESSION, reporting a blank one."
  (let ((keyword (read-string "搜索文章（标题、摘要或正文）：")))
    (if (or (null keyword) (string-empty-p (string-trim keyword)))
        (etaf-rss--note session "输入关键词后开始搜索")
      (condition-case error
          (etaf-rss-search session keyword)
        (etaf-rss-error (etaf-rss--note session (error-message-string error)))))))

(defun etaf-rss--add-in (session)
  "Prompt for a feed address and subscribe SESSION to it."
  (let ((url (read-string "订阅地址（RSS/Atom/JSON 或站点首页）：")))
    (when (and url (not (string-empty-p (string-trim url))))
      (let ((folder (read-string "归到文件夹（可留空）：")))
        (condition-case error
            (etaf-rss-add-feed session url folder)
          (etaf-rss-error (etaf-rss--note session (error-message-string error))))))))

(defun etaf-rss--import-in (session)
  "Prompt for an OPML file and import it into SESSION."
  (let ((path (read-file-name "导入 OPML：")))
    (when (and path (not (string-empty-p path)) (file-readable-p path))
      (condition-case error
          (etaf-rss-import-opml session path)
        (etaf-rss-error (etaf-rss--note session (error-message-string error)))))))

(defun etaf-rss--export-in (session)
  "Prompt for an OPML target and export SESSION's subscriptions."
  (let ((path (read-file-name "导出 OPML 到：" nil nil nil "etaf-rss.opml")))
    (when (and path (not (string-empty-p path)))
      (condition-case error
          (etaf-rss-export-opml session path)
        (etaf-rss-error (etaf-rss--note session (error-message-string error)))))))

(defun etaf-rss--repaint-palette (model)
  "Repaint MODEL's buffer after its palette changed.
The Views resolve their colors from the palette when they render, and a
Component instance is retained while its props are unchanged, so the view is
replaced; the session keeps its content and timers."
  (when-let* ((buffer (plist-get model :buffer)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when-let* ((runtime (etaf-runtime-for-buffer buffer)))
          (let ((etaf-rss--remounting t))
            (etaf-unmount runtime)
            (etaf-mount buffer (etaf-rss-view model))
            (etaf-runtime-flush (etaf-runtime-for-buffer buffer))))))))

(defun etaf-rss-view (&optional model)
  "Return the reader View for MODEL.
MODEL defaults to a new session, exactly as `etaf-rss-open' creates one; pass
a session from `etaf-rss-create' to embed the reader in your own mount."
  (etaf-view (etaf-rss-app :model (or model (etaf-rss-create)))))

(defun etaf-rss-open (&optional model)
  "Open the RSS reader and return its buffer.
MODEL defaults to a session from `etaf-rss-create', so the reader opens on
every stored article.  A caller-provided MODEL keeps its scope, selection and
open article, and is revived when it was displayed before.  The reader
replaces the selected window instead of following `display-buffer' rules that
might split the frame, and closing the buffer releases its timers and pending
requests, so a later `etaf-rss-open' with the same MODEL works again."
  (interactive)
  (let* ((model (or model (etaf-rss-create)))
         (buffer (get-buffer-create etaf-rss-buffer-name)))
    (plist-put model :buffer buffer)
    (with-current-buffer buffer
      (setq-local etaf-rss--model model)
      (setq-local truncate-lines t)
      (setq-local mode-line-format nil)
      (setq-local emulation-mode-map-alists
                  (cons 'etaf-rss--command-maps
                        (remq 'etaf-rss--command-maps emulation-mode-map-alists)))
      ;; The reader owns every column it paints.  A sub-cell rounding
      ;; remainder must not surface as Emacs's truncation glyph.
      (setq-local buffer-display-table
                  (let ((table (copy-sequence (or standard-display-table
                                                  (make-display-table)))))
                    (set-display-table-slot table 'truncation ?\s)
                    table))
      (etaf-rss--remap-canvas-face)
      (use-local-map etaf-rss-mode-map))
    ;; A native text app owns the window it was opened from: a general
    ;; `display-buffer' rule must not split the frame into a playground-style
    ;; pane, so open in the selected window and let the app fill it.
    (let ((display-buffer-overriding-action '((display-buffer-same-window))))
      (pop-to-buffer buffer))
    ;; The layout, page size and reading width come from the window that shows
    ;; the reader, so the first paint already fits it.
    (etaf-rss--sync-layout model (selected-window))
    ;; The mount tracks the window's pixel width, so the reader follows
    ;; resizes and windows that show it later.
    (etaf-mount buffer (etaf-rss-view model))
    (etaf-runtime-flush (etaf-runtime-for-buffer buffer))
    buffer))

(defun etaf-rss-close ()
  "Unmount the reader and kill its buffer."
  (interactive)
  (when-let* ((runtime (etaf-runtime-for-buffer etaf-rss-buffer-name)))
    (etaf-unmount runtime))
  (when-let* ((buffer (get-buffer etaf-rss-buffer-name)))
    (kill-buffer buffer)))

(provide 'etaf-rss-app)
;;; etaf-rss-app.el ends here
