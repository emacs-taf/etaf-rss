;;; etaf-rss-theme.el --- Palette and ETAF UI theme for etaf-rss -*- lexical-binding: t; -*-

;; Copyright (C) 2026 ETAF contributors
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;;
;; The reader paints its own surface instead of borrowing the user's Emacs
;; theme, so it looks the same in every session.  `etaf-rss-color' is the
;; palette lookup used by the Views; `etaf-rss-theme-defaults' projects the
;; same palette onto the ETAF UI token contract consumed by etaf-ui Components
;; (buttons, inputs, progress bars).

;;; Code:

(require 'etaf)

(define-error 'etaf-rss-error "RSS reader error")

(defgroup etaf-rss nil
  "RSS reader built with ETAF and Ebox."
  :group 'applications)

(defconst etaf-rss--palettes
  '((dark :bg "#0E1116" :panel "#141920" :panel2 "#1A212B" :panel3 "#222B37"
          :line "#232C39" :line-soft "#1B222C" :ink "#E9EDF3" :muted "#98A3B3"
          :dim "#647080" :accent "#E8A33D" :accent-soft "#2B2317" :gold "#E8A33D"
          :ok "#4FBF8B" :warn "#E8A33D" :danger "#FF7A85" :danger-bg "#3A1E24"
          :info "#6FB4E8" :selected "#1E2733" :unread "#E9EDF3" :read "#7C8798"
          :feed "#7FB3E8" :quote "#9CB4D4" :time "#6C7789")
    (light :bg "#FFFFFF" :panel "#F7F8FA" :panel2 "#EDF0F4" :panel3 "#E2E7ED"
           :line "#E2E7ED" :line-soft "#EEF1F5" :ink "#1B2431" :muted "#5A6472"
           :dim "#8B94A2" :accent "#B26A10" :accent-soft "#FBF0DD" :gold "#A86B14"
           :ok "#2E7D5B" :warn "#A86B14" :danger "#C0392B" :danger-bg "#FBE4E2"
           :info "#2C6FA8" :selected "#F0F2F6" :unread "#1B2431" :read "#6C7686"
           :feed "#2C6FA8" :quote "#3F66A0" :time "#7A8494"))
  "Palette of every supported appearance, keyed by mode.")

(defcustom etaf-rss-theme-mode 'dark
  "Appearance used by a new reader session.
`dark' (default) renders the reader's own dark surface and `light' the light
one; this is independent of the active Emacs theme."
  :type '(choice (const :tag "Dark" dark) (const :tag "Light" light))
  :group 'etaf-rss)

(defun etaf-rss-color (key &optional mode)
  "Return the palette color named KEY.
MODE defaults to `etaf-rss-theme-mode'; an unknown mode falls back to `dark'.
An unknown KEY signals `etaf-rss-error' instead of returning a fallback,
because a typo would otherwise paint an invisible surface."
  (let* ((mode (let ((mode (or mode etaf-rss-theme-mode)))
                 (if (assq mode etaf-rss--palettes) mode 'dark)))
         (palette (cdr (assq mode etaf-rss--palettes)))
         (color (plist-get palette key)))
    (unless (and (keywordp key) color)
      (signal 'etaf-rss-error (list (format "Unknown color: %S" key))))
    color))

(defun etaf-rss-theme-defaults (&optional mode)
  "Return the ETAF UI token plist for MODE.
MODE defaults to `etaf-rss-theme-mode'.  The result is passed to
`etaf-theme-provide' by the application so shared etaf-ui Components use the
same colors as the reader's own Views."
  (let* ((dark (eq (or mode etaf-rss-theme-mode) 'dark))
         (bg (etaf-rss-color :bg mode))
         (panel (etaf-rss-color :panel mode))
         (panel3 (etaf-rss-color :panel3 mode))
         (ink (etaf-rss-color :ink mode))
         (line (etaf-rss-color :line mode))
         (muted (etaf-rss-color :muted mode))
         (accent (etaf-rss-color :accent mode))
         (accent-soft (etaf-rss-color :accent-soft mode))
         (ok (etaf-rss-color :ok mode))
         (ok-bg (if dark "#17301F" "#E3F3E8"))
         (ok-border (if dark "#2E5C3F" "#A9D8BB"))
         (danger (etaf-rss-color :danger mode))
         (danger-bg (if dark "#3A1E24" "#FBE4E2"))
         (danger-border (if dark "#7A2A2C" "#E8B4AE"))
         (warn (etaf-rss-color :warn mode))
         (warn-bg (if dark "#33280F" "#FBF0DA"))
         (warn-border (if dark "#6B5423" "#E0C48A"))
         (info (etaf-rss-color :info mode))
         (info-bg (if dark "#14232F" "#E4F0FA"))
         (info-border (if dark "#2C4E66" "#A8CBE6")))
    (list
     :ink ink :paper bg :panel panel :line line :muted muted
     :accent accent :accent-soft accent-soft
     :ui-fg ink :ui-bg bg :ui-border line :ui-muted-fg muted
     :ui-disabled-fg muted :ui-disabled-bg panel :ui-disabled-border line
     :ui-accent accent :ui-accent-fg "#FFFFFF" :ui-accent-soft-bg accent-soft
     :ui-button-primary-fg "#FFFFFF" :ui-button-primary-bg accent
     :ui-button-secondary-fg accent :ui-button-secondary-bg accent-soft
     :ui-button-ghost-fg muted
     :ui-success-fg ok :ui-success-bg ok-bg :ui-success-border ok-border
     :ui-danger-fg danger :ui-danger-bg danger-bg :ui-danger-border danger-border
     :ui-warning-fg warn :ui-warning-bg warn-bg :ui-warning-border warn-border
     :ui-info-fg info :ui-info-bg info-bg :ui-info-border info-border
     :ui-panel-fg ink :ui-panel-bg panel :ui-panel-border line
     :ui-divider-bg line
     :ui-progress-track panel3 :ui-progress-value accent
     :ui-table-border line :ui-table-selected-fg accent
     :ui-table-selected-bg accent-soft
     :ui-shell-bg panel :ui-shell-fg ink :ui-shell-muted-fg muted
     :ui-shell-item-fg muted :ui-shell-item-minimized-fg muted
     :ui-window-bg bg :ui-window-fg ink :ui-window-border line
     :ui-window-title-bg panel :ui-window-title-fg muted
     :ui-window-title-active-fg ink
     :ui-picker-item-bg panel :ui-picker-item-fg ink
     :ui-picker-item-muted-fg muted
     :ui-pagination-muted-fg muted
     :ui-data-grid-error-fg danger
     :ui-checkbox-enabled-fg ink :ui-checkbox-disabled-fg muted)))

(provide 'etaf-rss-theme)
;;; etaf-rss-theme.el ends here
